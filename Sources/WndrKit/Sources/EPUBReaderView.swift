import SwiftUI
import WebKit

// MARK: - EPUB Reader View

public struct EPUBReaderView: View {
    @ObservedObject public var viewModel: EPUBReaderViewModel

    // Selection state for highlight creation
    @State private var pendingSelectionText: String = ""
    @State private var pendingStartOffset: Int = 0
    @State private var pendingEndOffset: Int = 0
    @State private var hasSelection: Bool = false
    @State private var webViewRefreshID: UUID = UUID()

    public init(viewModel: EPUBReaderViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top toolbar
            readerToolbar

            Divider()

            // Main content
            ZStack {
                if viewModel.isLoading {
                    loadingView
                } else if let error = viewModel.errorMessage {
                    errorView(error)
                } else {
                    readerContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bottom navigation bar
            bottomNavigationBar
        }
    }

    // MARK: - Toolbar

    private var readerToolbar: some View {
        HStack(spacing: 12) {
            // Chapter list button
            Button {
                viewModel.showChapterList.toggle()
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .help("Table of Contents")
            .popover(isPresented: $viewModel.showChapterList, arrowEdge: .bottom) {
                chapterListPopover
            }

            Divider()
                .frame(height: 16)

            // Chapter title
            Text(viewModel.currentChapterTitle)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            Spacer()

            // Highlight color picker (shown when text is selected)
            if hasSelection {
                highlightControls
            }

            Divider()
                .frame(height: 16)

            // Settings button
            Button {
                viewModel.showSettings.toggle()
            } label: {
                Image(systemName: "textformat.size")
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .help("Reader Settings")
            .popover(isPresented: $viewModel.showSettings, arrowEdge: .bottom) {
                readerSettingsPanel
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.platformControlBackground)
    }

    // MARK: - Highlight Controls

    private var highlightControls: some View {
        HStack(spacing: 6) {
            ForEach(highlightColors, id: \.id) { preset in
                Button {
                    viewModel.selectedHighlightColor = preset.id
                    createHighlight()
                } label: {
                    Circle()
                        .fill(preset.color)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle()
                                .stroke(
                                    viewModel.selectedHighlightColor == preset.id
                                        ? Color.primary : Color.clear,
                                    lineWidth: 2
                                )
                        )
                }
                .buttonStyle(.plain)
                .help(preset.name)
            }

            Button("Highlight") {
                createHighlight()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private var highlightColors: [(id: String, name: String, color: Color)] {
        [
            ("yellow", "Yellow", Color.yellow),
            ("green", "Green", Color.green),
            ("blue", "Blue", Color.blue),
            ("pink", "Pink", Color.pink),
            ("orange", "Orange", Color.orange),
            ("purple", "Purple", Color.purple),
        ]
    }

    private func createHighlight() {
        guard !pendingSelectionText.isEmpty else { return }
        viewModel.addHighlight(
            startOffset: pendingStartOffset,
            endOffset: pendingEndOffset,
            text: pendingSelectionText
        )
        // Trigger web view to apply the highlight visually
        webViewRefreshID = UUID()
        hasSelection = false
        pendingSelectionText = ""
    }

    // MARK: - Reader Content

    private var readerContent: some View {
        EPUBWebView(
            viewModel: viewModel,
            onTextSelected: { text, start, end in
                pendingSelectionText = text
                pendingStartOffset = start
                pendingEndOffset = end
                hasSelection = true
            },
            onSelectionCleared: {
                hasSelection = false
                pendingSelectionText = ""
            },
            refreshID: webViewRefreshID
        )
    }

    // MARK: - Bottom Navigation

    private var bottomNavigationBar: some View {
        HStack {
            Button {
                viewModel.goToPreviousChapter()
            } label: {
                Label("Previous", systemImage: "chevron.left")
                    .font(.system(size: 12))
            }
            .disabled(!viewModel.canGoToPreviousChapter)
            .buttonStyle(.plain)
            .foregroundColor(viewModel.canGoToPreviousChapter ? .accentColor : .secondary)

            Spacer()

            if viewModel.chapterCount > 0 {
                Text("\(viewModel.currentChapterIndex + 1) of \(viewModel.chapterCount)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                viewModel.goToNextChapter()
            } label: {
                Label("Next", systemImage: "chevron.right")
                    .font(.system(size: 12))
                    .labelStyle(TrailingIconLabelStyle())
            }
            .disabled(!viewModel.canGoToNextChapter)
            .buttonStyle(.plain)
            .foregroundColor(viewModel.canGoToNextChapter ? .accentColor : .secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.platformControlBackground)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    // MARK: - Chapter List Popover

    private var chapterListPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Table of Contents")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<viewModel.chapterTitles.count, id: \.self) { index in
                        Button {
                            viewModel.goToChapter(index)
                        } label: {
                            HStack {
                                Text(viewModel.chapterTitles[index])
                                    .font(.system(size: 13))
                                    .foregroundColor(
                                        index == viewModel.currentChapterIndex ? .accentColor : .primary
                                    )
                                    .lineLimit(2)
                                Spacer()
                                if index == viewModel.currentChapterIndex {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if index < viewModel.chapterTitles.count - 1 {
                            Divider()
                                .padding(.leading, 16)
                        }
                    }
                }
            }
            .frame(maxHeight: 400)
        }
        .frame(width: 300)
    }

    // MARK: - Reader Settings Panel

    private var readerSettingsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reader Settings")
                .font(.headline)

            // Font Size
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Font Size")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(viewModel.settings.fontSize))pt")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                }
                HStack(spacing: 8) {
                    Text("A")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Slider(
                        value: $viewModel.settings.fontSize,
                        in: EPUBReaderSettings.fontSizeRange,
                        step: 1
                    )
                    Text("A")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Font Family
            VStack(alignment: .leading, spacing: 6) {
                Text("Font")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Picker("Font", selection: $viewModel.settings.fontFamily) {
                    ForEach(EPUBFontFamily.allCases) { family in
                        Text(family.rawValue).tag(family)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Divider()

            // Margins
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Margins")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(viewModel.settings.horizontalMargin))px")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                }
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left.and.right.square")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Slider(
                        value: $viewModel.settings.horizontalMargin,
                        in: EPUBReaderSettings.marginRange,
                        step: 4
                    )
                    Image(systemName: "arrow.left.and.right.square.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    // MARK: - Loading / Error States

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Loading EPUB…")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            Text("Failed to Load EPUB")
                .font(.title2)
            Text(message)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

// MARK: - Trailing Icon Label Style

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}

// MARK: - WKWebView Wrapper

struct EPUBWebView {
    let viewModel: EPUBReaderViewModel
    let onTextSelected: (String, Int, Int) -> Void
    let onSelectionCleared: () -> Void
    let refreshID: UUID
}

#if canImport(AppKit)
extension EPUBWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = config.userContentController

        // Register message handlers
        contentController.add(context.coordinator, name: "textSelected")
        contentController.add(context.coordinator, name: "selectionCleared")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.viewModel = viewModel
        context.coordinator.onTextSelected = onTextSelected
        context.coordinator.onSelectionCleared = onSelectionCleared
        context.coordinator.loadCurrentChapter(in: webView)
    }

    func makeCoordinator() -> EPUBWebViewCoordinator {
        EPUBWebViewCoordinator(
            viewModel: viewModel,
            onTextSelected: onTextSelected,
            onSelectionCleared: onSelectionCleared
        )
    }
}
#else
extension EPUBWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = config.userContentController

        contentController.add(context.coordinator, name: "textSelected")
        contentController.add(context.coordinator, name: "selectionCleared")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.viewModel = viewModel
        context.coordinator.onTextSelected = onTextSelected
        context.coordinator.onSelectionCleared = onSelectionCleared
        context.coordinator.loadCurrentChapter(in: webView)
    }

    func makeCoordinator() -> EPUBWebViewCoordinator {
        EPUBWebViewCoordinator(
            viewModel: viewModel,
            onTextSelected: onTextSelected,
            onSelectionCleared: onSelectionCleared
        )
    }
}
#endif

// MARK: - WKWebView Coordinator

class EPUBWebViewCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var viewModel: EPUBReaderViewModel
    var onTextSelected: (String, Int, Int) -> Void
    var onSelectionCleared: () -> Void
    weak var webView: WKWebView?

    private var currentLoadedChapter: Int = -1
    private var currentSettingsHash: Int = 0

    init(
        viewModel: EPUBReaderViewModel,
        onTextSelected: @escaping (String, Int, Int) -> Void,
        onSelectionCleared: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onTextSelected = onTextSelected
        self.onSelectionCleared = onSelectionCleared
    }

    func loadCurrentChapter(in webView: WKWebView) {
        let settingsHash = viewModel.settings.hashValue

        // Only reload if chapter or settings changed
        guard let chapterURL = viewModel.currentChapterURL else { return }

        if currentLoadedChapter == viewModel.currentChapterIndex
            && currentSettingsHash == settingsHash {
            // Just re-apply highlights if needed
            applyHighlights(in: webView)
            return
        }

        currentLoadedChapter = viewModel.currentChapterIndex
        currentSettingsHash = settingsHash

        // Load chapter HTML with injected CSS
        let baseURL = chapterURL.deletingLastPathComponent()
        webView.loadFileURL(chapterURL, allowingReadAccessTo: baseURL)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Inject custom CSS
        let css = viewModel.readerCSS.replacingOccurrences(of: "\n", with: "\\n")
        let injectCSS = """
            (function() {
                var existingStyle = document.getElementById('wndr-reader-style');
                if (existingStyle) existingStyle.remove();
                var style = document.createElement('style');
                style.id = 'wndr-reader-style';
                style.textContent = "\(css)";
                document.head.appendChild(style);
            })();
            """
        webView.evaluateJavaScript(injectCSS)

        // Inject highlight JavaScript
        webView.evaluateJavaScript(viewModel.highlightJS)

        // Apply existing highlights
        applyHighlights(in: webView)

        // Mark loading as complete
        Task { @MainActor in
            viewModel.isLoading = false
        }
    }

    private func applyHighlights(in webView: WKWebView) {
        let highlights = viewModel.currentChapterHighlights
        for highlight in highlights {
            let js = "window.applyHighlight(\(highlight.startOffset), \(highlight.endOffset), '\(highlight.colorCategory)', '\(highlight.id.uuidString)');"
            webView.evaluateJavaScript(js)
        }
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        switch message.name {
        case "textSelected":
            guard let body = message.body as? [String: Any],
                  let text = body["text"] as? String,
                  let startOffset = body["startOffset"] as? Int,
                  let endOffset = body["endOffset"] as? Int else { return }
            Task { @MainActor in
                onTextSelected(text, startOffset, endOffset)
            }

        case "selectionCleared":
            Task { @MainActor in
                onSelectionCleared()
            }

        default:
            break
        }
    }
}

// Make EPUBReaderSettings Hashable for change detection
extension EPUBReaderSettings: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(fontSize)
        hasher.combine(fontFamily)
        hasher.combine(horizontalMargin)
    }
}
