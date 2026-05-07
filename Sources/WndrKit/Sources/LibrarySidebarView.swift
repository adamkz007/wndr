import SwiftUI
import UniformTypeIdentifiers

public struct LibrarySidebarView: View {
    @ObservedObject var viewModel: LibrarySidebarViewModel
    var statusMessage: String?
    var onRenameTag: ((UUID, String) -> Void)?
    var onRenameCollection: ((UUID, String) -> Void)?
    var onDeleteTag: ((UUID) -> Void)?
    var onDeleteCollection: ((UUID) -> Void)?
    var onDropDocumentOnCollection: ((UUID, UUID) -> Void)?
    @State private var editingTagID: UUID?
    @State private var editingTagName: String = ""
    @State private var editingCollectionID: UUID?
    @State private var editingCollectionName: String = ""
    @State private var deletingCollectionID: UUID?
    @State private var deletingTagID: UUID?
    @State private var showDeleteCollectionConfirmation = false
    @State private var showDeleteTagConfirmation = false
    @State private var dropTargetedCollectionID: UUID?

    public init(
        viewModel: LibrarySidebarViewModel,
        statusMessage: String? = nil,
        onRenameTag: ((UUID, String) -> Void)? = nil,
        onRenameCollection: ((UUID, String) -> Void)? = nil,
        onDeleteTag: ((UUID) -> Void)? = nil,
        onDeleteCollection: ((UUID) -> Void)? = nil,
        onDropDocumentOnCollection: ((UUID, UUID) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.statusMessage = statusMessage
        self.onRenameTag = onRenameTag
        self.onRenameCollection = onRenameCollection
        self.onDeleteTag = onDeleteTag
        self.onDeleteCollection = onDeleteCollection
        self.onDropDocumentOnCollection = onDropDocumentOnCollection
    }

    public var body: some View {
        VStack(spacing: 0) {
            List(selection: $viewModel.selectedItem) {
            Section("Library") {
                SidebarItem(
                    title: "All Documents",
                    icon: "doc.richtext",
                    count: viewModel.documentCount,
                    id: .allDocuments
                )
                SidebarItem(
                    title: "Unsorted",
                    icon: "tray",
                    count: viewModel.unsortedDocumentCount,
                    id: .unsortedDocuments
                )
                .padding(.leading, 16) // Indent to show it's a sub-item
                SidebarItem(
                    title: "Notes",
                    icon: "note.text",
                    count: viewModel.noteCount,
                    id: .allNotes
                )
            }

            Section("Collections") {
                ForEach(viewModel.collections) { collection in
                    if editingCollectionID == collection.id {
                        HStack {
                            Image(systemName: collection.icon ?? "folder")
                            TextField("Collection name", text: $editingCollectionName, onCommit: {
                                if !editingCollectionName.isEmpty {
                                    onRenameCollection?(collection.id, editingCollectionName)
                                }
                                editingCollectionID = nil
                            })
                            .textFieldStyle(.plain)
                        }
                        .tag(SidebarSelection.collection(collection.id))
                    } else {
                        SidebarItem(
                            title: collection.name,
                            icon: collection.icon ?? "folder",
                            count: collection.documentCount,
                            id: .collection(collection.id)
                        )
                        .contextMenu {
                            Button("Rename") {
                                editingCollectionName = collection.name
                                editingCollectionID = collection.id
                            }

                            Divider()

                            Button(role: .destructive) {
                                deletingCollectionID = collection.id
                                showDeleteCollectionConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .onDrop(of: [.utf8PlainText], isTargeted: Binding(
                            get: { dropTargetedCollectionID == collection.id },
                            set: { dropTargetedCollectionID = $0 ? collection.id : nil }
                        )) { providers in
                            handleDocumentDrop(providers: providers, collectionID: collection.id)
                        }
                        .listRowBackground(
                            dropTargetedCollectionID == collection.id
                                ? Color.accentColor.opacity(0.18)
                                : Color.clear
                        )
                    }
                }
                Button(action: viewModel.createCollection) {
                    Label("New Collection", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }

            Section("Tags") {
                ForEach(viewModel.tags) { tag in
                    if editingTagID == tag.id {
                        HStack {
                            Image(systemName: "tag.fill")
                                .foregroundColor(tag.color.flatMap { Color(hex: $0) })
                            TextField("Tag name", text: $editingTagName, onCommit: {
                                if !editingTagName.isEmpty {
                                    onRenameTag?(tag.id, editingTagName)
                                }
                                editingTagID = nil
                            })
                            .textFieldStyle(.plain)
                        }
                        .tag(SidebarSelection.tag(tag.id))
                    } else {
                        SidebarItem(
                            title: tag.name,
                            icon: "tag.fill",
                            color: tag.color,
                            count: tag.itemCount,
                            id: .tag(tag.id)
                        )
                        .contextMenu {
                            Button("Rename") {
                                editingTagName = tag.name
                                editingTagID = tag.id
                            }

                            Divider()

                            Button(role: .destructive) {
                                deletingTagID = tag.id
                                showDeleteTagConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                Button(action: viewModel.createTag) {
                    Label("New Tag", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }

            }
            .listStyle(.sidebar)
            .onChange(of: viewModel.pendingEditCollectionID) { _, newValue in
                if let id = newValue,
                   let collection = viewModel.collections.first(where: { $0.id == id }) {
                    editingCollectionName = collection.name
                    editingCollectionID = id
                    viewModel.pendingEditCollectionID = nil
                }
            }
            .onChange(of: viewModel.pendingEditTagID) { _, newValue in
                if let id = newValue,
                   let tag = viewModel.tags.first(where: { $0.id == id }) {
                    editingTagName = tag.name
                    editingTagID = id
                    viewModel.pendingEditTagID = nil
                }
            }
            .alert("Delete Collection?", isPresented: $showDeleteCollectionConfirmation) {
                Button("Cancel", role: .cancel) {
                    deletingCollectionID = nil
                }
                Button("Delete", role: .destructive) {
                    if let id = deletingCollectionID {
                        onDeleteCollection?(id)
                    }
                    deletingCollectionID = nil
                }
            } message: {
                Text("This will remove the collection. Documents in this collection will not be deleted.")
            }
            .alert("Delete Tag?", isPresented: $showDeleteTagConfirmation) {
                Button("Cancel", role: .cancel) {
                    deletingTagID = nil
                }
                Button("Delete", role: .destructive) {
                    if let id = deletingTagID {
                        onDeleteTag?(id)
                    }
                    deletingTagID = nil
                }
            } message: {
                Text("This will remove the tag from all documents and notes.")
            }

            // Status message at bottom
            if let message = statusMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 12))
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.platformControlBackground)
            }

            // App info at the very bottom
            Divider()
                .opacity(0.5)

            SidebarFooterView()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .padding(.bottom, 4)
        }
    }

    private func handleDocumentDrop(providers: [NSItemProvider], collectionID: UUID) -> Bool {
        var handled = false
        for provider in providers {
            if provider.canLoadObject(ofClass: NSString.self) {
                handled = true
                provider.loadObject(ofClass: NSString.self) { item, _ in
                    if let uuidString = item as? String,
                       let documentID = UUID(uuidString: uuidString) {
                        DispatchQueue.main.async {
                            onDropDocumentOnCollection?(documentID, collectionID)
                        }
                    }
                }
            }
        }
        return handled
    }
}

struct SidebarItem: View {
    let title: String
    let icon: String
    var color: String?
    var count: Int?
    let id: SidebarSelection

    var body: some View {
        HStack {
            if icon == "tag.fill" && colorValue != nil {
                // Special styling for colored tags
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .foregroundColor(colorValue)
                        .font(.system(size: 14))
                    Text(title)
                }
            } else {
                Label(title, systemImage: icon)
                    .foregroundColor(colorValue)
            }
            Spacer()
            if let count = count {
                Text("\(count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
        .tag(id)
    }

    private var colorValue: Color? {
        guard let color = color else { return nil }
        return Color(hex: color)
    }
}

public enum SidebarSelection: Hashable {
    case allDocuments
    case unsortedDocuments
    case allNotes
    case collection(UUID)
    case tag(UUID)
}

public struct CollectionItem: Identifiable {
    public let id: UUID
    public var name: String
    public var icon: String?
    public var documentCount: Int

    public init(id: UUID, name: String, icon: String? = nil, documentCount: Int = 0) {
        self.id = id
        self.name = name
        self.icon = icon
        self.documentCount = documentCount
    }
}

public struct TagItem: Identifiable {
    public let id: UUID
    public var name: String
    public var color: String?
    public var itemCount: Int

    public init(id: UUID, name: String, color: String? = nil, itemCount: Int = 0) {
        self.id = id
        self.name = name
        self.color = color
        self.itemCount = itemCount
    }
}

// MARK: - Sidebar Footer

private struct SidebarFooterView: View {
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
                Text("Wndr")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Text("v\(appVersion)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.6))
            }

            VStack(alignment: .leading, spacing: 3) {
                Button(action: openReleaseNotes) {
                    Text("Release Notes")
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor.opacity(0.7))
                        .underline(color: .clear)
                }
                .buttonStyle(.plain)
                #if canImport(AppKit)
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                #endif

                Text("by @adamkz")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .opacity(0.4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openReleaseNotes() {
        // TODO: Add actual release notes URL
        #if canImport(AppKit)
        if let url = URL(string: "https://github.com/adamkz007/wndr/releases") {
            NSWorkspace.shared.open(url)
        }
        #elseif canImport(UIKit)
        if let url = URL(string: "https://github.com/adamkz007/wndr/releases") {
            UIApplication.shared.open(url)
        }
        #endif
    }
}

public extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
