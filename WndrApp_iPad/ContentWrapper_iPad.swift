// ContentWrapper_iPad.swift
// Assembles the main iPadOS UI, wiring up document/note handlers and the import picker.

import SwiftUI
import WndrKit
import WndrData
import WndrPDF
import WndrNotes

struct ContentWrapper_iPad: View {
    let environment: AppEnvironment_iPad
    @ObservedObject var sidebarViewModel: LibrarySidebarViewModel
    @ObservedObject var contentViewModel: ContentAreaViewModel
    var availableTags: [DocumentTagItem] = []
    var availableCollections: [CollectionMenuItem] = []
    var onToggleTag: ((UUID, UUID) -> Void)? = nil
    var onRenameTag: ((UUID, String) -> Void)? = nil
    var onRenameCollection: ((UUID, String) -> Void)? = nil
    var onDeleteTag: ((UUID) -> Void)? = nil
    var onDeleteCollection: ((UUID) -> Void)? = nil
    var onRenameDocument: ((UUID, String) -> Void)? = nil
    var onDeleteDocument: ((UUID) -> Void)? = nil
    var onSetDocumentCollection: ((UUID, UUID?) -> Void)? = nil
    var onDropDocumentOnCollection: ((UUID, UUID) -> Void)? = nil
    var onUpdateDocumentMetadata: ((UUID, String, String?, [String]?) -> Void)? = nil

    var body: some View {
        LookPrimaryView(
            coordinator: environment.libraryCoordinator,
            sidebarViewModel: sidebarViewModel,
            contentViewModel: contentViewModel,
            statusMessage: environment.importCoordinator.statusMessage,
            availableTags: availableTags,
            availableCollections: availableCollections,
            onToggleTag: onToggleTag,
            onRenameTag: onRenameTag,
            onRenameCollection: onRenameCollection,
            onDeleteTag: onDeleteTag,
            onDeleteCollection: onDeleteCollection,
            onRenameDocument: onRenameDocument,
            onDeleteDocument: onDeleteDocument,
            onSetDocumentCollection: onSetDocumentCollection,
            onDropDocumentOnCollection: onDropDocumentOnCollection,
            onUpdateDocumentMetadata: onUpdateDocumentMetadata
        )
        .environment(\.contentAreaDocumentHandler, documentHandler)
        .environment(\.contentAreaNoteHandler, noteHandler)
        .environment(\.contentAreaDropHandler, dropHandler)
        .sheet(isPresented: $environment.importCoordinator.showDocumentPicker) {
            DocumentPickerView { urls in
                environment.importCoordinator.libraryURL = environment.libraryURL
                Task {
                    await environment.importCoordinator.importDocuments(from: urls)
                }
            }
        }
        .onAppear {
            // Keep import coordinator's library URL in sync
            environment.importCoordinator.libraryURL = environment.libraryURL
        }
    }

    // MARK: - Drop Handler

    private func dropHandler(urls: [URL]) {
        environment.importCoordinator.libraryURL = environment.libraryURL
        Task {
            await environment.importCoordinator.importDocuments(from: urls)
            environment.documentService.fetchAllDocuments()
            await MainActor.run {
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
                if contentViewModel.contentMode == .empty {
                    contentViewModel.contentMode = .documentList
                }
            }
        }
    }

    private func thumbnailURL(for documentID: UUID) -> URL? {
        guard let libraryURL = environment.libraryURL else { return nil }
        let url = libraryURL.appendingPathComponent("Index/Thumbnails/\(documentID.uuidString).png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Document Handler

    private func documentHandler(documentID: UUID, url: URL?, title: String) -> AnyView {
        guard let url = url else {
            return AnyView(
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("File Not Found")
                        .font(.title2)
                    Text("The document file could not be located")
                        .foregroundColor(.secondary)
                }
            )
        }

        // Route to EPUB reader if file is an EPUB
        if url.pathExtension.lowercased() == "epub" {
            return makeEPUBViewer(documentID: documentID, url: url, title: title)
        }

        return makePDFViewer(documentID: documentID, url: url, title: title)
    }

    // MARK: - PDF Viewer

    private func makePDFViewer(documentID: UUID, url: URL, title: String) -> AnyView {
        let viewModel = PDFViewerViewModel(documentID: documentID, documentURL: url, title: title)

        environment.annotationService.fetchAnnotations(for: documentID)

        viewModel.onCreateAnnotation = { [weak environment] pageIndex, rects, textSnippet, color in
            guard let env = environment else { return }
            let rectsDict = rects.map { rect -> [String: Double] in
                ["x": Double(rect.origin.x), "y": Double(rect.origin.y), "width": Double(rect.width), "height": Double(rect.height)]
            }
            _ = try? await env.annotationService.createHighlight(
                in: documentID,
                pageIndex: pageIndex,
                rects: rectsDict,
                textSnippet: textSnippet,
                colorCategory: color
            )
            let annotations = env.annotationService.annotations.map { dto in
                AnnotationData(
                    id: dto.id,
                    kind: dto.kind.rawValue,
                    pageIndex: dto.pageIndex,
                    rects: dto.rects,
                    colorCategory: dto.colorCategory,
                    textSnippet: dto.textSnippet
                )
            }
            await MainActor.run {
                viewModel.setAnnotations(annotations)
            }
        }

        viewModel.onDeleteAllAnnotations = { [weak environment] in
            guard let env = environment else { return }
            try? await env.annotationService.deleteAllAnnotations(for: documentID)
            await MainActor.run {
                viewModel.setAnnotations([])
            }
        }

        viewModel.onDeleteAnnotation = { [weak environment] annotationID in
            guard let env = environment else { return }
            try? await env.annotationService.deleteAnnotation(annotationID)
            // Refresh annotations
            env.annotationService.fetchAnnotations(for: documentID)
            let updatedAnnotations = env.annotationService.annotations.map { dto in
                AnnotationData(
                    id: dto.id,
                    kind: dto.kind.rawValue,
                    pageIndex: dto.pageIndex,
                    rects: dto.rects,
                    colorCategory: dto.colorCategory,
                    textSnippet: dto.textSnippet
                )
            }
            await MainActor.run {
                viewModel.setAnnotations(updatedAnnotations)
            }
        }

        viewModel.onRemoveAnnotationAt = { [weak environment] pageIndex, bounds in
            guard let env = environment else { return }
            // Find and remove annotation at specific location
            if let annotation = env.annotationService.annotations.first(where: { dto in
                dto.pageIndex == pageIndex && dto.rects.contains(where: { rect in
                    abs(rect.origin.x - bounds.origin.x) < 1 &&
                    abs(rect.origin.y - bounds.origin.y) < 1 &&
                    abs(rect.size.width - bounds.size.width) < 1 &&
                    abs(rect.size.height - bounds.size.height) < 1
                })
            }) {
                try? await env.annotationService.deleteAnnotation(annotation.id)
                // Refresh annotations
                env.annotationService.fetchAnnotations(for: documentID)
                let updatedAnnotations = env.annotationService.annotations.map { dto in
                    AnnotationData(
                        id: dto.id,
                        kind: dto.kind.rawValue,
                        pageIndex: dto.pageIndex,
                        rects: dto.rects,
                        colorCategory: dto.colorCategory,
                        textSnippet: dto.textSnippet
                    )
                }
                await MainActor.run {
                    viewModel.setAnnotations(updatedAnnotations)
                }
            }
        }

        let initialAnnotations = environment.annotationService.annotations.map { dto in
            AnnotationData(
                id: dto.id,
                kind: dto.kind.rawValue,
                pageIndex: dto.pageIndex,
                rects: dto.rects,
                colorCategory: dto.colorCategory,
                textSnippet: dto.textSnippet
            )
        }
        viewModel.setAnnotations(initialAnnotations)

        return AnyView(PDFViewerView(viewModel: viewModel))
    }

    // MARK: - EPUB Viewer

    private func makeEPUBViewer(documentID: UUID, url: URL, title: String) -> AnyView {
        let viewModel = EPUBReaderViewModel(documentID: documentID, documentURL: url, title: title)

        environment.annotationService.fetchAnnotations(for: documentID)

        // Wire up highlight creation
        viewModel.onCreateHighlight = { [weak environment] chapterIndex, chapterHref, startOffset, endOffset, text, color in
            guard let env = environment else { return }
            let rectsDict: [[String: Double]] = [[
                "x": Double(startOffset),
                "y": Double(endOffset),
                "width": 0,
                "height": 0
            ]]
            _ = try? await env.annotationService.createHighlight(
                in: documentID,
                pageIndex: chapterIndex,
                rects: rectsDict,
                textSnippet: text,
                colorCategory: color
            )
        }

        viewModel.onDeleteAllHighlights = { [weak environment] in
            guard let env = environment else { return }
            try? await env.annotationService.deleteAllAnnotations(for: documentID)
        }

        // Set initial highlights from existing annotations
        let initialHighlights: [EPUBHighlightData] = environment.annotationService.annotations.compactMap { dto in
            guard !dto.rects.isEmpty else { return nil }
            let startOffset = Int(dto.rects[0].origin.x)
            let endOffset = Int(dto.rects[0].origin.y)
            return EPUBHighlightData(
                id: dto.id,
                chapterIndex: dto.pageIndex,
                chapterHref: "",
                startOffset: startOffset,
                endOffset: endOffset,
                selectedText: dto.textSnippet ?? "",
                colorCategory: dto.colorCategory,
                createdAt: dto.createdAt
            )
        }
        viewModel.setHighlights(initialHighlights)

        // Parse EPUB and set up chapters
        Task { @MainActor in
            do {
                guard let libraryURL = environment.libraryURL else {
                    viewModel.errorMessage = "Library not available"
                    viewModel.isLoading = false
                    return
                }
                let cacheURL = await environment.libraryRootStore.epubCacheURL(for: documentID, in: libraryURL)
                let parser = EPUBParser()
                let book = try parser.parse(epubURL: url, extractTo: cacheURL)

                viewModel.chapterCount = book.spine.count
                viewModel.chapterTitles = book.spine.map { $0.title ?? "Chapter \($0.index + 1)" }
                viewModel.chapterHTMLPaths = book.spine.map { book.resolvedURL(for: $0) }
                viewModel.extractedBookURL = book.extractedURL
                viewModel.opfDirectory = book.opfDirectory
                viewModel.isLoading = false
            } catch {
                viewModel.errorMessage = error.localizedDescription
                viewModel.isLoading = false
            }
        }

        return AnyView(EPUBReaderView(viewModel: viewModel))
    }

    // MARK: - Note Handler

    private func noteHandler(noteID: UUID, title: String, preview: String) -> AnyView {
        guard let noteDTO = environment.documentService.getNote(byID: noteID) else {
            return AnyView(
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Note Not Found")
                        .font(.title2)
                    Text("The note could not be loaded")
                        .foregroundColor(.secondary)
                }
            )
        }

        let viewModel = NoteEditorViewModel(
            noteID: noteDTO.id,
            title: noteDTO.title,
            body: noteDTO.body
        )
        viewModel.onSave = { [weak environment] id, title, body in
            try await environment?.documentService.updateNote(id, title: title, body: body)
        }
        viewModel.onDelete = { [weak environment] id in
            try await environment?.documentService.deleteNote(id)
        }

        return AnyView(MarkdownEditorView(viewModel: viewModel))
    }
}
