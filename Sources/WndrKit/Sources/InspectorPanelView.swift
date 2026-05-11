import SwiftUI

public struct InspectorPanelView: View {
    let inspectorMode: InspectorMode
    let linkedNotes: [NoteItem]
    let onSelectNote: (UUID) -> Void

    public init(
        inspectorMode: InspectorMode,
        linkedNotes: [NoteItem] = [],
        onSelectNote: @escaping (UUID) -> Void = { _ in }
    ) {
        self.inspectorMode = inspectorMode
        self.linkedNotes = linkedNotes
        self.onSelectNote = onSelectNote
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch inspectorMode {
                case .none:
                    Text("No Selection")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .document(let document):
                    DocumentInspectorView(
                        document: document,
                        linkedNotes: linkedNotes,
                        onSelectNote: onSelectNote
                    )
                case .note(let note):
                    NoteInspectorView(note: note)
                }
            }
            .padding()
        }
        .frame(minWidth: 260, idealWidth: 300)
        .background(Color.platformControlBackground)
    }
}

struct DocumentInspectorView: View {
    let document: DocumentItem
    let linkedNotes: [NoteItem]
    let onSelectNote: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InspectorSection(title: "Information") {
                InspectorField(label: "Title", value: document.title)
                if let authors = document.authors, !authors.isEmpty {
                    InspectorField(label: "Authors", value: authors.joined(separator: ", "))
                }
                InspectorField(label: "Pages", value: "\(document.pageCount)")
                if let createdAt = document.createdAt {
                    InspectorField(label: "Added", value: createdAt.formatted())
                }
            }

            InspectorSection(title: "Tags") {
                Text("No tags")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Button("Add Tag") {
                    // Will implement
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            InspectorSection(title: "Annotations") {
                Text("No annotations")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }

            InspectorSection(title: "Linked Notes") {
                if linkedNotes.isEmpty {
                    Text("No linked notes")
                        .foregroundColor(.secondary)
                        .font(.caption)
                } else {
                    ForEach(linkedNotes) { note in
                        LinkedNoteTile(note: note) {
                            onSelectNote(note.id)
                        }
                    }
                }
            }
        }
    }
}

struct NoteInspectorView: View {
    let note: NoteItem

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InspectorSection(title: "Information") {
                InspectorField(label: "Title", value: note.title)
                if let updatedAt = note.updatedAt {
                    InspectorField(label: "Modified", value: updatedAt.formatted())
                }
                InspectorField(label: "Pinned", value: note.pinned ? "Yes" : "No")
            }

            InspectorSection(title: "Tags") {
                Text("No tags")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Button("Add Tag") {
                    // Will implement
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            InspectorSection(title: "Backlinks") {
                Text("No backlinks")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }

            InspectorSection(title: "Linked Highlights") {
                Text("No linked highlights")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
    }
}

struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct InspectorField: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
    }
}

struct LinkedNoteTile: View {
    let note: NoteItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "note.text")
                        .foregroundColor(.orange)
                    Text(note.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Spacer()
                }

                if !note.preview.isEmpty {
                    Text(note.preview)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.platformTextBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

public enum InspectorMode: Equatable {
    case none
    case document(DocumentItem)
    case note(NoteItem)
}
