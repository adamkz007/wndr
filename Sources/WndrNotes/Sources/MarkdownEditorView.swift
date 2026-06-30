import AppKit
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
        .onDisappear {
            viewModel.clearLinkSuggestions()
        }
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
        editorView
        .onAppear { isEditorFocused = true }
    }

    private var splitView: some View {
        HSplitView {
            editorPane
            previewPane
        }
    }

    private var editorPane: some View {
        editorView
    }

    private var previewPane: some View {
        ScrollView {
            MarkdownPreviewView(markdown: viewModel.body)
                .padding(16)
        }
        .background(Color.platformTextBackground)
    }

    private var editorView: some View {
        ZStack(alignment: .topLeading) {
            editorTextView

            if viewModel.isShowingLinkSuggestions {
                linkSuggestionDropdown
                    .padding(.top, 12)
                    .padding(.leading, 24)
            }
        }
        .background(Color.platformTextBackground)
    }

    @ViewBuilder
    private var editorTextView: some View {
        MarkdownTextView(
            text: $viewModel.body,
            pendingCursorLocation: $viewModel.pendingCursorLocation
        ) { cursorLocation in
            viewModel.updateLinkSuggestions(cursorLocation: cursorLocation)
        }
        .padding(12)
    }

    private var linkSuggestionDropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(viewModel.activeLinkQuery.isEmpty ? "Link Document" : "Link \"\(viewModel.activeLinkQuery)\"")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            ForEach(viewModel.linkSuggestions) { suggestion in
                Button {
                    viewModel.applyLinkSuggestion(suggestion)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text")
                            .foregroundColor(.blue)
                            .frame(width: 16)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title)
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            if let subtitle = suggestion.subtitle, !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.platformControlBackground)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
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

private struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var pendingCursorLocation: Int?
    let onSelectionChange: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        textView.delegate = context.coordinator
        textView.string = text
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.allowsUndo = true
        textView.importsGraphics = false
        textView.allowsImageEditing = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.autoresizingMask = [.width]
        textView.setSelectedRange(NSRange(location: text.utf16.count, length: 0))

        context.coordinator.textView = textView

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        if textView.string != text {
            textView.string = text
        }

        if let pendingCursorLocation {
            let clampedLocation = min(max(0, pendingCursorLocation), textView.string.utf16.count)
            textView.setSelectedRange(NSRange(location: clampedLocation, length: 0))
            textView.scrollRangeToVisible(NSRange(location: clampedLocation, length: 0))
            textView.window?.makeFirstResponder(textView)

            DispatchQueue.main.async {
                self.pendingCursorLocation = nil
                self.onSelectionChange(clampedLocation)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextView
        weak var textView: NSTextView?

        init(parent: MarkdownTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            let newText = textView.string
            if parent.text != newText {
                parent.text = newText
            }
            parent.onSelectionChange(textView.selectedRange().location)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            parent.onSelectionChange(textView.selectedRange().location)
        }
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
        .help(helpText)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
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

#if DEBUG
#Preview {
    MarkdownEditorView(viewModel: NoteEditorViewModel(
        noteID: UUID(),
        title: "Sample Note",
        body: "# Hello World\n\nThis is a **sample** note with some _markdown_ formatting.\n\n- Item 1\n- Item 2\n- Item 3"
    ))
    .frame(width: 800, height: 600)
}
#endif
