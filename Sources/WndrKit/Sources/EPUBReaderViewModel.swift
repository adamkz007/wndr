import Combine
import Foundation

// MARK: - EPUB Reader Settings

public struct EPUBReaderSettings: Equatable {
    public var fontSize: CGFloat
    public var fontFamily: EPUBFontFamily
    public var horizontalMargin: CGFloat

    public init(
        fontSize: CGFloat = 18,
        fontFamily: EPUBFontFamily = .system,
        horizontalMargin: CGFloat = 40
    ) {
        self.fontSize = fontSize
        self.fontFamily = fontFamily
        self.horizontalMargin = horizontalMargin
    }

    public static let fontSizeRange: ClosedRange<CGFloat> = 12...32
    public static let marginRange: ClosedRange<CGFloat> = 16...100
}

public enum EPUBFontFamily: String, CaseIterable, Identifiable {
    case system = "System"
    case serif = "Serif"
    case sansSerif = "Sans Serif"
    case monospace = "Monospace"

    public var id: String { rawValue }

    public var cssValue: String {
        switch self {
        case .system: return "-apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif"
        case .serif: return "Georgia, 'Times New Roman', serif"
        case .sansSerif: return "'Helvetica Neue', Helvetica, Arial, sans-serif"
        case .monospace: return "'SF Mono', Menlo, Courier, monospace"
        }
    }
}

// MARK: - EPUB Highlight Data

public struct EPUBHighlightData: Identifiable, Equatable {
    public let id: UUID
    public let chapterIndex: Int
    public let chapterHref: String
    public let startOffset: Int
    public let endOffset: Int
    public let selectedText: String
    public let colorCategory: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        chapterIndex: Int,
        chapterHref: String,
        startOffset: Int,
        endOffset: Int,
        selectedText: String,
        colorCategory: String = "yellow",
        createdAt: Date = Date()
    ) {
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

// MARK: - EPUB Reader View Model

@MainActor
public final class EPUBReaderViewModel: ObservableObject {
    // Document identity
    public let documentID: UUID
    public let documentURL: URL
    public let title: String

    // Chapter navigation
    @Published public var currentChapterIndex: Int = 0
    @Published public var chapterTitles: [String] = []
    @Published public var chapterCount: Int = 0

    // Reader settings
    @Published public var settings: EPUBReaderSettings = EPUBReaderSettings()
    @Published public var showSettings: Bool = false
    @Published public var showChapterList: Bool = false

    // Highlight state
    @Published public var highlights: [EPUBHighlightData] = []
    @Published public var selectedHighlightColor: String = "yellow"
    @Published public var showHighlightToolbar: Bool = false

    // Content state
    @Published public var isLoading: Bool = true
    @Published public var errorMessage: String?

    // Chapter HTML content cache
    public var chapterHTMLPaths: [URL] = []
    public var extractedBookURL: URL?
    public var opfDirectory: String = ""

    // Callbacks for annotation persistence
    public var onCreateHighlight: ((Int, String, Int, Int, String, String) async -> Void)?
    public var onDeleteHighlight: ((UUID) async -> Void)?
    public var onDeleteAllHighlights: (() async -> Void)?

    public init(documentID: UUID, documentURL: URL, title: String) {
        self.documentID = documentID
        self.documentURL = documentURL
        self.title = title
    }

    // MARK: - Chapter Navigation

    public var currentChapterTitle: String {
        guard currentChapterIndex < chapterTitles.count else { return title }
        return chapterTitles[currentChapterIndex]
    }

    public var canGoToPreviousChapter: Bool {
        currentChapterIndex > 0
    }

    public var canGoToNextChapter: Bool {
        currentChapterIndex < chapterCount - 1
    }

    public func goToPreviousChapter() {
        guard canGoToPreviousChapter else { return }
        currentChapterIndex -= 1
    }

    public func goToNextChapter() {
        guard canGoToNextChapter else { return }
        currentChapterIndex += 1
    }

    public func goToChapter(_ index: Int) {
        guard index >= 0, index < chapterCount else { return }
        currentChapterIndex = index
        showChapterList = false
    }

    // MARK: - Current Chapter URL

    public var currentChapterURL: URL? {
        guard currentChapterIndex < chapterHTMLPaths.count else { return nil }
        return chapterHTMLPaths[currentChapterIndex]
    }

    // MARK: - Highlights for Current Chapter

    public var currentChapterHighlights: [EPUBHighlightData] {
        highlights.filter { $0.chapterIndex == currentChapterIndex }
    }

    // MARK: - CSS Generation

    public var readerCSS: String {
        """
        body {
            font-family: \(settings.fontFamily.cssValue);
            font-size: \(Int(settings.fontSize))px;
            line-height: 1.6;
            margin: 20px \(Int(settings.horizontalMargin))px;
            padding: 0;
            color: #1a1a1a;
            -webkit-text-size-adjust: 100%;
            word-wrap: break-word;
            overflow-wrap: break-word;
        }
        @media (prefers-color-scheme: dark) {
            body {
                color: #e0e0e0;
                background-color: #1c1c1e;
            }
            a { color: #5ac8fa; }
            img { opacity: 0.85; }
        }
        img {
            max-width: 100%;
            height: auto;
        }
        h1, h2, h3, h4, h5, h6 {
            line-height: 1.3;
            margin-top: 1.5em;
            margin-bottom: 0.5em;
        }
        p {
            margin-bottom: 0.8em;
        }
        mark.wndr-highlight {
            padding: 2px 0;
            border-radius: 2px;
        }
        mark.wndr-highlight.yellow { background-color: rgba(255, 235, 59, 0.4); }
        mark.wndr-highlight.green { background-color: rgba(76, 175, 80, 0.4); }
        mark.wndr-highlight.blue { background-color: rgba(33, 150, 243, 0.4); }
        mark.wndr-highlight.pink { background-color: rgba(233, 30, 99, 0.4); }
        mark.wndr-highlight.orange { background-color: rgba(255, 152, 0, 0.4); }
        mark.wndr-highlight.purple { background-color: rgba(156, 39, 176, 0.4); }
        @media (prefers-color-scheme: dark) {
            mark.wndr-highlight.yellow { background-color: rgba(255, 235, 59, 0.3); }
            mark.wndr-highlight.green { background-color: rgba(76, 175, 80, 0.3); }
            mark.wndr-highlight.blue { background-color: rgba(33, 150, 243, 0.3); }
            mark.wndr-highlight.pink { background-color: rgba(233, 30, 99, 0.3); }
            mark.wndr-highlight.orange { background-color: rgba(255, 152, 0, 0.3); }
            mark.wndr-highlight.purple { background-color: rgba(156, 39, 176, 0.3); }
        }
        """
    }

    // MARK: - Highlight JavaScript

    /// JavaScript to inject into the page for text selection handling.
    public var highlightJS: String {
        """
        (function() {
            // Send selection info to Swift when user lifts finger/mouse
            document.addEventListener('mouseup', handleSelection);
            document.addEventListener('touchend', handleSelection);

            function handleSelection() {
                var selection = window.getSelection();
                if (!selection || selection.isCollapsed || selection.toString().trim().length === 0) {
                    window.webkit.messageHandlers.selectionCleared.postMessage({});
                    return;
                }
                var text = selection.toString().trim();
                var range = selection.getRangeAt(0);

                // Calculate text offsets within the body
                var bodyRange = document.createRange();
                bodyRange.selectNodeContents(document.body);
                bodyRange.setEnd(range.startContainer, range.startOffset);
                var startOffset = bodyRange.toString().length;
                var endOffset = startOffset + text.length;

                window.webkit.messageHandlers.textSelected.postMessage({
                    text: text,
                    startOffset: startOffset,
                    endOffset: endOffset
                });
            }

            // Function to apply a highlight
            window.applyHighlight = function(startOffset, endOffset, color, highlightId) {
                var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null, false);
                var currentOffset = 0;
                var startNode = null, startOff = 0, endNode = null, endOff = 0;

                while (walker.nextNode()) {
                    var node = walker.currentNode;
                    var nodeLen = node.textContent.length;

                    if (!startNode && currentOffset + nodeLen > startOffset) {
                        startNode = node;
                        startOff = startOffset - currentOffset;
                    }
                    if (!endNode && currentOffset + nodeLen >= endOffset) {
                        endNode = node;
                        endOff = endOffset - currentOffset;
                        break;
                    }
                    currentOffset += nodeLen;
                }

                if (startNode && endNode) {
                    try {
                        var range = document.createRange();
                        range.setStart(startNode, startOff);
                        range.setEnd(endNode, endOff);

                        var mark = document.createElement('mark');
                        mark.className = 'wndr-highlight ' + color;
                        mark.dataset.highlightId = highlightId;
                        range.surroundContents(mark);
                    } catch(e) {
                        // surroundContents can fail if range crosses element boundaries
                        // Fall back to text-based matching
                        console.log('Highlight fallback for: ' + highlightId);
                    }
                }
            };

            // Function to remove a highlight
            window.removeHighlight = function(highlightId) {
                var marks = document.querySelectorAll('mark[data-highlight-id="' + highlightId + '"]');
                marks.forEach(function(mark) {
                    var parent = mark.parentNode;
                    while (mark.firstChild) {
                        parent.insertBefore(mark.firstChild, mark);
                    }
                    parent.removeChild(mark);
                    parent.normalize();
                });
            };

            // Function to clear selection
            window.clearSelection = function() {
                window.getSelection().removeAllRanges();
            };
        })();
        """
    }

    // MARK: - Highlight Actions

    public func addHighlight(startOffset: Int, endOffset: Int, text: String) {
        let highlight = EPUBHighlightData(
            chapterIndex: currentChapterIndex,
            chapterHref: chapterHTMLPaths.indices.contains(currentChapterIndex)
                ? chapterHTMLPaths[currentChapterIndex].lastPathComponent : "",
            startOffset: startOffset,
            endOffset: endOffset,
            selectedText: text,
            colorCategory: selectedHighlightColor
        )
        highlights.append(highlight)
        showHighlightToolbar = false

        Task {
            await onCreateHighlight?(
                currentChapterIndex,
                highlight.chapterHref,
                startOffset,
                endOffset,
                text,
                selectedHighlightColor
            )
        }
    }

    public func setHighlights(_ data: [EPUBHighlightData]) {
        highlights = data
    }
}
