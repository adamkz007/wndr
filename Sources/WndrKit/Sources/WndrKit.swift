import Combine
import SwiftUI

@MainActor
public protocol LibraryRootHandling: AnyObject, ObservableObject {
    var libraryURL: URL? { get }
    func presentLibraryChooser()
}

public struct LookPrimaryView<Coordinator: LibraryRootHandling>: View {
    @ObservedObject private var coordinator: Coordinator
    @ObservedObject private var sidebarViewModel: LibrarySidebarViewModel
    @ObservedObject private var contentViewModel: ContentAreaViewModel
    @State private var showInspector = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    var statusMessage: String?
    var availableTags: [DocumentTagItem]
    var availableCollections: [CollectionMenuItem]
    var onToggleTag: ((UUID, UUID) -> Void)?
    var onRenameTag: ((UUID, String) -> Void)?
    var onRenameCollection: ((UUID, String) -> Void)?
    var onDeleteTag: ((UUID) -> Void)?
    var onDeleteCollection: ((UUID) -> Void)?
    var onRenameDocument: ((UUID, String) -> Void)?
    var onDeleteDocument: ((UUID) -> Void)?
    var onRenameNote: ((UUID, String) -> Void)?
    var onDeleteNote: ((UUID) -> Void)?
    var onSetDocumentCollection: ((UUID, UUID?) -> Void)?
    var onDropDocumentOnCollection: ((UUID, UUID) -> Void)?
    var onUpdateDocumentMetadata: ((UUID, String, String?, [String]?) -> Void)?

    public init(
        coordinator: Coordinator,
        sidebarViewModel: LibrarySidebarViewModel,
        contentViewModel: ContentAreaViewModel,
        statusMessage: String? = nil,
        availableTags: [DocumentTagItem] = [],
        availableCollections: [CollectionMenuItem] = [],
        onToggleTag: ((UUID, UUID) -> Void)? = nil,
        onRenameTag: ((UUID, String) -> Void)? = nil,
        onRenameCollection: ((UUID, String) -> Void)? = nil,
        onDeleteTag: ((UUID) -> Void)? = nil,
        onDeleteCollection: ((UUID) -> Void)? = nil,
        onRenameDocument: ((UUID, String) -> Void)? = nil,
        onDeleteDocument: ((UUID) -> Void)? = nil,
        onRenameNote: ((UUID, String) -> Void)? = nil,
        onDeleteNote: ((UUID) -> Void)? = nil,
        onSetDocumentCollection: ((UUID, UUID?) -> Void)? = nil,
        onDropDocumentOnCollection: ((UUID, UUID) -> Void)? = nil,
        onUpdateDocumentMetadata: ((UUID, String, String?, [String]?) -> Void)? = nil
    ) {
        self._coordinator = ObservedObject(wrappedValue: coordinator)
        self._sidebarViewModel = ObservedObject(wrappedValue: sidebarViewModel)
        self._contentViewModel = ObservedObject(wrappedValue: contentViewModel)
        self.statusMessage = statusMessage
        self.availableTags = availableTags
        self.availableCollections = availableCollections
        self.onToggleTag = onToggleTag
        self.onRenameTag = onRenameTag
        self.onRenameCollection = onRenameCollection
        self.onDeleteTag = onDeleteTag
        self.onDeleteCollection = onDeleteCollection
        self.onRenameDocument = onRenameDocument
        self.onDeleteDocument = onDeleteDocument
        self.onRenameNote = onRenameNote
        self.onDeleteNote = onDeleteNote
        self.onSetDocumentCollection = onSetDocumentCollection
        self.onDropDocumentOnCollection = onDropDocumentOnCollection
        self.onUpdateDocumentMetadata = onUpdateDocumentMetadata
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            LibrarySidebarView(viewModel: sidebarViewModel, statusMessage: statusMessage, onRenameTag: onRenameTag, onRenameCollection: onRenameCollection, onDeleteTag: onDeleteTag, onDeleteCollection: onDeleteCollection, onDropDocumentOnCollection: onDropDocumentOnCollection)
                .navigationTitle("Library")
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } content: {
            ContentListView(
                viewModel: contentViewModel,
                selectedSidebarItem: $sidebarViewModel.selectedItem,
                availableTags: availableTags,
                availableCollections: availableCollections,
                onToggleTag: onToggleTag,
                onRenameDocument: onRenameDocument,
                onDeleteDocument: onDeleteDocument,
                onRenameNote: onRenameNote,
                onDeleteNote: onDeleteNote,
                onSetDocumentCollection: onSetDocumentCollection
            )
            .navigationTitle(contentTitle)
            .navigationSplitViewColumnWidth(min: 200, ideal: 280, max: 400)
        } detail: {
            DetailAreaView(
                viewModel: contentViewModel,
                showInspector: showInspector,
                onToggleInspector: toggleInspector
            )
            .navigationSplitViewColumnWidth(min: 400, ideal: 500, max: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            sidebarViewModel.refresh()
        }
    }

    private var contentTitle: String {
        guard let selection = sidebarViewModel.selectedItem else {
            return "Wndr"
        }

        switch selection {
        case .allDocuments:
            return "All Documents"
        case .unsortedDocuments:
            return "Unsorted Documents"
        case .allNotes:
            return "Notes"
        case .collection:
            return "Collection"
        case .tag:
            return "Tag"
        }
    }

    private func toggleInspector() {
        withAnimation(.easeInOut(duration: 0.24)) {
            showInspector.toggle()
        }
    }
}

// MARK: - Content List View (Middle Pane - Lists Only)

public struct ContentListView: View {
    @ObservedObject var viewModel: ContentAreaViewModel
    @Binding var selectedSidebarItem: SidebarSelection?
    @Environment(\.contentAreaDropHandler) var dropHandler
    @State private var isDropTargeted = false
    var availableTags: [DocumentTagItem] = []
    var availableCollections: [CollectionMenuItem] = []
    var onToggleTag: ((UUID, UUID) -> Void)? = nil
    var onRenameDocument: ((UUID, String) -> Void)? = nil
    var onDeleteDocument: ((UUID) -> Void)? = nil
    var onRenameNote: ((UUID, String) -> Void)? = nil
    var onDeleteNote: ((UUID) -> Void)? = nil
    var onSetDocumentCollection: ((UUID, UUID?) -> Void)? = nil

    public init(
        viewModel: ContentAreaViewModel,
        selectedSidebarItem: Binding<SidebarSelection?>,
        availableTags: [DocumentTagItem] = [],
        availableCollections: [CollectionMenuItem] = [],
        onToggleTag: ((UUID, UUID) -> Void)? = nil,
        onRenameDocument: ((UUID, String) -> Void)? = nil,
        onDeleteDocument: ((UUID) -> Void)? = nil,
        onRenameNote: ((UUID, String) -> Void)? = nil,
        onDeleteNote: ((UUID) -> Void)? = nil,
        onSetDocumentCollection: ((UUID, UUID?) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self._selectedSidebarItem = selectedSidebarItem
        self.availableTags = availableTags
        self.availableCollections = availableCollections
        self.onToggleTag = onToggleTag
        self.onRenameDocument = onRenameDocument
        self.onDeleteDocument = onDeleteDocument
        self.onRenameNote = onRenameNote
        self.onDeleteNote = onDeleteNote
        self.onSetDocumentCollection = onSetDocumentCollection
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Search bar
            ContentSearchBar(viewModel: viewModel)

            Divider()

            // Content area
            Group {
                if viewModel.isContentSearchActive {
                    // Content search results
                    SearchResultsListView(
                        results: viewModel.contentSearchResults,
                        isSearching: viewModel.isSearchingContent,
                        onSelectDocument: viewModel.selectDocument,
                        onSelectNote: viewModel.selectNote
                    )
                } else {
                    switch selectedSidebarItem {
                    case .allDocuments, .unsortedDocuments, .collection, .tag, .none:
                        if viewModel.filteredDocuments.isEmpty {
                            if viewModel.documents.isEmpty {
                                emptyDocumentsState
                            } else {
                                NoSearchResultsView()
                            }
                        } else {
                            DocumentListView(
                                documents: viewModel.filteredDocuments,
                                selectedID: selectedDocumentID,
                                onSelect: viewModel.selectDocument,
                                availableTags: availableTags,
                                availableCollections: availableCollections,
                                onToggleTag: onToggleTag,
                                onRename: onRenameDocument,
                                onDelete: onDeleteDocument,
                                onSetCollection: onSetDocumentCollection
                            )
                        }
                    case .allNotes:
                        if viewModel.filteredNotes.isEmpty {
                            if viewModel.notes.isEmpty {
                                emptyNotesState
                            } else {
                                NoSearchResultsView()
                            }
                        } else {
                            NoteListView(
                                notes: viewModel.filteredNotes,
                                selectedID: selectedNoteID,
                                onSelect: viewModel.selectNote,
                                onRename: onRenameNote,
                                onDelete: onDeleteNote
                            )
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            ContentListStatusBar(
                fileCount: displayedItemCount,
                storageBytes: viewModel.totalStorageBytes
            )
        }
        .background(Color.platformTextBackground)
        .onChange(of: selectedSidebarItem) { _, newValue in
            Task { @MainActor in
                viewModel.updateContent(for: newValue)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button(action: viewModel.showImportPanel) {
                    Image(systemName: "plus")
                }
                .keyboardShortcut("i", modifiers: .command)
                .help("Add Document")

                Button(action: viewModel.showNewNoteSheet) {
                    Image(systemName: "square.and.pencil")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("New Note")
            }
        }
        .sheet(isPresented: $viewModel.showingNewNoteSheet) {
            NewNoteSheet(
                onCreate: { title in
                    viewModel.createNote(withTitle: title)
                }
            )
        }
        .onDrop(of: [.pdf, .fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .background(Color.accentColor.opacity(0.1))
                    .padding(8)
            }
        }
    }

    private var displayedItemCount: Int {
        if viewModel.isContentSearchActive {
            return viewModel.contentSearchResults.count
        }
        return viewModel.filteredDocuments.count + viewModel.filteredNotes.count
    }

    private var selectedDocumentID: UUID? {
        if case .documentDetail(let id) = viewModel.contentMode {
            return id
        }
        return nil
    }

    private var selectedNoteID: UUID? {
        if case .noteDetail(let id) = viewModel.contentMode {
            return id
        }
        return nil
    }

    private static let supportedExtensions: Set<String> = ["pdf"]

    private func handleDrop(providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier("com.adobe.pdf") {
                group.enter()
                provider.loadItem(forTypeIdentifier: "com.adobe.pdf", options: nil) { item, error in
                    defer { group.leave() }
                    if let url = item as? URL {
                        urls.append(url)
                    } else if let data = item as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil) {
                        urls.append(url)
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                group.enter()
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                    defer { group.leave() }
                    if let url = item as? URL,
                       Self.supportedExtensions.contains(url.pathExtension.lowercased()) {
                        urls.append(url)
                    } else if let data = item as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil),
                              Self.supportedExtensions.contains(url.pathExtension.lowercased()) {
                        urls.append(url)
                    }
                }
            }
        }

        group.notify(queue: .main) {
            if !urls.isEmpty {
                dropHandler?(urls)
            }
        }
    }

    private var emptyDocumentsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Documents")
                .font(.title2)
            Text("Drop PDF files here or use the Import button")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button(action: viewModel.showImportPanel) {
                    Label("Import Document", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyNotesState: some View {
        VStack(spacing: 16) {
            Image(systemName: "note.text")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Notes")
                .font(.title2)
            Text("Create a note to get started")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: viewModel.showNewNoteSheet) {
                Label("New Note", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Content List Status Bar

struct ContentListStatusBar: View {
    let fileCount: Int
    let storageBytes: Int64

    var body: some View {
        HStack(spacing: 12) {
            Label("\(fileCount) \(fileCount == 1 ? "item" : "items")", systemImage: "doc.on.doc")
            Spacer()
            Label(formattedStorage, systemImage: "internaldrive")
        }
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.platformControlBackground)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var formattedStorage: String {
        SharedFormatters.storageTotal.string(fromByteCount: storageBytes)
    }
}

// MARK: - Detail Area View (Right Pane - Document/Note Viewer)

public struct DetailAreaView: View {
    @ObservedObject var viewModel: ContentAreaViewModel
    var showInspector: Bool
    var onToggleInspector: () -> Void

    @Environment(\.contentAreaDocumentHandler) var documentHandler
    @Environment(\.contentAreaNoteHandler) var noteHandler
    @Environment(\.contentAreaDocumentLinkedNotesHandler) var linkedNotesHandler

    private let inspectorWidth: CGFloat = 300
    private let inspectorDividerWidth: CGFloat = 1

    public var body: some View {
        ZStack(alignment: .trailing) {
            detailContent
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)

            inspectorOverlay
        }
        .clipped()
        .animation(.easeInOut(duration: 0.24), value: showInspector)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onToggleInspector) {
                    Image(systemName: "sidebar.right")
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .help("Toggle Inspector")
            }
        }
    }

    private var inspectorOverlay: some View {
        HStack(spacing: 0) {
            Divider()
                .opacity(showInspector ? 1 : 0)

            InspectorPanelView(
                inspectorMode: currentInspectorMode,
                linkedNotes: currentLinkedNotes,
                onSelectNote: viewModel.selectNote
            )
            .frame(width: inspectorWidth)
        }
        .frame(width: inspectorWidth + inspectorDividerWidth)
        .frame(maxHeight: .infinity, alignment: .trailing)
        .background(Color.clear)
        .offset(x: showInspector ? 0 : inspectorWidth + inspectorDividerWidth)
        .opacity(showInspector ? 1 : 0.01)
        .allowsHitTesting(showInspector)
        .accessibilityHidden(!showInspector)
        .shadow(color: Color.black.opacity(showInspector ? 0.08 : 0), radius: 10, x: -2, y: 0)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch viewModel.contentMode {
        case .empty, .documentList, .noteList:
            emptyDetailState
        case .documentDetail(let documentID):
            if let documentHandler = documentHandler,
               let document = viewModel.documents.first(where: { $0.id == documentID }) {
                documentHandler(documentID, document.fileURL, document.title)
            } else {
                DocumentDetailPlaceholder(documentID: documentID)
            }
        case .noteDetail(let noteID):
            if let noteHandler = noteHandler,
               let note = viewModel.notes.first(where: { $0.id == noteID }) {
                noteHandler(noteID, note.title, note.preview)
            } else {
                NoteDetailPlaceholder(noteID: noteID)
            }
        }
    }

    private var emptyDetailState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 64))
                .foregroundColor(.secondary.opacity(0.5))
            Text("Select a Document or Note")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Choose an item from the list to view it here")
                .foregroundColor(.secondary.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var currentInspectorMode: InspectorMode {
        switch viewModel.contentMode {
        case .documentDetail(let id):
            guard let document = viewModel.documents.first(where: { $0.id == id }) else { return .none }
            return .document(document)
        case .noteDetail(let id):
            guard let note = viewModel.notes.first(where: { $0.id == id }) else { return .none }
            return .note(note)
        case .empty, .documentList, .noteList:
            return .none
        }
    }

    private var currentLinkedNotes: [NoteItem] {
        guard case .documentDetail(let id) = viewModel.contentMode else { return [] }
        return linkedNotesHandler?(id) ?? []
    }
}

// MARK: - New Note Sheet

public struct NewNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var noteTitle: String = ""
    var onCreate: (String) -> Void

    public init(onCreate: @escaping (String) -> Void) {
        self.onCreate = onCreate
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text("New Note")
                .font(.headline)

            TextField("Note title", text: $noteTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    createAndDismiss()
                }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create") {
                    createAndDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(noteTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(width: 320)
    }

    private func createAndDismiss() {
        let title = noteTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        onCreate(title)
        dismiss()
    }
}
