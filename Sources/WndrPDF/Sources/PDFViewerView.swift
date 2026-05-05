import PDFKit
import SwiftUI
import WndrKit

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public struct PDFViewerView: View {
    @ObservedObject var viewModel: PDFViewerViewModel
    @State private var showColorPopover = false
    @State private var showClearConfirmation = false

    public init(viewModel: PDFViewerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Thumbnail sidebar (optional)
            if viewModel.showThumbnails {
                PDFThumbnailListView(viewModel: viewModel)
                    .frame(width: 180)
                    .background(Color.platformControlBackground)
                Divider()
            }

            // PDF content - full height, no extra toolbars
            if viewModel.pdfDocument != nil {
                PDFViewRepresentable(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack {
                    Image(systemName: "doc.text.fill.viewfinder")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("Loading PDF...")
                        .font(.title2)
                        .padding(.top)
                    if viewModel.pageCount == 0 {
                        Text("Unable to load PDF document")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                        if let url = viewModel.documentURL {
                            Text("Path: \(url.path)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.platformControlBackground)
            }
        }
        .navigationTitle(viewModel.documentTitle)
        .toolbar {
            // Page navigation
            ToolbarItemGroup(placement: .automatic) {
                Button(action: viewModel.previousPage) {
                    Image(systemName: "chevron.left")
                }
                #if os(macOS)
                .help("Previous Page")
                #endif
                .disabled(!viewModel.canGoPrevious)

                Text("\(viewModel.currentPage) / \(viewModel.pageCount)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(minWidth: 60)

                Button(action: viewModel.nextPage) {
                    Image(systemName: "chevron.right")
                }
                #if os(macOS)
                .help("Next Page")
                #endif
                .disabled(!viewModel.canGoNext)
            }

            // Annotation tools
            ToolbarItemGroup(placement: .automatic) {
                Picker("Tool", selection: $viewModel.selectedTool) {
                    Image(systemName: "highlighter")
                        .tag(AnnotationTool.highlight)
                    Image(systemName: "note.text")
                        .tag(AnnotationTool.note)
                }
                .pickerStyle(.segmented)
                .frame(width: 80)

                // Color picker button with popover
                Button(action: { showColorPopover.toggle() }) {
                    Circle()
                        .fill(AnnotationColorOption(rawValue: viewModel.selectedColor)?.color ?? .yellow)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Color.primary.opacity(0.3), lineWidth: 1))
                }
                .popover(isPresented: $showColorPopover, arrowEdge: .bottom) {
                    ColorPickerPopover(selectedColor: $viewModel.selectedColor)
                }

                // Clear highlights button
                Button(action: { showClearConfirmation = true }) {
                    Image(systemName: "xmark.circle")
                }
                .disabled(viewModel.annotations.isEmpty)
            }

            // Zoom controls
            ToolbarItemGroup(placement: .automatic) {
                Button(action: viewModel.zoomOut) {
                    Image(systemName: "minus.magnifyingglass")
                }
                .disabled(!viewModel.canZoomOut)

                Button(action: viewModel.zoomIn) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .disabled(!viewModel.canZoomIn)

                Menu {
                    Button("Actual Size") { viewModel.actualSize() }
                    Button("Fit to Width") { viewModel.fitToWidth() }
                    Divider()
                    ForEach([50, 75, 100, 125, 150, 200], id: \.self) { percent in
                        Button("\(percent)%") { viewModel.setZoom(percent) }
                    }
                } label: {
                    Text("\(Int((viewModel.scaleFactor ?? 1.0) * 100))%")
                        .frame(minWidth: 45)
                }
                #if os(macOS)
                .menuStyle(.borderlessButton)
                #endif
            }

            // Display mode & View options
            ToolbarItem(placement: .automatic) {
                Menu {
                    Section("Page Layout") {
                        Button {
                            viewModel.displayMode = .singlePage
                        } label: {
                            Label("Single Page", systemImage: "doc")
                        }
                        Button {
                            viewModel.displayMode = .singlePageContinuous
                        } label: {
                            Label("Continuous", systemImage: "arrow.down.doc")
                        }
                        Button {
                            viewModel.displayMode = .twoUp
                        } label: {
                            Label("Two Pages", systemImage: "doc.on.doc")
                        }
                    }

                    Divider()

                    Button {
                        viewModel.toggleThumbnails()
                    } label: {
                        Label(
                            viewModel.showThumbnails ? "Hide Thumbnails" : "Show Thumbnails",
                            systemImage: "sidebar.left"
                        )
                    }
                } label: {
                    Image(systemName: "rectangle.split.3x1")
                }
            }
        }
        .alert("Clear All Highlights?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                viewModel.clearAllAnnotations()
            }
        } message: {
            Text("This will remove all highlights from this document. This action cannot be undone.")
        }
    }
}

// MARK: - Color Picker Popover

private struct ColorPickerPopover: View {
    @Binding var selectedColor: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 8) {
            Text("Highlight Color")
                .font(.headline)
                .foregroundColor(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 28))], spacing: 8) {
                ForEach(AnnotationColorOption.allCases, id: \.self) { colorOption in
                    Circle()
                        .fill(colorOption.color)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .stroke(selectedColor == colorOption.id ? Color.primary : Color.clear, lineWidth: 2)
                        )
                        .onTapGesture {
                            selectedColor = colorOption.id
                            dismiss()
                        }
                }
            }
        }
        .padding(12)
        .frame(width: 120)
    }
}

struct PDFThumbnailListView: View {
    @ObservedObject var viewModel: PDFViewerViewModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(0..<viewModel.pageCount, id: \.self) { pageIndex in
                    PDFThumbnailItemView(
                        pageIndex: pageIndex,
                        isSelected: pageIndex == viewModel.currentPage - 1,
                        viewModel: viewModel
                    )
                }
            }
            .padding(8)
        }
    }
}

struct PDFThumbnailItemView: View {
    let pageIndex: Int
    let isSelected: Bool
    @ObservedObject var viewModel: PDFViewerViewModel

    var body: some View {
        VStack(spacing: 4) {
            if let thumbnail = viewModel.thumbnail(for: pageIndex) {
                thumbnail.swiftUIImage
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 150)
                    .border(isSelected ? Color.accentColor : Color.clear, width: 2)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 150)
            }

            Text("Page \(pageIndex + 1)")
                .font(.caption)
                .foregroundColor(isSelected ? .accentColor : .secondary)
        }
        .onTapGesture {
            viewModel.goToPage(pageIndex)
        }
    }
}

// MARK: - Custom PDFView for macOS with Context Menu Support

#if canImport(AppKit)
class CustomPDFView: PDFView {
    weak var coordinator: PDFViewCoordinator?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let page = page(for: point, nearest: false) else {
            return super.menu(for: event)
        }

        let pagePoint = convert(point, to: page)

        // Check if there's a highlight annotation at this point
        var highlightAtPoint: PDFAnnotation?
        for annotation in page.annotations {
            if annotation.type == "Highlight" && annotation.bounds.contains(pagePoint) {
                highlightAtPoint = annotation
                break
            }
        }

        // If there's a highlight, show custom menu
        if let highlight = highlightAtPoint {
            let menu = NSMenu()
            let removeItem = NSMenuItem(
                title: "Remove Highlight",
                action: #selector(removeHighlight(_:)),
                keyEquivalent: ""
            )
            removeItem.target = self
            removeItem.representedObject = highlight
            menu.addItem(removeItem)
            return menu
        }

        return super.menu(for: event)
    }

    @objc private func removeHighlight(_ sender: NSMenuItem) {
        guard let annotation = sender.representedObject as? PDFAnnotation,
              let page = annotation.page else { return }

        page.removeAnnotation(annotation)

        // Notify the view model to remove from persistence
        if let coordinator = coordinator {
            Task { @MainActor in
                // Find the annotation in the view model and remove it
                if let pageIndex = document?.index(for: page) {
                    await coordinator.viewModel.removeAnnotationAt(pageIndex: pageIndex, bounds: annotation.bounds)
                }
            }
        }
    }
}

// MARK: - PDFView Platform Representable

struct PDFViewRepresentable: NSViewRepresentable {
    @ObservedObject var viewModel: PDFViewerViewModel

    func makeCoordinator() -> PDFViewCoordinator {
        PDFViewCoordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = CustomPDFView()
        pdfView.autoScales = true
        pdfView.displayMode = viewModel.displayMode
        pdfView.displaysPageBreaks = true
        pdfView.document = viewModel.pdfDocument

        // Set the coordinator reference for context menu handling
        (pdfView as? CustomPDFView)?.coordinator = context.coordinator

        context.coordinator.pdfView = pdfView
        context.coordinator.registerNotifications(for: pdfView)

        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== viewModel.pdfDocument {
            pdfView.document = viewModel.pdfDocument
        }
        if pdfView.displayMode != viewModel.displayMode {
            pdfView.displayMode = viewModel.displayMode
        }
        if let scaleFactor = viewModel.scaleFactor {
            pdfView.scaleFactor = scaleFactor
        }
        context.coordinator.currentTool = viewModel.selectedTool
        context.coordinator.currentColor = viewModel.selectedColor
    }

    static func dismantleNSView(_ pdfView: PDFView, coordinator: PDFViewCoordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }
}

#else // UIKit (iPadOS)
struct PDFViewRepresentable: UIViewRepresentable {
    @ObservedObject var viewModel: PDFViewerViewModel

    func makeCoordinator() -> PDFViewCoordinator {
        PDFViewCoordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = viewModel.displayMode
        pdfView.displaysPageBreaks = true
        pdfView.document = viewModel.pdfDocument
        // iPadOS: optimize for touch
        pdfView.usePageViewController(true, withViewOptions: nil)

        context.coordinator.pdfView = pdfView
        context.coordinator.registerNotifications(for: pdfView)

        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== viewModel.pdfDocument {
            pdfView.document = viewModel.pdfDocument
        }
        if pdfView.displayMode != viewModel.displayMode {
            pdfView.displayMode = viewModel.displayMode
        }
        if let scaleFactor = viewModel.scaleFactor {
            pdfView.scaleFactor = scaleFactor
        }
        context.coordinator.currentTool = viewModel.selectedTool
        context.coordinator.currentColor = viewModel.selectedColor
    }

    static func dismantleUIView(_ pdfView: PDFView, coordinator: PDFViewCoordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }
}
#endif

// MARK: - Shared PDFView Coordinator

class PDFViewCoordinator: NSObject {
    var viewModel: PDFViewerViewModel
    weak var pdfView: PDFView?
    var currentTool: AnnotationTool = .highlight
    var currentColor: String = "yellow"
    private var selectionDebounceWorkItem: DispatchWorkItem?

    init(viewModel: PDFViewerViewModel) {
        self.viewModel = viewModel
        super.init()
    }

    func registerNotifications(for pdfView: PDFView) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(selectionChanged(_:)),
            name: .PDFViewSelectionChanged,
            object: pdfView
        )
    }

    @objc func pageChanged(_ notification: Notification) {
        guard let pdfView = notification.object as? PDFView,
              let currentPage = pdfView.currentPage,
              let pageIndex = pdfView.document?.index(for: currentPage) else { return }

        Task { @MainActor in
            viewModel.currentPage = pageIndex + 1
        }
    }

    @objc func selectionChanged(_ notification: Notification) {
        selectionDebounceWorkItem?.cancel()

        guard currentTool == .highlight else { return }
        guard let pdfView = notification.object as? PDFView,
              let selection = pdfView.currentSelection,
              let selectionString = selection.string,
              !selectionString.isEmpty else { return }

        let workItem = DispatchWorkItem { [weak self] in
            self?.createAnnotationFromSelection(pdfView: pdfView, selection: selection)
        }
        selectionDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    private func createAnnotationFromSelection(pdfView: PDFView, selection: PDFSelection) {
        guard let pages = selection.pages as? [PDFPage],
              let document = pdfView.document else { return }

        for page in pages {
            let pageIndex = document.index(for: page)
            let textSnippet = selection.string
            let colorOption = AnnotationColorOption(rawValue: currentColor) ?? .yellow

            // Get selections by line for precise highlighting
            let lineSelections = selection.selectionsByLine()
            var allBounds: [CGRect] = []

            // Create a highlight for each line of selected text
            for lineSelection in lineSelections {
                // Only process selections on the current page
                guard let linePages = lineSelection.pages as? [PDFPage],
                      linePages.contains(page) else { continue }

                let lineBounds = lineSelection.bounds(for: page)
                allBounds.append(lineBounds)

                let highlight = PDFAnnotation(bounds: lineBounds, forType: .highlight, withProperties: nil)
                highlight.color = colorOption.platformColor
                page.addAnnotation(highlight)
            }

            // Store all bounds for persistence
            if !allBounds.isEmpty {
                Task { @MainActor in
                    await viewModel.onCreateAnnotation?(pageIndex, allBounds, textSnippet, currentColor)
                }
            }
        }

        pdfView.clearSelection()
    }
}
