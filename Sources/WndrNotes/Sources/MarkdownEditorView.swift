import SwiftUI
import WndrKit

public struct MarkdownEditorView: View {
    @ObservedObject var viewModel: NoteEditorViewModel
    @FocusState private var isEditorFocused: Bool

    public init(viewModel: NoteEditorViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Title bar
            editorTitleBar

            Divider()

            // Centered formatting toolbar
            formattingToolbar

            Divider()

            // Main content
            if viewModel.showPreview {
                splitView
            } else {
                editorOnly
            }

            Divider()

            // Status bar
            statusBar
        }
        .background(Color.platformTextBackground)
    }

    // MARK: - Title Bar

    private var editorTitleBar: some View {
        HStack(spacing: 12) {
            TextField("Note Title", text: $viewModel.title)
                .textFieldStyle(.plain)
                .font(.title2.bold())

            Spacer()

            Button(action: viewModel.togglePreview) {
                Image(systemName: viewModel.showPreview ? "eye.slash" : "eye")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)

            if viewModel.isDirty {
                Button(action: { Task { await viewModel.save() } }) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("s", modifiers: .command)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.platformControlBackground)
    }

    // MARK: - Formatting Toolbar

    private var formattingToolbar: some View {
        HStack(spacing: 4) {
            Spacer()

            FormatIconButton(text: "H1", helpText: "Heading 1") {
                viewModel.insertTemplate("\n# ")
            }

            FormatIconButton(text: "H2", helpText: "Heading 2") {
                viewModel.insertTemplate("\n## ")
            }

            toolbarDivider

            FormatIconButton(systemImage: "list.bullet", helpText: "Bullet List") {
                viewModel.insertTemplate("\n- ")
            }

            FormatIconButton(systemImage: "list.number", helpText: "Numbered List") {
                viewModel.insertTemplate("\n1. ")
            }

            toolbarDivider

            FormatIconButton(systemImage: "curlybraces", helpText: "Code Block") {
                viewModel.insertTemplate("\n```\n\n```\n")
            }

            FormatIconButton(systemImage: "text.quote", helpText: "Quote") {
                viewModel.insertTemplate("\n> ")
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .background(Color.platformControlBackground.opacity(0.5))
    }

    private var toolbarDivider: some View {
        RoundedRectangle(cornerRadius: 0.5)
            .fill(Color.secondary.opacity(0.25))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 4)
    }

    private var editorOnly: some View {
        ScrollView {
            TextEditor(text: $viewModel.body)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(16)
                .focused($isEditorFocused)
        }
        .onAppear { isEditorFocused = true }
    }

    private var splitView: some View {
        #if os(macOS)
        HSplitView {
            editorPane
            previewPane
        }
        #else
        // iPadOS: Use HStack with equal split instead of HSplitView
        GeometryReader { geometry in
            HStack(spacing: 0) {
                editorPane
                    .frame(width: geometry.size.width / 2)
                Divider()
                previewPane
                    .frame(width: geometry.size.width / 2)
            }
        }
        #endif
    }

    private var editorPane: some View {
        ScrollView {
            TextEditor(text: $viewModel.body)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(16)
                .focused($isEditorFocused)
        }
    }

    private var previewPane: some View {
        ScrollView {
            MarkdownPreviewView(markdown: viewModel.body)
                .padding(16)
        }
        .background(Color.platformTextBackground)
    }

    private var statusBar: some View {
        HStack(spacing: 16) {
            Text("\(viewModel.wordCount) words")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("\(viewModel.characterCount) characters")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            if viewModel.isSaving {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Saving...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if let lastSaved = viewModel.lastSaved {
                Text("Saved \(lastSaved, style: .relative)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if viewModel.isDirty {
                Text("Unsaved changes")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.platformControlBackground)
    }
}

// MARK: - Format Icon Button

private struct FormatIconButton: View {
    var text: String? = nil
    var systemImage: String? = nil
    let helpText: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .medium))
                } else if let text = text {
                    Text(text)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
            }
            .foregroundColor(isHovering ? .primary : .secondary)
            .frame(width: 36, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovering ? Color.secondary.opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .help(helpText)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        #endif
    }
}

// MARK: - Markdown Preview

struct MarkdownPreviewView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let attributed = try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                Text(attributed)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(markdown)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

#Preview {
    MarkdownEditorView(viewModel: NoteEditorViewModel(
        noteID: UUID(),
        title: "Sample Note",
        body: "# Hello World\n\nThis is a **sample** note with some _markdown_ formatting.\n\n- Item 1\n- Item 2\n- Item 3"
    ))
    .frame(width: 800, height: 600)
}
