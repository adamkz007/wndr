import SwiftUI
import WndrKit
import WndrData
import WndrPDF
import WndrNotes

struct ContentWrapper: View {
    let environment: AppEnvironment
    @ObservedObject var sidebarViewModel: LibrarySidebarViewModel
    @ObservedObject var contentViewModel: ContentAreaViewModel
    @ObservedObject var importCoordinator: ImportCoordinator
    var availableTags: [DocumentTagItem] = []
    var availableCollections: [CollectionMenuItem] = []
    var onToggleTag: ((UUID, UUID) -> Void)? = nil
    var onRenameTag: ((UUID, String) -> Void)? = nil
    var onRenameCollection: ((UUID, String) -> Void)? = nil
    var onDeleteTag: ((UUID) -> Void)? = nil
    var onDeleteCollection: ((UUID) -> Void)? = nil
    var onRenameDocument: ((UUID, String) -> Void)? = nil
    var onDeleteDocument: ((UUID) -> Void)? = nil
    var onRenameNote: ((UUID, String) -> Void)? = nil
    var onDeleteNote: ((UUID) -> Void)? = nil
    var onSetDocumentCollection: ((UUID, UUID?) -> Void)? = nil
    var onDropDocumentOnCollection: ((UUID, UUID) -> Void)? = nil
    var onUpdateDocumentMetadata: ((UUID, String, String?, [String]?) -> Void)? = nil

    var body: some View {
        LookPrimaryView(
            coordinator: environment.libraryRootCoordinator,
            sidebarViewModel: sidebarViewModel,
            contentViewModel: contentViewModel,
            statusMessage: importCoordinator.statusMessage,
            availableTags: availableTags,
            availableCollections: availableCollections,
            onToggleTag: onToggleTag,
            onRenameTag: onRenameTag,
            onRenameCollection: onRenameCollection,
            onDeleteTag: onDeleteTag,
            onDeleteCollection: onDeleteCollection,
            onRenameDocument: onRenameDocument,
            onDeleteDocument: onDeleteDocument,
            onRenameNote: onRenameNote,
            onDeleteNote: onDeleteNote,
            onSetDocumentCollection: onSetDocumentCollection,
            onDropDocumentOnCollection: onDropDocumentOnCollection,
            onUpdateDocumentMetadata: onUpdateDocumentMetadata
        )
        .environment(\.contentAreaDocumentHandler, documentHandler)
        .environment(\.contentAreaNoteHandler, noteHandler)
        .environment(\.contentAreaDropHandler, dropHandler)
        .environment(\.contentAreaDocumentLinkedNotesHandler, linkedNotesHandler)
    }

    private func dropHandler(urls: [URL]) {
        Task {
            await environment.importCoordinator.importDocuments(from: urls)
        }
    }

    private func thumbnailURL(for documentID: UUID) -> URL? {
        guard let libraryURL = environment.libraryURL else { return nil }
        let url = libraryURL.appendingPathComponent("Index/Thumbnails/\(documentID.uuidString).png")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

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
                    Text("URL was nil")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            )
        }

        // Check if file exists
        if !FileManager.default.fileExists(atPath: url.path) {
            return AnyView(
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("File Not Found")
                        .font(.title2)
                    Text("The document file does not exist at the expected location")
                        .foregroundColor(.secondary)
                    Text("Path: \(url.path)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                }
            )
        }

        // PDF viewer
        print("DEBUG: Loading PDF from URL: \(url.path)")
        return makePDFViewer(documentID: documentID, url: url, title: title)
    }

    // MARK: - PDF Viewer

    private func makePDFViewer(documentID: UUID, url: URL, title: String) -> AnyView {
        let viewModel = PDFViewerViewModel(documentID: documentID, documentURL: url, title: title)
        if let savedPageIndex = PDFReadProgressStore.pageIndex(for: documentID) {
            viewModel.goToPage(savedPageIndex)
        }
        viewModel.onPageChanged = { currentPage, pageCount in
            PDFReadProgressStore.save(
                documentID: documentID,
                currentPage: currentPage,
                pageCount: pageCount
            )
        }

        // Load annotations for this document
        environment.annotationService.fetchAnnotations(for: documentID)
        print("DEBUG: Loaded \(environment.annotationService.annotations.count) annotations for document \(documentID)")

        // Wire up annotation handlers
        viewModel.onCreateAnnotation = { [weak environment] pageIndex, rects, textSnippet, color in
            guard let env = environment else { return }
            let rectsDict = rects.map { rect -> [String: Double] in
                ["x": Double(rect.origin.x), "y": Double(rect.origin.y), "width": Double(rect.width), "height": Double(rect.height)]
            }
            do {
                _ = try await env.annotationService.createHighlight(
                    in: documentID,
                    pageIndex: pageIndex,
                    rects: rectsDict,
                    textSnippet: textSnippet,
                    colorCategory: color
                )
                print("DEBUG: Successfully created highlight annotation for document \(documentID)")
            } catch {
                print("ERROR: Failed to create highlight annotation: \(error.localizedDescription)")
            }
            // Refresh annotations in view model
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

        // Set initial annotations
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
        print("DEBUG: Setting \(initialAnnotations.count) initial annotations on PDF viewer")
        viewModel.setAnnotations(initialAnnotations)

        return AnyView(
            DocumentOpenMetricsView(documentID: documentID) {
                PDFViewerView(viewModel: viewModel)
            }
        )
    }

    private func noteHandler(noteID: UUID, title: String, preview: String) -> AnyView {
        AnyView(
            NoteEditorContainerView(
                noteID: noteID,
                environment: environment,
                contentViewModel: contentViewModel
            )
            .id(noteID)
        )
    }

    private func linkedNotesHandler(documentID: UUID) -> [NoteItem] {
        environment.documentService.linkedNotes(forDocumentID: documentID).map { dto in
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
}

private struct NoteEditorContainerView: View {
    let noteID: UUID
    let environment: AppEnvironment
    @ObservedObject var contentViewModel: ContentAreaViewModel

    @StateObject private var viewModel: NoteEditorViewModel

    init(noteID: UUID, environment: AppEnvironment, contentViewModel: ContentAreaViewModel) {
        self.noteID = noteID
        self.environment = environment
        self._contentViewModel = ObservedObject(wrappedValue: contentViewModel)

        let noteDTO = environment.documentService.getNote(byID: noteID)
        _viewModel = StateObject(
            wrappedValue: NoteEditorViewModel(
                noteID: noteID,
                title: noteDTO?.title ?? "Untitled Note",
                body: noteDTO?.body ?? ""
            )
        )
    }

    var body: some View {
        MarkdownEditorView(viewModel: viewModel)
            .task(id: noteID) {
                configureViewModel()
                syncFromStoreIfNeeded()
            }
    }

    private func configureViewModel() {
        viewModel.onSearchDocumentLinks = { query in
            environment.documentService.searchDocumentsForLinking(query: query).map { suggestion in
                NoteDocumentLinkSuggestion(
                    id: suggestion.id,
                    title: suggestion.title,
                    subtitle: suggestion.subtitle,
                    documentType: suggestion.documentType
                )
            }
        }

        viewModel.onSave = { id, title, body in
            guard let libraryURL = environment.libraryURL else { return }
            try await environment.documentService.updateNote(
                id,
                title: title,
                body: body,
                libraryURL: libraryURL,
                libraryStore: environment.libraryRootStore
            )

            await MainActor.run {
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
            }
        }

        viewModel.onDelete = { id in
            guard let libraryURL = environment.libraryURL else { return }
            try await environment.documentService.deleteNote(
                id,
                libraryURL: libraryURL,
                libraryStore: environment.libraryRootStore
            )
        }
    }

    private func syncFromStoreIfNeeded() {
        guard let noteDTO = environment.documentService.getNote(byID: noteID) else { return }
        guard !viewModel.isDirty else { return }

        if viewModel.title != noteDTO.title {
            viewModel.title = noteDTO.title
        }
        if viewModel.body != noteDTO.body {
            viewModel.body = noteDTO.body
        }
        viewModel.lastSaved = noteDTO.updatedAt ?? noteDTO.createdAt
        viewModel.isDirty = false
    }
}

private struct DocumentOpenMetricsView<Content: View>: View {
    let documentID: UUID
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .task(id: documentID) {
                PerformanceMonitor.shared.begin(.documentOpen)
                await Task.yield()
                PerformanceMonitor.shared.end(.documentOpen, metadata: ["document_id": documentID.uuidString])
            }
    }
}
