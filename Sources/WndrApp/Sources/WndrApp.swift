import PDFKit
import SwiftUI
import WndrKit
import WndrData
import WndrPDF

@main
struct WndrApp: App {
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Wndr") {
                    showAboutPanel()
                }
            }
            CommandMenu("Library") {
                Button("Change Library Location") {
                    environment.libraryRootCoordinator.presentLibraryChooser()
                }
                .keyboardShortcut(",", modifiers: [.command, .shift])

                Divider()

                Button("Regenerate All Thumbnails") {
                    environment.shouldRegenerateThumbnails = true
                }

                Button("Reassign Tag Colors") {
                    environment.shouldReassignTagColors = true
                }
                .keyboardShortcut("T", modifiers: [.command, .shift])
            }
        }
    }
}

private struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var sidebarViewModel = LibrarySidebarViewModel()
    @StateObject private var contentViewModel = ContentAreaViewModel()
    @State private var availableTags: [DocumentTagItem] = []
    @State private var availableCollections: [CollectionMenuItem] = []

    var body: some View {
        Group {
            if environment.libraryURL == nil {
                LibrarySetupView()
            } else {
                ContentWrapper(
                    environment: environment,
                    sidebarViewModel: sidebarViewModel,
                    contentViewModel: contentViewModel,
                    importCoordinator: environment.importCoordinator,
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
            }
        }
        .frame(minWidth: 960, minHeight: 640)
        .task {
            await environment.bootstrap()
        }
        .alert(item: $environment.libraryRootCoordinator.activeAlert) { alert in
            alert.toSwiftUIAlert()
        }
        .alert(item: $environment.importCoordinator.activeAlert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
        .overlay {
            if environment.importCoordinator.isImporting,
               let progress = environment.importCoordinator.importProgress {
                ImportProgressView(progress: progress)
            }
        }
        .onChange(of: environment.shouldRegenerateThumbnails) { shouldRegenerate in
            if shouldRegenerate {
                regenerateAllThumbnails()
                environment.shouldRegenerateThumbnails = false
            }
        }
        .onChange(of: environment.shouldReassignTagColors) { shouldReassign in
            if shouldReassign {
                reassignTagColors()
                environment.shouldReassignTagColors = false
            }
        }
        .onChange(of: environment.importCoordinator.isImporting) { _, newValue in
            // Refresh document list when import completes
            if !newValue {
                refreshDocumentList()
            }
        }
    }

    private func thumbnailURL(for documentID: UUID) -> URL? {
        guard let libraryURL = environment.libraryURL else { return nil }
        let indexURL = libraryURL.appendingPathComponent("Index", isDirectory: true)
        let thumbURL = indexURL.appendingPathComponent("Thumbnails", isDirectory: true)
            .appendingPathComponent("\(documentID.uuidString).png")
        return FileManager.default.fileExists(atPath: thumbURL.path) ? thumbURL : nil
    }

    private func setupViewModels() {
        // Connect import handler
        contentViewModel.onImport = {
            environment.importCoordinator.presentImportPanel()
        }

        // Connect note creation handler
        contentViewModel.onCreateNote = { [weak environment, weak contentViewModel] title in
            guard let env = environment else { return nil }
            do {
                let noteID = try await env.documentService.createNote(title: title)
                // Sync the notes list so the detail view can find the new note immediately
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

        // Connect content search handler
        contentViewModel.onContentSearch = { [weak environment, weak contentViewModel] query in
            guard let env = environment, let vm = contentViewModel else { return }

            // 1. Search notes via Core Data (fast, runs on main actor)
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

            // 2. Search PDFs via PDFKit (slow, each PDF searched on background thread)
            env.documentService.fetchAllDocuments()
            let allDocs = env.documentService.documents

            for doc in allDocs {
                guard !Task.isCancelled else { return }
                guard let url = doc.fileURL else { continue }

                // Search this PDF on a background thread to avoid blocking UI
                let match: SearchResultItem? = await Task.detached(priority: .utility) {
                    guard let pdfDoc = PDFDocument(url: url) else { return nil }
                    let selections = pdfDoc.findString(query, withOptions: [.caseInsensitive])
                    guard let firstMatch = selections.first else { return nil }

                    // Build a contextual snippet from the page text around the match
                    let pageIdx = firstMatch.pages.first.flatMap { pdfDoc.index(for: $0) }
                    var snippetText = firstMatch.string ?? ""

                    // Try to get surrounding context from the page
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

        // Connect tag creation handler
        sidebarViewModel.onCreateTag = { [weak environment, weak sidebarViewModel] name, color in
            guard let env = environment else { return nil }
            do {
                let tagID = try await env.collectionService.createTag(name: name, color: color)
                // createTag already calls fetchAllTags() internally
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

        // Connect collection creation handler
        sidebarViewModel.onCreateCollection = { [weak environment, weak sidebarViewModel] name, icon in
            guard let env = environment else { return nil }
            do {
                let collectionID = try await env.collectionService.createCollection(name: name, icon: icon)
                // createCollection already calls fetchAllCollections() internally
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

        // Connect refresh handler
        contentViewModel.onRefresh = { [weak sidebarViewModel, weak contentViewModel] selection in
            guard let selection = selection else { return }

            // Helper to compute thumbnail URL
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
                        id: dto.id,
                        title: dto.title,
                        subtitle: dto.subtitle,
                        authors: dto.authors,
                        pageCount: dto.pageCount,
                        createdAt: dto.createdAt,
                        updatedAt: dto.updatedAt,
                        fileURL: dto.fileURL,
                        thumbnailURL: thumbURL(dto.id),
                        documentType: dto.documentType,
                        tags: dto.tags.map { DocumentTagItem(id: $0.id, name: $0.name, color: $0.color) },
                        collectionID: dto.collectionID
                    )
                }
                // Update content mode based on document count
                if let vm = contentViewModel {
                    vm.contentMode = vm.documents.isEmpty ? .empty : .documentList
                }
                // Update total counts only when viewing all documents
                sidebarViewModel?.documentCount = environment.documentService.documents.count
                sidebarViewModel?.unsortedDocumentCount = environment.documentService.documents.filter { $0.collectionID == nil }.count
            case .unsortedDocuments:
                environment.documentService.fetchAllDocuments()
                // Filter to show only documents without collections
                let unsortedDocs = environment.documentService.documents.filter { $0.collectionID == nil }
                contentViewModel?.documents = unsortedDocs.map { dto in
                    DocumentItem(
                        id: dto.id,
                        title: dto.title,
                        subtitle: dto.subtitle,
                        authors: dto.authors,
                        pageCount: dto.pageCount,
                        createdAt: dto.createdAt,
                        updatedAt: dto.updatedAt,
                        fileURL: dto.fileURL,
                        thumbnailURL: thumbURL(dto.id),
                        documentType: dto.documentType,
                        tags: dto.tags.map { DocumentTagItem(id: $0.id, name: $0.name, color: $0.color) },
                        collectionID: dto.collectionID
                    )
                }
                // Update content mode based on document count
                if let vm = contentViewModel {
                    vm.contentMode = vm.documents.isEmpty ? .empty : .documentList
                }
            case .allNotes:
                environment.documentService.fetchAllNotes()
                contentViewModel?.notes = environment.documentService.notes.map { dto in
                    NoteItem(
                        id: dto.id,
                        title: dto.title,
                        preview: dto.preview,
                        pinned: dto.pinned,
                        createdAt: dto.createdAt,
                        updatedAt: dto.updatedAt
                    )
                }
                // Update content mode based on note count
                if let vm = contentViewModel {
                    vm.contentMode = vm.notes.isEmpty ? .empty : .noteList
                }
                // Update total counts only when viewing all notes
                sidebarViewModel?.noteCount = environment.documentService.notes.count
            case .collection(let id):
                environment.documentService.fetchDocuments(for: id)
                contentViewModel?.documents = environment.documentService.documents.map { dto in
                    DocumentItem(
                        id: dto.id,
                        title: dto.title,
                        subtitle: dto.subtitle,
                        authors: dto.authors,
                        pageCount: dto.pageCount,
                        createdAt: dto.createdAt,
                        updatedAt: dto.updatedAt,
                        fileURL: dto.fileURL,
                        thumbnailURL: thumbURL(dto.id),
                        documentType: dto.documentType,
                        tags: dto.tags.map { DocumentTagItem(id: $0.id, name: $0.name, color: $0.color) },
                        collectionID: dto.collectionID
                    )
                }
                // Update content mode
                if let vm = contentViewModel {
                    vm.contentMode = vm.documents.isEmpty ? .empty : .documentList
                }
            case .tag(let id):
                environment.documentService.fetchDocuments(forTag: id)
                contentViewModel?.documents = environment.documentService.documents.map { dto in
                    DocumentItem(
                        id: dto.id,
                        title: dto.title,
                        subtitle: dto.subtitle,
                        authors: dto.authors,
                        pageCount: dto.pageCount,
                        createdAt: dto.createdAt,
                        updatedAt: dto.updatedAt,
                        fileURL: dto.fileURL,
                        thumbnailURL: thumbURL(dto.id),
                        documentType: dto.documentType,
                        tags: dto.tags.map { DocumentTagItem(id: $0.id, name: $0.name, color: $0.color) },
                        collectionID: dto.collectionID
                    )
                }
                // Update content mode
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
        // Update counts in sidebar
        sidebarViewModel.documentCount = environment.documentService.documents.count
        sidebarViewModel.unsortedDocumentCount = environment.documentService.documents.filter { $0.collectionID == nil }.count
        sidebarViewModel.noteCount = environment.documentService.notes.count

        // Update sidebar tags
        sidebarViewModel.tags = environment.collectionService.tags.map { dto in
            TagItem(id: dto.id, name: dto.name, color: dto.color, itemCount: dto.itemCount)
        }

        // Update sidebar collections
        sidebarViewModel.collections = environment.collectionService.collections.map { dto in
            CollectionItem(id: dto.id, name: dto.name, icon: dto.icon, documentCount: dto.documentCount)
        }

        // Update available tags for context menus
        availableTags = environment.collectionService.tags.map { dto in
            DocumentTagItem(id: dto.id, name: dto.name, color: dto.color)
        }

        // Update available collections for context menus
        availableCollections = environment.collectionService.collections.map { dto in
            CollectionMenuItem(id: dto.id, name: dto.name)
        }

        // Populate documents directly
        contentViewModel.documents = environment.documentService.documents.map { dto in
            DocumentItem(
                id: dto.id,
                title: dto.title,
                subtitle: dto.subtitle,
                authors: dto.authors,
                pageCount: dto.pageCount,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt,
                fileURL: dto.fileURL,
                thumbnailURL: thumbnailURL(for: dto.id),
                documentType: dto.documentType,
                tags: dto.tags.map { DocumentTagItem(id: $0.id, name: $0.name, color: $0.color) },
                collectionID: dto.collectionID
            )
        }

        contentViewModel.notes = environment.documentService.notes.map { dto in
            NoteItem(
                id: dto.id,
                title: dto.title,
                preview: dto.preview,
                pinned: dto.pinned,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt
            )
        }

        // Update content mode based on selection
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

        // Calculate total storage
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
                id: dto.id,
                title: dto.title,
                subtitle: dto.subtitle,
                authors: dto.authors,
                pageCount: dto.pageCount,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt,
                fileURL: dto.fileURL,
                thumbnailURL: thumbnailURL(for: dto.id),
                documentType: dto.documentType,
                tags: dto.tags.map { DocumentTagItem(id: $0.id, name: $0.name, color: $0.color) },
                collectionID: dto.collectionID
            )
        }

        contentViewModel.notes = environment.documentService.notes.map { dto in
            NoteItem(
                id: dto.id,
                title: dto.title,
                preview: dto.preview,
                pinned: dto.pinned,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt
            )
        }

        // Update total counts from service (not filtered view)
        sidebarViewModel.documentCount = environment.documentService.documents.count
        sidebarViewModel.unsortedDocumentCount = environment.documentService.documents.filter { $0.collectionID == nil }.count
        sidebarViewModel.noteCount = environment.documentService.notes.count

        // Update sidebar tags
        sidebarViewModel.tags = environment.collectionService.tags.map { dto in
            TagItem(id: dto.id, name: dto.name, color: dto.color, itemCount: dto.itemCount)
        }

        // Update sidebar collections
        sidebarViewModel.collections = environment.collectionService.collections.map { dto in
            CollectionItem(id: dto.id, name: dto.name, icon: dto.icon, documentCount: dto.documentCount)
        }

        // Update available tags
        availableTags = environment.collectionService.tags.map { dto in
            DocumentTagItem(id: dto.id, name: dto.name, color: dto.color)
        }

        // Update available collections
        availableCollections = environment.collectionService.collections.map { dto in
            CollectionMenuItem(id: dto.id, name: dto.name)
        }

        // Update content mode
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

        // Recalculate storage
        updateStorageInfo()
    }

    private func handleToggleTag(documentID: UUID, tagID: UUID) {
        Task {
            // Check if document already has this tag
            if let doc = contentViewModel.documents.first(where: { $0.id == documentID }),
               doc.tags.contains(where: { $0.id == tagID }) {
                // Remove tag
                try? await environment.collectionService.removeTag(tagID, from: documentID)
            } else {
                // Add tag
                try? await environment.collectionService.addTag(tagID, to: documentID)
            }
            // Refresh to update UI
            await MainActor.run {
                refreshDocumentList()
            }
        }
    }

    private func handleRenameTag(tagID: UUID, newName: String) {
        // Optimistic update for instant UI feedback
        if let index = sidebarViewModel.tags.firstIndex(where: { $0.id == tagID }) {
            sidebarViewModel.tags[index].name = newName
        }
        if let index = availableTags.firstIndex(where: { $0.id == tagID }) {
            availableTags[index].name = newName
        }

        Task {
            try? await environment.collectionService.updateTag(tagID, name: newName)
            // updateTag already calls fetchAllTags() internally
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
        // Optimistic update for instant UI feedback
        if let index = sidebarViewModel.collections.firstIndex(where: { $0.id == collectionID }) {
            sidebarViewModel.collections[index].name = newName
        }
        if let index = availableCollections.firstIndex(where: { $0.id == collectionID }) {
            availableCollections[index].name = newName
        }

        Task {
            try? await environment.collectionService.updateCollection(collectionID, name: newName)
            // updateCollection already calls fetchAllCollections() internally
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
                // If the deleted tag was selected, switch to All Documents
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
                // If the deleted collection was selected, switch to All Documents
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
            await MainActor.run {
                refreshDocumentList()
            }
        }
    }

    private func handleDeleteDocument(documentID: UUID) {
        Task {
            try? await environment.documentService.deleteDocument(documentID)
            await MainActor.run {
                refreshDocumentList()
            }
        }
    }

    private func handleSetDocumentCollection(documentID: UUID, collectionID: UUID?) {
        Task {
            try? await environment.collectionService.setDocumentCollection(documentID, collectionID: collectionID)
            await MainActor.run {
                refreshDocumentList()
            }
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
            await MainActor.run {
                refreshDocumentList()
            }
        }
    }

    // MARK: - Tag Management

    func reassignTagColors() {
        Task {
            let logger = WndrLogger(category: "tags")
            logger.info("Manually reassigning tag colors")

            // Fetch all existing tags
            environment.collectionService.fetchAllTags()
            let existingTags = environment.collectionService.tags

            guard !existingTags.isEmpty else {
                logger.info("No tags to reassign colors to")
                return
            }

            // Sort tags by name to ensure consistent ordering
            let sortedTags = existingTags.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            // Assign colors from the palette
            for (index, tag) in sortedTags.enumerated() {
                let colorIndex = index % CollectionService.tagColorPalette.count
                let newColor = CollectionService.tagColorPalette[colorIndex]

                do {
                    try await environment.collectionService.updateTag(tag.id, color: newColor)
                    logger.info("Assigned color \(newColor) to tag: \(tag.name)")
                } catch {
                    logger.error("Failed to assign color to tag \(tag.name): \(error.localizedDescription)")
                }
            }

            // Refresh the sidebar to show new colors
            await MainActor.run {
                refreshDocumentList()
            }

            logger.info("Manual tag color reassignment completed")
        }
    }

    // MARK: - Thumbnail Management

    func regenerateAllThumbnails() {
        Task {
            guard let libraryURL = environment.libraryURL else {
                print("No library URL available")
                return
            }

            // Show progress indicator
            await MainActor.run {
                environment.importCoordinator.statusMessage = "Regenerating thumbnails..."
            }

            // Get all documents
            environment.documentService.fetchAllDocuments()
            let documents = environment.documentService.documents.compactMap { dto -> (id: UUID, pdfURL: URL)? in
                guard let fileURL = dto.fileURL else { return nil }
                return (dto.id, fileURL)
            }

            print("Starting thumbnail regeneration for \(documents.count) documents")

            // Regenerate thumbnails
            let result = await environment.thumbnailService.regenerateAllThumbnails(
                documents: documents,
                libraryURL: libraryURL
            )

            // Update status
            await MainActor.run {
                environment.importCoordinator.statusMessage = "Regenerated \(result.succeeded) thumbnails (\(result.failed) failed)"

                // Clear status after 3 seconds
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await MainActor.run {
                        environment.importCoordinator.statusMessage = nil
                    }
                }

                // Refresh the document list to show new thumbnails
                refreshDocumentList()
            }

            print("Thumbnail regeneration complete: \(result.succeeded) succeeded, \(result.failed) failed")
        }
    }
}

// MARK: - Search Helpers

/// Extracts a snippet from text centered around the first occurrence of the query.
private func contextualSnippet(from text: String, matching query: String, maxLength: Int = 150) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }

    guard let range = trimmed.range(of: query, options: .caseInsensitive) else {
        // No match in body (title-only match); return start of text
        if trimmed.count > maxLength {
            return String(trimmed.prefix(maxLength)) + "…"
        }
        return trimmed
    }

    // Center the match in the snippet window
    let beforeLength = maxLength / 3
    let afterLength = maxLength - beforeLength

    let start = trimmed.index(
        range.lowerBound,
        offsetBy: -beforeLength,
        limitedBy: trimmed.startIndex
    ) ?? trimmed.startIndex

    let end = trimmed.index(
        range.upperBound,
        offsetBy: afterLength,
        limitedBy: trimmed.endIndex
    ) ?? trimmed.endIndex

    var snippet = String(trimmed[start..<end])
        .replacingOccurrences(of: "\n", with: " ")
        .trimmingCharacters(in: .whitespaces)

    if start != trimmed.startIndex { snippet = "…" + snippet }
    if end != trimmed.endIndex { snippet += "…" }

    return snippet
}

// MARK: - About Panel

/// Content for the About panel
private struct AboutContentView: View {
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("Wndr")
                .font(.system(size: 20, weight: .semibold))

            Text("Version \(appVersion) (\(buildNumber))")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Text("A research workspace for PDFs and notes")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.top, 4)

            Divider()
                .frame(width: 180)
                .padding(.vertical, 8)

            VStack(spacing: 4) {
                Button(action: openReleaseNotes) {
                    Text("Release Notes")
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }

                Text("Created by @adamkz")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.6))
            }
        }
    }

    private func openReleaseNotes() {
        if let url = URL(string: "https://github.com/adamkz/wndr/releases") {
            NSWorkspace.shared.open(url)
        }
    }
}


// MARK: - About Panel

private func showAboutPanel() {
    let aboutView = AboutContentView()
        .padding(.horizontal, 40)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .frame(width: 280)

    let hostingView = NSHostingView(rootView: aboutView)
    hostingView.setFrameSize(hostingView.fittingSize)

    let panel = NSPanel(
        contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
        styleMask: [.titled, .closable, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    panel.titlebarAppearsTransparent = true
    panel.titleVisibility = NSWindow.TitleVisibility.hidden
    panel.isMovableByWindowBackground = true
    panel.contentView = hostingView
    panel.center()
    panel.isReleasedWhenClosed = false
    panel.makeKeyAndOrderFront(NSApplication.shared.mainWindow)
}

// MARK: - Visual Effect (NSVisualEffectView wrapper)

private struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Import Progress

private struct ImportProgressView: View {
    let progress: ImportCoordinator.ImportProgress

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
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 20)
    }
}

private struct LibrarySetupView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome to Wndr")
                .font(.largeTitle)
                .bold()
            Text("Choose a library location to start managing your documents and notes.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            Button("Choose Library Location…") {
                environment.libraryRootCoordinator.presentLibraryChooser()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
    }
}
