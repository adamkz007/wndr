import SwiftUI

public struct InspectorPanelView: View {
    @ObservedObject var viewModel: InspectorPanelViewModel

    public init(viewModel: InspectorPanelViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch viewModel.inspectorMode {
                case .none:
                    Text("No Selection")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .document(let document):
                    DocumentInspectorView(document: document)
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
                Text("No linked notes")
                    .foregroundColor(.secondary)
                    .font(.caption)
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

public enum InspectorMode: Equatable {
    case none
    case document(DocumentItem)
    case note(NoteItem)
}
