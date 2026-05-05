// WndrApp_iPad.swift
// iPadOS entry point for the Wndr research workspace.
// Provides feature parity with the macOS version, optimized for touch and Apple Pencil.

import PDFKit
import SwiftUI
import WndrKit
import WndrData
import WndrPDF
import WndrNotes

@main
struct WndrApp_iPad: App {
    @StateObject private var environment = AppEnvironment_iPad()

    var body: some Scene {
        WindowGroup {
            RootView_iPad()
                .environmentObject(environment)
        }
    }
}

// MARK: - Root View

private struct RootView_iPad: View {
    @EnvironmentObject private var environment: AppEnvironment_iPad
    @StateObject private var sidebarViewModel = LibrarySidebarViewModel()
    @StateObject private var contentViewModel = ContentAreaViewModel()
    @State private var availableTags: [DocumentTagItem] = []
    @State private var availableCollections: [CollectionMenuItem] = []

    var body: some View {
        Group {
            if environment.libraryURL == nil && environment.isBootstrapped {
                LibrarySetupView_iPad()
            } else if environment.libraryURL != nil {
                ContentWrapper_iPad(
                    environment: environment,
                    sidebarViewModel: sidebarViewModel,
                    contentViewModel: contentViewModel,
                    availableTags: availableTags,
                    availableCollections: availableCollections,
                    onToggleTag: handleToggleTag,
                    onRenameTag: handleRenameTag,
                    onRenameCollection: handleRenameCollection,
                    onDeleteTag: handleDeleteTag,
                    onDeleteCollection: handleDeleteCollection,
                    onRenameDocument: handleRenameDocument,
                    onDeleteDocument: handleDeleteDocument,
                    onSetDocumentCollection: handleSetDocumentCollection,
                    onDropDocumentOnCollection: { documentID, collectionID in
                        handleSetDocumentCollection(documentID: documentID, collectionID: collectionID)
                    },
                    onUpdateDocumentMetadata: handleUpdateDocumentMetadata
                )
                .environment(\.managedObjectContext, environment.persistenceController.viewContext)
                .onAppear {
                    setupViewModels()
                }
            } else {
                ProgressView("Starting Wndr…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await environment.bootstrap()
        }
        .alert(item: $environment.libraryCoordinator.activeAlert) { alert in
            alert.toSwiftUIAlert()
        }
        .alert(item: $environment.importCoordinator.activeAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
        .overlay {
            if environment.importCoordinator.isImporting,
               let progress = environment.importCoordinator.importProgress {
                ImportProgressView_iPad(progress: progress)
            }
        }
        .onChange(of: environment.importCoordinator.isImporting) { _, newValue in
            if !newValue {
                refreshDocumentList()
            }
        }
    }

    // MARK: - Thumbnail Helpers

    private func thumbnailURL(for documentID: UUID) -> URL? {
        guard let libraryURL = environment.libraryURL else { return nil }
        let indexURL = libraryURL.appendingPathComponent("Index", isDirectory: true)
        let thumbURL = indexURL.appendingPathComponent("Thumbnails", isDirectory: true)
            .appendingPathComponent("\(documentID.uuidString).png")
        return FileManager.default.fileExists(atPath: thumbURL.path) ? thumbURL : nil
    }

    // MARK: - ViewModel Setup (same logic as macOS)

    private func setupViewModels() {
        contentViewModel.onImport = {
            environment.importCoordinator.presentImportPicker()
        }

        contentViewModel.onCreateNote = { [weak environment, weak contentViewModel] title in
            guard let env = environment else { return nil }
            do {
                let noteID = try await env.documentService.createNote(title: title)
                await MainActor.run {
                    contentViewModel?.notes = env.documentService.notes.map { dto in
                        NoteItem(
                            id: dto.id,
                            title: dto.title,
                            preview: dto.preview,
                            pinned: dto.pinned,
                            createdAt: dto.createdAt,
                            updatedAt: dto.updatedAt
                        )
                    }
                }
                return noteID
            } catch {
                return nil
            }
        }

        contentViewModel.onContentSearch = { [weak environment, weak contentViewModel] query in
            guard let env = environment, let vm = contentViewModel else { return }

            let noteMatches = env.documentService.searchNoteContent(query: query)
            for note in noteMatches {
                guard !Task.isCancelled else { return }
                vm.contentSearchResults.append(SearchResultItem(
                    id: note.id,
                    title: note.title,
                    snippet: contextualSnippet(from: note.body, matching: query),
                    kind: .note
                ))
            }

            env.documentService.fetchAllDocuments()
            let allDocs = env.documentService.documents

            for doc in allDocs {
                guard !Task.isCancelled else { return }
                guard let url = doc.fileURL else { continue }

                let match: SearchResultItem? = await Task.detached(priority: .utility) {
                    guard let pdfDoc = PDFDocument(url: url) else { return nil }
                    let selections = pdfDoc.findString(query, withOptions: [.caseInsensitive])
                    guard let firstMatch = selections.first else { return nil }

                    let pageIdx = firstMatch.pages.first.flatMap { pdfDoc.index(for: $0) }
                    var snippetText = firstMatch.string ?? ""

                    if let page = firstMatch.pages.first, let pageText = page.string {
                        if let matchRange = pageText.range(of: query, options: .caseInsensitive) {
                            let start = pageText.index(
                                matchRange.lowerBound,
                                offsetBy: -80,
                                limitedBy: pageText.startIndex
                            ) ?? pageText.startIndex
                            let end = pageText.index(
                                matchRange.upperBound,
                                offsetBy: 80,
                                limitedBy: pageText.endIndex
                            ) ?? pageText.endIndex
                            snippetText = String(pageText[start..<end])
                                .replacingOccurrences(of: "\n", with: " ")
                                .trimmingCharacters(in: .whitespaces)
                            if start != pageText.startIndex { snippetText = "…" + snippetText }
                            if end != pageText.endIndex { snippetText += "…" }
                        }
                    }

                    let pageLabel = pageIdx.map { "Page \($0 + 1): " } ?? ""
                    return SearchResultItem(
                        id: doc.id,
                        title: doc.title,
                        snippet: "\(pageLabel)\(snippetText)",
                        kind: .document,
                        fileURL: doc.fileURL,
                        pageIndex: pageIdx
                    )
                }.value

                guard !Task.isCancelled else { return }
                if let match = match {
                    vm.contentSearchResults.append(match)
                }
            }
        }

        sidebarViewModel.onCreateTag = { [weak environment, weak sidebarViewModel] name, color in
            guard let env = environment else { return nil }
            do {
                let tagID = try await env.collectionService.createTag(name: name, color: color)
                await MainActor.run {
                    sidebarViewModel?.tags = env.collectionService.tags.map { dto in
                        TagItem(id: dto.id, name: dto.name, color: dto.color, itemCount: dto.itemCount)
                    }
                }
                return tagID
            } catch {
                return nil
            }
        }

        sidebarViewModel.onCreateCollection = { [weak environment, weak sidebarViewModel] name, icon in
            guard let env = environment else { return nil }
            do {
                let collectionID = try await env.collectionService.createCollection(name: name, icon: icon)
                await MainActor.run {
                    sidebarViewModel?.collections = env.collectionService.collections.map { dto in
                        CollectionItem(id: dto.id, name: dto.name, icon: dto.icon, documentCount: dto.documentCount)
                    }
                }
                return collectionID
            } catch {
                return nil
            }
        }

        contentViewModel.onRefresh = { [weak sidebarViewModel, weak contentViewModel] selection in
            guard let selection = selection else { return }

            let thumbURL: (UUID) -> URL? = { docID in
                guard let libraryURL = environment.libraryURL else { return nil }
                let url = libraryURL.appendingPathComponent("Index/Thumbnails/\(docID.uuidString).png")
                return FileManager.default.fileExists(atPath: url.path) ? url : nil
            }

            switch selection {
            case .allDocuments:
                environment.documentService.fetchAllDocuments()
                contentViewModel?.documents = environment.documentService.documents.map { dto in
                    DocumentItem(
                        id: dto.id, title: dto.title, subtitle: dto.subtitle,
                        authors: dto.authors, pageCount: dto.pageCount,
                        createdAt: dto.createdAt, updatedAt: dto.updatedAt,
                        fileURL: dto.fileURL, thumbnailURL: thumbURL(dto.id),
                        documentType: dto.documentType,
                        tags: dto.tags.map { DocumentTagItem(id: $0.id, name: $0.name, color: $0.color) },
                        collectionID: dto.collectionID
                    )
                }
                if let vm = contentViewModel {
                    vm.contentMode = vm.documents.isEmpty ? .empty : .documentList
                }
                sidebarViewModel?.documentCount = environment.documentService.documents.count
                sidebarViewModel?.unsortedDocumentCount = environment.documentService.documents.filter { $0.collectionID == nil }.count
            case .unsortedDocuments:
                environment.documentService.fetchAllDocuments()
                let unsortedDocs = environment.documentService.documents.filter { $0.collectionID == nil }
                contentViewModel?.documents = unsortedDocs.map { dto in
                    DocumentItem(
                        id: dto.id, title: dto.title, subtitle: dto.subtitle,
                        authors: dto.authors, pageCount: dto.pageCount,
                        createdAt: dto.createdAt, updatedAt: dto.updatedAt,
                        fileURL: dto.fileURL, thumbnailURL: thumbURL(dto.id),
                        documentType: dto.documentType,
                        tags: dto.tags.map { DocumentTagItem(id: $0.id, name: $0.name, color: $0.color) },
                        collectionID: dto.collectionID
                    )
                }
                if let vm = contentViewModel {
                    vm.contentMode = vm.documents.isEmpty ? .empty : .documentList
                }
            case .allNotes:
                environment.documentService.fetchAllNotes()
                contentViewModel?.notes = environment.documentService.notes.map { dto in
                    NoteItem(id: dto.id, title: dto.title, preview: dto.preview, pinned: dto.pinned, createdAt: dto.createdAt, updatedAt: dto.updatedAt)
                }
                if let vm = contentViewModel {
                    vm.contentMode = vm.notes.isEmpty ? .empty : .noteList
                }
                sidebarViewModel?.noteCount = environment.documentService.notes.count
            case .collection(let id):
                environment.documentService.fetchDocuments(for: id)
                contentViewModel?.documents = environment.documentService.documents.map { dto in
                    DocumentItem(
                        id: dto.id, title: dto.title, subtitle: dto.subtitle,
                        authors: dto.authors, pageCount: dto.pageCount,
                        createdAt: dto.createdAt, updatedAt: dto.updatedAt,
                        fileURL: dto.fileURL, thumbnailURL: thumbURL(dto.id),
                        documentType: dto.documentType,
                        tags: dto.tags.map { DocumentTagItem(id: $0.id, name: $0.name, color: $0.color) },
                        collectionID: dto.collectionID
                    )
                }
                if let vm = contentViewModel {
                    vm.contentMode = vm.documents.isEmpty ? .empty : .documentList
                }
            case .tag(let id):
                environment.documentService.fetchDocuments(forTag: id)
                contentViewModel?.documents = environment.documentService.documents.map { dto in
                    DocumentItem(
                        id: dto.id, title: dto.title, subtitle: dto.subtitle,
                        authors: dto.authors, pageCount: dto.pageCount,
                        createdAt: dto.createdAt, updatedAt: dto.updatedAt,
                        fileURL: dto.fileURL, thumbnailURL: thumbURL(dto.id),
                        documentType: dto.documentType,
                        tags: dto.tags.map { DocumentTagItem(id: $0.id, name: $0.name, color: $0.color) },
                        collectionID: dto.collectionID
                    )
                }
                if let vm = contentViewModel {
                    vm.contentMode = vm.documents.isEmpty ? .empty : .documentList
                }
            }
        }

        // Initial load
        environment.documentService.fetchAllDocuments()
        environment.documentService.fetchAllNotes()
        environment.collectionService.fetchAllTags()
        environment.collectionService.fetchAllCollections()
        updateViewModelsFromService()
    }

    private func updateViewModelsFromService() {
        sidebarViewModel.documentCount = environment.documentService.documents.count
        sidebarViewModel.unsortedDocumentCount = environment.documentService.documents.filter { $0.collectionID == nil }.count
        sidebarViewModel.noteCount = environment.documentService.notes.count

        sidebarViewModel.tags = environment.collectionService.tags.map { dto in
            TagItem(id: dto.id, name: dto.name, color: dto.color, itemCount: dto.itemCount)
        }

        sidebarViewModel.collections = environment.collectionService.collections.map { dto in
            CollectionItem(id: dto.id, name: dto.name, icon: dto.icon, documentCount: dto.documentCount)
        }

        availableTags = environment.collectionService.tags.map { dto in
            DocumentTagItem(id: dto.id, name: dto.name, color: dto.color)
        }

        availableCollections = environment.collectionService.collections.map { dto in
            CollectionMenuItem(id: dto.id, name: dto.name)
        }

        contentViewModel.documents = environment.documentService.documents.map { dto in
            DocumentItem(
                id: dto.id, title: dto.title, subtitle: dto.subtitle,
                authors: dto.authors, pageCount: dto.pageCount,
                createdAt: dto.createdAt, updatedAt: dto.updatedAt,
                fileURL: dto.fileURL, thumbnailURL: thumbnailURL(for: dto.id),
                documentType: dto.documentType,
                tags: dto.tags.map { DocumentTagItem(id: $0.id, name: $0.name, color: $0.color) },
                collectionID: dto.collectionID
            )
        }

        contentViewModel.notes = environment.documentService.notes.map { dto in
            NoteItem(id: dto.id, title: dto.title, preview: dto.preview, pinned: dto.pinned, createdAt: dto.createdAt, updatedAt: dto.updatedAt)
        }

        if let selection = sidebarViewModel.selectedItem {
            switch selection {
            case .allDocuments, .unsortedDocuments:
                contentViewModel.contentMode = contentViewModel.documents.isEmpty ? .empty : .documentList
            case .allNotes:
                contentViewModel.contentMode = contentViewModel.notes.isEmpty ? .empty : .noteList
            case .collection, .tag:
                contentViewModel.contentMode = contentViewModel.documents.isEmpty ? .empty : .documentList
            }
        }

        updateStorageInfo()
    }

    private func updateStorageInfo() {
        guard let libraryURL = environment.libraryURL else { return }
        Task.detached(priority: .utility) {
            let totalBytes = await environment.documentService.calculateTotalStorage(libraryURL: libraryURL)
            await MainActor.run {
                contentViewModel.totalStorageBytes = totalBytes
            }
        }
    }

    private func refreshDocumentList() {
        environment.documentService.fetchAllDocuments()
        environment.documentService.fetchAllNotes()
        environment.collectionService.fetchAllTags()
        environment.collectionService.fetchAllCollections()

        contentViewModel.documents = environment.documentService.documents.map { dto in
            DocumentItem(
                id: dto.id, title: dto.title, subtitle: dto.subtitle,
                authors: dto.authors, pageCount: dto.pageCount,
                createdAt: dto.createdAt, updatedAt: dto.updatedAt,
                fileURL: dto.fileURL, thumbnailURL: thumbnailURL(for: dto.id),
                documentType: dto.documentType,
                tags: dto.tags.map { DocumentTagItem(id: $0.id, name: $0.name, color: $0.color) },
                collectionID: dto.collectionID
            )
        }

        contentViewModel.notes = environment.documentService.notes.map { dto in
            NoteItem(id: dto.id, title: dto.title, preview: dto.preview, pinned: dto.pinned, createdAt: dto.createdAt, updatedAt: dto.updatedAt)
        }

        sidebarViewModel.documentCount = environment.documentService.documents.count
        sidebarViewModel.unsortedDocumentCount = environment.documentService.documents.filter { $0.collectionID == nil }.count
        sidebarViewModel.noteCount = environment.documentService.notes.count

        sidebarViewModel.tags = environment.collectionService.tags.map { dto in
            TagItem(id: dto.id, name: dto.name, color: dto.color, itemCount: dto.itemCount)
        }
        sidebarViewModel.collections = environment.collectionService.collections.map { dto in
            CollectionItem(id: dto.id, name: dto.name, icon: dto.icon, documentCount: dto.documentCount)
        }
        availableTags = environment.collectionService.tags.map { dto in
            DocumentTagItem(id: dto.id, name: dto.name, color: dto.color)
        }
        availableCollections = environment.collectionService.collections.map { dto in
            CollectionMenuItem(id: dto.id, name: dto.name)
        }

        if let selection = sidebarViewModel.selectedItem {
            switch selection {
            case .allDocuments, .unsortedDocuments:
                contentViewModel.contentMode = contentViewModel.documents.isEmpty ? .empty : .documentList
            case .allNotes:
                contentViewModel.contentMode = contentViewModel.notes.isEmpty ? .empty : .noteList
            default:
                contentViewModel.contentMode = contentViewModel.documents.isEmpty ? .empty : .documentList
            }
        }

        updateStorageInfo()
    }

    // MARK: - Handlers (same logic as macOS)

    private func handleToggleTag(documentID: UUID, tagID: UUID) {
        Task {
            if let doc = contentViewModel.documents.first(where: { $0.id == documentID }),
               doc.tags.contains(where: { $0.id == tagID }) {
                try? await environment.collectionService.removeTag(tagID, from: documentID)
            } else {
                try? await environment.collectionService.addTag(tagID, to: documentID)
            }
            await MainActor.run { refreshDocumentList() }
        }
    }

    private func handleRenameTag(tagID: UUID, newName: String) {
        if let index = sidebarViewModel.tags.firstIndex(where: { $0.id == tagID }) {
            sidebarViewModel.tags[index].name = newName
        }
        Task {
            try? await environment.collectionService.updateTag(tagID, name: newName)
            await MainActor.run {
                sidebarViewModel.tags = environment.collectionService.tags.map { dto in
                    TagItem(id: dto.id, name: dto.name, color: dto.color, itemCount: dto.itemCount)
                }
                availableTags = environment.collectionService.tags.map { dto in
                    DocumentTagItem(id: dto.id, name: dto.name, color: dto.color)
                }
            }
        }
    }

    private func handleRenameCollection(collectionID: UUID, newName: String) {
        if let index = sidebarViewModel.collections.firstIndex(where: { $0.id == collectionID }) {
            sidebarViewModel.collections[index].name = newName
        }
        Task {
            try? await environment.collectionService.updateCollection(collectionID, name: newName)
            await MainActor.run {
                sidebarViewModel.collections = environment.collectionService.collections.map { dto in
                    CollectionItem(id: dto.id, name: dto.name, icon: dto.icon, documentCount: dto.documentCount)
                }
                availableCollections = environment.collectionService.collections.map { dto in
                    CollectionMenuItem(id: dto.id, name: dto.name)
                }
            }
        }
    }

    private func handleDeleteTag(tagID: UUID) {
        Task {
            try? await environment.collectionService.deleteTag(tagID)
            environment.collectionService.fetchAllTags()
            await MainActor.run {
                if case .tag(let selectedID) = sidebarViewModel.selectedItem, selectedID == tagID {
                    sidebarViewModel.selectedItem = .allDocuments
                }
                sidebarViewModel.tags = environment.collectionService.tags.map { dto in
                    TagItem(id: dto.id, name: dto.name, color: dto.color, itemCount: dto.itemCount)
                }
                availableTags = environment.collectionService.tags.map { dto in
                    DocumentTagItem(id: dto.id, name: dto.name, color: dto.color)
                }
                refreshDocumentList()
            }
        }
    }

    private func handleDeleteCollection(collectionID: UUID) {
        Task {
            try? await environment.collectionService.deleteCollection(collectionID)
            environment.collectionService.fetchAllCollections()
            await MainActor.run {
                if case .collection(let selectedID) = sidebarViewModel.selectedItem, selectedID == collectionID {
                    sidebarViewModel.selectedItem = .allDocuments
                }
                sidebarViewModel.collections = environment.collectionService.collections.map { dto in
                    CollectionItem(id: dto.id, name: dto.name, icon: dto.icon, documentCount: dto.documentCount)
                }
                availableCollections = environment.collectionService.collections.map { dto in
                    CollectionMenuItem(id: dto.id, name: dto.name)
                }
                refreshDocumentList()
            }
        }
    }

    private func handleRenameDocument(documentID: UUID, newName: String) {
        Task {
            try? await environment.documentService.renameDocument(
                documentID,
                title: newName,
                libraryURL: environment.libraryURL,
                libraryStore: environment.libraryRootStore
            )
            await MainActor.run { refreshDocumentList() }
        }
    }

    private func handleDeleteDocument(documentID: UUID) {
        Task {
            try? await environment.documentService.deleteDocument(documentID)
            await MainActor.run { refreshDocumentList() }
        }
    }

    private func handleSetDocumentCollection(documentID: UUID, collectionID: UUID?) {
        Task {
            try? await environment.collectionService.setDocumentCollection(documentID, collectionID: collectionID)
            await MainActor.run { refreshDocumentList() }
        }
    }

    private func handleUpdateDocumentMetadata(documentID: UUID, title: String, subtitle: String?, authors: [String]?) {
        Task {
            try? await environment.documentService.updateDocumentMetadata(
                documentID,
                title: title,
                subtitle: subtitle,
                authors: authors,
                libraryURL: environment.libraryURL,
                libraryStore: environment.libraryRootStore
            )
            await MainActor.run { refreshDocumentList() }
        }
    }
}

// MARK: - Search Helpers

private func contextualSnippet(from text: String, matching query: String, maxLength: Int = 150) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }

    guard let range = trimmed.range(of: query, options: .caseInsensitive) else {
        if trimmed.count > maxLength {
            return String(trimmed.prefix(maxLength)) + "…"
        }
        return trimmed
    }

    let beforeLength = maxLength / 3
    let afterLength = maxLength - beforeLength

    let start = trimmed.index(range.lowerBound, offsetBy: -beforeLength, limitedBy: trimmed.startIndex) ?? trimmed.startIndex
    let end = trimmed.index(range.upperBound, offsetBy: afterLength, limitedBy: trimmed.endIndex) ?? trimmed.endIndex

    var snippet = String(trimmed[start..<end])
        .replacingOccurrences(of: "\n", with: " ")
        .trimmingCharacters(in: .whitespaces)

    if start != trimmed.startIndex { snippet = "…" + snippet }
    if end != trimmed.endIndex { snippet += "…" }

    return snippet
}

// MARK: - Import Progress View

private struct ImportProgressView_iPad: View {
    let progress: ImportCoordinator_iPad.ImportProgress

    var body: some View {
        VStack(spacing: 16) {
            ProgressView(value: Double(progress.current), total: Double(progress.total))
                .progressViewStyle(.linear)
                .frame(width: 300)

            Text("Importing \(progress.current) of \(progress.total)")
                .font(.headline)

            Text(progress.currentFile)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(24)
        .background(Color.platformWindowBackground)
        .cornerRadius(12)
        .shadow(radius: 20)
    }
}

// MARK: - Library Setup

private struct LibrarySetupView_iPad: View {
    @EnvironmentObject private var environment: AppEnvironment_iPad

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("Welcome to Wndr")
                .font(.largeTitle)
                .bold()

            Text("Wndr stores your research library locally on this iPad.\nTap below to get started.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 40)

            Button {
                environment.createDefaultLibrary()
            } label: {
                Label("Create Library", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(60)
    }
}
