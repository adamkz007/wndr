import SwiftUI
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - Content Mode

public enum ContentMode: Equatable {
    case empty
    case documentList
    case noteList
    case documentDetail(UUID)
    case noteDetail(UUID)
}

// MARK: - Thumbnail Image View

/// Loads a thumbnail image asynchronously from a local file URL and caches it
/// in `@State` so that repeated SwiftUI body evaluations don't re-read from disk.
/// Falls back to a document icon when no URL is provided or loading fails.
private struct ThumbnailImageView: View {
    let url: URL?
    var documentType: String = "pdf"
    @State private var loadedImage: PlatformImage?

    var body: some View {
        Group {
            if let image = loadedImage {
                image.swiftUIImage
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(fallbackColor.opacity(0.1))
                    .overlay(
                        Image(systemName: fallbackIcon)
                            .font(.system(size: 16))
                            .foregroundColor(fallbackColor)
                    )
            }
        }
        .frame(width: 32, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .task(id: url) {
            loadedImage = await loadImage()
        }
    }

    private var fallbackIcon: String {
        documentType == "epub" ? "book.fill" : "doc.fill"
    }

    private var fallbackColor: Color {
        documentType == "epub" ? .teal : .blue
    }

    private func loadImage() async -> PlatformImage? {
        guard let url = url else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let image = PlatformImage.loadFromURL(url)
                continuation.resume(returning: image)
            }
        }
    }
}

// MARK: - Document Drag Item

/// Transferable wrapper for dragging documents by UUID.
/// Uses raw UTF-8 encoding (not JSON) so existing `.onDrop(of: [.utf8PlainText])`
/// handlers in the sidebar can read the UUID string directly.
struct DocumentDragItem: Transferable {
    let documentID: UUID

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(contentType: .utf8PlainText) { item in
            Data(item.documentID.uuidString.utf8)
        } importing: { data in
            guard let string = String(data: data, encoding: .utf8),
                  let uuid = UUID(uuidString: string) else {
                throw CocoaError(.formatting)
            }
            return DocumentDragItem(documentID: uuid)
        }
    }
}

// MARK: - Document List View

struct DocumentListView: View {
    let documents: [DocumentItem]
    var selectedID: UUID?
    let onSelect: (UUID) -> Void
    var availableTags: [DocumentTagItem] = []
    var availableCollections: [CollectionMenuItem] = []
    var onToggleTag: ((UUID, UUID) -> Void)? = nil
    var onRename: ((UUID, String) -> Void)? = nil
    var onDelete: ((UUID) -> Void)? = nil
    var onSetCollection: ((UUID, UUID?) -> Void)? = nil

    // Use @State so the List can mutate the selection directly,
    // avoiding the stale-binding issue with Binding(get:set:).
    @State private var internalSelection: UUID?

    var body: some View {
        List(documents, selection: $internalSelection) { document in
            DocumentRow(
                document: document,
                isSelected: document.id == internalSelection,
                availableTags: availableTags,
                availableCollections: availableCollections,
                onToggleTag: { tagID in
                    onToggleTag?(document.id, tagID)
                },
                onRename: { newName in
                    onRename?(document.id, newName)
                },
                onDelete: {
                    onDelete?(document.id)
                },
                onSetCollection: { collectionID in
                    onSetCollection?(document.id, collectionID)
                }
            )
            .tag(document.id)
        }
        .listStyle(.sidebar)
        .onAppear {
            internalSelection = selectedID
        }
        .onChange(of: internalSelection) { newValue in
            if let id = newValue {
                onSelect(id)
            }
        }
        .onChange(of: selectedID) { newValue in
            if internalSelection != newValue {
                internalSelection = newValue
            }
        }
    }
}

struct DocumentRow: View {
    let document: DocumentItem
    var isSelected: Bool = false
    var availableTags: [DocumentTagItem] = []
    var availableCollections: [CollectionMenuItem] = []
    var onToggleTag: ((UUID) -> Void)? = nil
    var onRename: ((String) -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onSetCollection: ((UUID?) -> Void)? = nil

    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var showDeleteConfirmation = false
    @FocusState private var isRenameFieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Thumbnail or fallback icon
            ThumbnailImageView(url: document.thumbnailURL, documentType: document.documentType)

            VStack(alignment: .leading, spacing: 2) {
                if isRenaming {
                    TextField("Document name", text: $renameText, onCommit: {
                        if !renameText.isEmpty {
                            onRename?(renameText)
                        }
                        isRenaming = false
                    })
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isRenameFieldFocused)
                } else {
                    Text(document.title)
                        .font(.system(size: 13))
                        .lineLimit(1)
                }

                HStack(spacing: 3) {
                    // Collection badge (if assigned)
                    if let collectionName = collectionName {
                        Image(systemName: "folder")
                        Text(collectionName)
                            .lineLimit(1)
                        Text("/")
                    }

                    // Page count for PDFs
                    if !document.isEPUB && document.pageCount > 0 {
                        Text("\(document.pageCount) page\(document.pageCount == 1 ? "" : "s")")
                        Text("/")
                    }

                    // File size
                    Text(formattedFileSize)

                    // Date modified
                    Text("/")
                    if let date = document.updatedAt ?? document.createdAt {
                        Text(compactDate(date))
                    }

                    Spacer()

                    // Tag badges
                    if !document.tags.isEmpty {
                        HStack(spacing: 3) {
                            ForEach(document.tags.prefix(3)) { tag in
                                TagBadge(name: tag.name, color: tag.color)
                            }
                            if document.tags.count > 3 {
                                Text("+\(document.tags.count - 3)")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .draggable(DocumentDragItem(documentID: document.id))
        .onChange(of: isRenameFieldFocused) { focused in
            if !focused && isRenaming {
                // User clicked away without pressing Enter — cancel rename
                isRenaming = false
            }
        }
        .onChange(of: isRenaming) { renaming in
            if renaming {
                // Auto-focus the text field when entering rename mode
                DispatchQueue.main.async {
                    isRenameFieldFocused = true
                }
            }
        }
        .contextMenu {
            Button("Rename") {
                renameText = document.title
                isRenaming = true
            }

            Divider()

            Menu("Tags") {
                ForEach(availableTags) { tag in
                    Button {
                        onToggleTag?(tag.id)
                    } label: {
                        HStack {
                            if document.tags.contains(where: { $0.id == tag.id }) {
                                Image(systemName: "checkmark")
                            }
                            Text(tag.name)
                        }
                    }
                }

                if availableTags.isEmpty {
                    Text("No tags available")
                        .foregroundColor(.secondary)
                }
            }

            Menu("Add to Collection") {
                Button("None") {
                    onSetCollection?(nil)
                }

                if !availableCollections.isEmpty {
                    Divider()
                }

                ForEach(availableCollections) { collection in
                    Button {
                        onSetCollection?(collection.id)
                    } label: {
                        HStack {
                            if document.collectionID == collection.id {
                                Image(systemName: "checkmark")
                            }
                            Text(collection.name)
                        }
                    }
                }
            }

            Divider()

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .alert("Delete Document?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete?()
            }
        } message: {
            Text("Are you sure you want to delete \"\(document.title)\"? This action cannot be undone.")
        }
    }

    private func compactDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        }

        let components = calendar.dateComponents([.day, .month, .year], from: date, to: Date())

        if let years = components.year, years >= 1 {
            return "\(years)y"
        } else if let months = components.month, months >= 1 {
            return "\(months)mo"
        } else if let days = components.day, days >= 1 {
            return "\(days)d"
        }

        return "Today"
    }

    private var formattedFileSize: String {
        guard let url = document.fileURL else { return "—" }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        guard let bytes = attributes?[.size] as? Int64 else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private var collectionName: String? {
        guard let collectionID = document.collectionID else { return nil }
        return availableCollections.first(where: { $0.id == collectionID })?.name
    }
}

struct TagBadge: View {
    let name: String
    let color: String?

    var body: some View {
        Text(name)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(badgeColor.opacity(0.2))
            .foregroundColor(badgeColor)
            .cornerRadius(3)
    }

    private var badgeColor: Color {
        guard let hex = color else { return .blue }
        return Color(hex: hex) ?? .blue
    }
}

struct NoteListView: View {
    let notes: [NoteItem]
    var selectedID: UUID?
    let onSelect: (UUID) -> Void

    @State private var internalSelection: UUID?

    var body: some View {
        List(notes, selection: $internalSelection) { note in
            NoteRow(note: note, isSelected: note.id == internalSelection)
                .tag(note.id)
        }
        .listStyle(.sidebar)
        .onAppear {
            internalSelection = selectedID
        }
        .onChange(of: internalSelection) { newValue in
            if let id = newValue {
                onSelect(id)
            }
        }
        .onChange(of: selectedID) { newValue in
            if internalSelection != newValue {
                internalSelection = newValue
            }
        }
    }
}

struct NoteRow: View {
    let note: NoteItem
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.system(size: 14))
                .foregroundColor(.orange)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(note.title)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Spacer()
                    if note.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 4) {
                    if let date = note.updatedAt ?? note.createdAt {
                        Text(formattedDate(date))
                    }
                    if !note.preview.isEmpty {
                        Text("—")
                        Text(note.preview)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private func formattedDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return formatter.localizedString(for: date, relativeTo: Date())
        }
    }
}

struct DocumentDetailPlaceholder: View {
    let documentID: UUID

    var body: some View {
        VStack {
            Text("PDF Viewer")
                .font(.title)
            Text("Document ID: \(documentID.uuidString)")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("PDF rendering will be implemented in Phase 2")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NoteDetailPlaceholder: View {
    let noteID: UUID

    var body: some View {
        VStack {
            Text("Markdown Editor")
                .font(.title)
            Text("Note ID: \(noteID.uuidString)")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Loading note...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

public struct DocumentItem: Identifiable, Equatable {
    public let id: UUID
    public var title: String
    public var subtitle: String?
    public var authors: [String]?
    public var pageCount: Int
    public var createdAt: Date?
    public var updatedAt: Date?
    public var fileURL: URL?
    public var thumbnailURL: URL?
    public var documentType: String
    public var tags: [DocumentTagItem]
    public var collectionID: UUID?

    public var isEPUB: Bool { documentType == "epub" }
    public var isPDF: Bool { documentType == "pdf" }

    public init(id: UUID, title: String, subtitle: String? = nil, authors: [String]? = nil, pageCount: Int = 0, createdAt: Date? = nil, updatedAt: Date? = nil, fileURL: URL? = nil, thumbnailURL: URL? = nil, documentType: String = "pdf", tags: [DocumentTagItem] = [], collectionID: UUID? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.authors = authors
        self.pageCount = pageCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.fileURL = fileURL
        self.thumbnailURL = thumbnailURL
        self.documentType = documentType
        self.tags = tags
        self.collectionID = collectionID
    }
}

public struct CollectionMenuItem: Identifiable, Equatable {
    public let id: UUID
    public var name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

public struct DocumentTagItem: Identifiable, Equatable, Hashable {
    public let id: UUID
    public var name: String
    public var color: String?

    public init(id: UUID, name: String, color: String? = nil) {
        self.id = id
        self.name = name
        self.color = color
    }
}

public struct NoteItem: Identifiable, Equatable {
    public let id: UUID
    public var title: String
    public var preview: String
    public var pinned: Bool
    public var createdAt: Date?
    public var updatedAt: Date?

    public init(id: UUID, title: String, preview: String = "", pinned: Bool = false, createdAt: Date? = nil, updatedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.preview = preview
        self.pinned = pinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Document Info Popover

public struct DocumentInfoPopover: View {
    let document: DocumentItem
    let onSave: (UUID, String, String?, [String]?) -> Void

    @State private var editedTitle: String
    @State private var editedSubtitle: String
    @State private var editedAuthors: String
    @Environment(\.dismiss) private var dismiss

    public init(document: DocumentItem, onSave: @escaping (UUID, String, String?, [String]?) -> Void) {
        self.document = document
        self.onSave = onSave
        self._editedTitle = State(initialValue: document.title)
        self._editedSubtitle = State(initialValue: document.subtitle ?? "")
        self._editedAuthors = State(initialValue: document.authors?.joined(separator: ", ") ?? "")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Document Info")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    saveAndDismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Divider()

            // Editable fields
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Title")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Document title", text: $editedTitle)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Subtitle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Subtitle (optional)", text: $editedSubtitle)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Authors")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Comma-separated authors", text: $editedAuthors)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Divider()

            // Read-only fields
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "Type", value: document.documentType.uppercased())

                if document.isPDF && document.pageCount > 0 {
                    InfoRow(label: "Pages", value: "\(document.pageCount)")
                }

                if let fileURL = document.fileURL {
                    InfoRow(label: "Filename", value: fileURL.lastPathComponent)
                }

                if let createdAt = document.createdAt {
                    InfoRow(label: "Added", value: formatDate(createdAt))
                }

                if let updatedAt = document.updatedAt {
                    InfoRow(label: "Modified", value: formatDate(updatedAt))
                }

                if !document.tags.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Text("Tags")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 70, alignment: .leading)
                        FlowLayout(spacing: 4) {
                            ForEach(document.tags) { tag in
                                TagBadge(name: tag.name, color: tag.color)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private func saveAndDismiss() {
        let authors: [String]? = editedAuthors.isEmpty ? nil : editedAuthors
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let subtitle: String? = editedSubtitle.isEmpty ? nil : editedSubtitle

        onSave(document.id, editedTitle, subtitle, authors)
        dismiss()
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.caption)
                .lineLimit(2)
            Spacer()
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalHeight = currentY + lineHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}

// MARK: - Content Search Bar

public struct ContentSearchBar: View {
    @ObservedObject var viewModel: ContentAreaViewModel

    public init(viewModel: ContentAreaViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: searchIcon)
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            TextField(placeholder, text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit {
                    // For content mode, trigger search immediately on Enter
                    if viewModel.searchMode == .content {
                        viewModel.setSearchMode(.content)
                    }
                }

            if viewModel.isSearchingContent {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                    .frame(width: 14, height: 14)
            }

            if !viewModel.searchText.isEmpty {
                Button(action: viewModel.clearSearch) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()
                .frame(height: 14)

            // Sort dropdown
            Menu {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Button {
                        viewModel.sortOption = option
                    } label: {
                        HStack {
                            Label(option.label, systemImage: option.icon)
                            if viewModel.sortOption == option {
                                Spacer()
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10))
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: sortIconForCurrentOption)
                        .font(.system(size: 11))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9))
                }
                .foregroundColor(.secondary)
            }
            #if os(macOS)
            .menuStyle(.borderlessButton)
            #endif
            .help("Sort: \(viewModel.sortOption.label)")
            .fixedSize()

            Divider()
                .frame(height: 14)

            // Advanced search dropdown
            Menu {
                Picker(selection: Binding(
                    get: { viewModel.searchMode },
                    set: { viewModel.setSearchMode($0) }
                )) {
                    Label("File Name", systemImage: "doc.text")
                        .tag(SearchMode.fileName)
                    Label("Document Content", systemImage: "doc.text.magnifyingglass")
                        .tag(SearchMode.content)
                } label: {
                    Text("Search In")
                }
            } label: {
                Text("Advanced")
                    .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.platformControlBackground)
                )
            }
            #if os(macOS)
            .menuStyle(.borderlessButton)
            #endif
            .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.platformTextBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.platformSeparator, lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var searchIcon: String {
        viewModel.searchMode == .content ? "doc.text.magnifyingglass" : "magnifyingglass"
    }

    private var placeholder: String {
        viewModel.searchMode == .content ? "Search document content…" : "Search by name…"
    }

    private var sortIconForCurrentOption: String {
        switch viewModel.sortOption {
        case .titleAscending, .titleDescending:
            return "textformat"
        case .dateNewest, .dateOldest:
            return "calendar"
        }
    }
}

// MARK: - Search Results List

public struct SearchResultsListView: View {
    let results: [SearchResultItem]
    let isSearching: Bool
    let onSelectDocument: (UUID) -> Void
    let onSelectNote: (UUID) -> Void

    public init(
        results: [SearchResultItem],
        isSearching: Bool,
        onSelectDocument: @escaping (UUID) -> Void,
        onSelectNote: @escaping (UUID) -> Void
    ) {
        self.results = results
        self.isSearching = isSearching
        self.onSelectDocument = onSelectDocument
        self.onSelectNote = onSelectNote
    }

    public var body: some View {
        if results.isEmpty && isSearching {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Searching documents…")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("No Results")
                    .font(.title3)
                    .foregroundColor(.secondary)
                Text("Try a different search term")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.8))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                if isSearching {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Searching more documents…")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                ForEach(results) { result in
                    SearchResultRow(result: result)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            switch result.kind {
                            case .document:
                                onSelectDocument(result.id)
                            case .note:
                                onSelectNote(result.id)
                            }
                        }
                }
            }
            .listStyle(.sidebar)
        }
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let result: SearchResultItem

    var body: some View {
        HStack(spacing: 8) {
            // Type icon
            Group {
                if let thumbnailURL = result.thumbnailURL,
                   let image = PlatformImage.loadFromURL(thumbnailURL) {
                    image.swiftUIImage
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 28, height: 36)
                        .cornerRadius(3)
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(iconBackgroundColor.opacity(0.1))
                        .frame(width: 28, height: 36)
                        .overlay(
                            Image(systemName: iconName)
                                .font(.system(size: 14))
                                .foregroundColor(iconColor)
                        )
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(result.title)
                        .font(.system(size: 13))
                        .lineLimit(1)

                    Spacer()

                    Text(kindLabel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.1))
                        )
                }

                if !result.snippet.isEmpty {
                    Text(result.snippet)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 3)
    }

    private var iconName: String {
        result.kind == .document ? "doc.fill" : "note.text"
    }

    private var iconColor: Color {
        result.kind == .document ? .blue : .orange
    }

    private var iconBackgroundColor: Color {
        result.kind == .document ? .blue : .orange
    }

    private var kindLabel: String {
        switch result.kind {
        case .document:
            if let page = result.pageIndex {
                return "PDF p.\(page + 1)"
            }
            // Check file extension for EPUB
            if let url = result.fileURL, url.pathExtension.lowercased() == "epub" {
                return "EPUB"
            }
            return "PDF"
        case .note:
            return "Note"
        }
    }
}

// MARK: - No Search Results State

struct NoSearchResultsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No Results")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("Try a different search term")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
