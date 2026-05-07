import SwiftUI
import WndrKit
import WndrData
import WndrPDF
import WndrNotes

// TEMPORARY: EPUB types stub - Remove after adding EPUB files to Xcode project
// The actual implementations exist in WndrKit/Sources but need to be added to the Xcode project
#if true // Set to false once EPUB files are properly added to Xcode
struct EPUBHighlightData: Identifiable {
    let id: UUID
    let chapterIndex: Int
    let chapterHref: String
    let startOffset: Int
    let endOffset: Int
    let selectedText: String
    let colorCategory: String
    let createdAt: Date

    init(id: UUID, chapterIndex: Int, chapterHref: String, startOffset: Int, endOffset: Int, selectedText: String, colorCategory: String = "yellow", createdAt: Date = Date()) {
        self.id = id
        self.chapterIndex = chapterIndex
        self.chapterHref = chapterHref
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.selectedText = selectedText
        self.colorCategory = colorCategory
        self.createdAt = createdAt
    }
}

@MainActor
class EPUBReaderViewModel: ObservableObject {
    let documentID: UUID
    let documentURL: URL
    let title: String
    @Published var isLoading: Bool = true
    @Published var errorMessage: String?
    @Published var chapterCount: Int = 0
    @Published var chapterTitles: [String] = []
    var chapterHTMLPaths: [URL] = []
    var extractedBookURL: URL?
    var opfDirectory: String = ""

    var onCreateHighlight: ((Int, String, Int, Int, String, String) async -> Void)?
    var onDeleteAllHighlights: (() async -> Void)?

    init(documentID: UUID, documentURL: URL, title: String) {
        self.documentID = documentID
        self.documentURL = documentURL
        self.title = title
    }

    func setHighlights(_ highlights: [EPUBHighlightData]) {
        // Stub implementation
    }
}

struct EPUBReaderView: View {
    @ObservedObject var viewModel: EPUBReaderViewModel

    init(viewModel: EPUBReaderViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack {
            if viewModel.isLoading {
                ProgressView("Loading EPUB...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.errorMessage {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Error Loading EPUB")
                        .font(.title2)
                    Text(error)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("EPUB Reader Placeholder")
                    .font(.title)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text("Add EPUBReaderView.swift and EPUBReaderViewModel.swift to Xcode project")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct EPUBBook {
    struct SpineItem {
        let index: Int
        let title: String?
    }
    let spine: [SpineItem] = []
    let extractedURL: URL = URL(fileURLWithPath: "/tmp")
    let opfDirectory: String = ""
    func resolvedURL(for item: SpineItem) -> URL {
        return URL(fileURLWithPath: "/tmp")
    }
}

class EPUBParser {
    func parse(epubURL: URL, extractTo: URL) throws -> EPUBBook {
        return EPUBBook()
    }
}
#endif

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
            onSetDocumentCollection: onSetDocumentCollection,
            onDropDocumentOnCollection: onDropDocumentOnCollection,
            onUpdateDocumentMetadata: onUpdateDocumentMetadata
        )
        .environment(\.contentAreaDocumentHandler, documentHandler)
        .environment(\.contentAreaNoteHandler, noteHandler)
        .environment(\.contentAreaDropHandler, dropHandler)
    }

    private func dropHandler(urls: [URL]) {
        Task {
            await environment.importCoordinator.importDocuments(from: urls)
            // Refresh the document list after import
            environment.documentService.fetchAllDocuments()
            await MainActor.run {
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
                // Update to document list view if we were on empty state
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

        // Route to EPUB reader if file is an EPUB
        if url.pathExtension.lowercased() == "epub" {
            return makeEPUBViewer(documentID: documentID, url: url, title: title)
        }

        // Default: PDF viewer
        print("DEBUG: Loading PDF from URL: \(url.path)")
        return makePDFViewer(documentID: documentID, url: url, title: title)
    }

    // MARK: - PDF Viewer

    private func makePDFViewer(documentID: UUID, url: URL, title: String) -> AnyView {
        let viewModel = PDFViewerViewModel(documentID: documentID, documentURL: url, title: title)

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

        return AnyView(PDFViewerView(viewModel: viewModel))
    }

    // MARK: - EPUB Viewer

    private func makeEPUBViewer(documentID: UUID, url: URL, title: String) -> AnyView {
        let viewModel = EPUBReaderViewModel(documentID: documentID, documentURL: url, title: title)

        // Load annotations for this document
        environment.annotationService.fetchAnnotations(for: documentID)

        // Wire up highlight creation
        viewModel.onCreateHighlight = { [weak environment] (chapterIndex: Int, chapterHref: String, startOffset: Int, endOffset: Int, text: String, color: String) in
            guard let env = environment else { return }
            // Store EPUB highlight data in the annotation's rects field as JSON
            let epubLocation: [[String: Any]] = [[
                "type": "epub",
                "chapterHref": chapterHref,
                "startOffset": startOffset,
                "endOffset": endOffset
            ]]
            let rectsDict = epubLocation.map { entry -> [String: Double] in
                // Encode offsets as doubles in the existing rect format
                [
                    "x": Double(startOffset),
                    "y": Double(endOffset),
                    "width": 0,
                    "height": 0
                ]
            }
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
            // Convert annotation DTO to EPUB highlight data
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

    private func noteHandler(noteID: UUID, title: String, preview: String) -> AnyView {
        // Fetch the full note from the service
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
            guard let environment, let libraryURL = environment.libraryURL else { return }
            try await environment.documentService.updateNote(
                id,
                title: title,
                body: body,
                libraryURL: libraryURL,
                libraryStore: environment.libraryRootStore
            )
        }
        viewModel.onDelete = { [weak environment] id in
            guard let environment, let libraryURL = environment.libraryURL else { return }
            try await environment.documentService.deleteNote(
                id,
                libraryURL: libraryURL,
                libraryStore: environment.libraryRootStore
            )
        }

        return AnyView(MarkdownEditorView(viewModel: viewModel))
    }
}
