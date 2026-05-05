import Combine
import Foundation
import PDFKit
import WndrKit

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@MainActor
public final class PDFViewerViewModel: ObservableObject {
    @Published public var currentPage: Int = 1
    @Published public var pageCount: Int = 0
    @Published public var showThumbnails: Bool = false
    @Published public var displayMode: PDFDisplayMode = .singlePageContinuous
    @Published public var scaleFactor: CGFloat?
    @Published public var selectedTool: AnnotationTool = .highlight
    @Published public var selectedColor: String = "yellow"
    @Published public var showAnnotationToolbar: Bool = true
    @Published public var annotations: [AnnotationData] = []

    public var pdfDocument: PDFDocument?
    public var documentTitle: String
    public var documentURL: URL?
    public var documentID: UUID?

    public var onCreateAnnotation: ((Int, [CGRect], String?, String) async -> Void)?
    public var onDeleteAnnotation: ((UUID) async -> Void)?
    public var onDeleteAllAnnotations: (() async -> Void)?
    public var onRemoveAnnotationAt: ((Int, CGRect) async -> Void)?

    private var thumbnailCache: [Int: PlatformImage] = [:]

    public var canGoPrevious: Bool {
        currentPage > 1
    }

    public var canGoNext: Bool {
        currentPage < pageCount
    }

    public var canZoomIn: Bool {
        guard let scaleFactor = scaleFactor else { return true }
        return scaleFactor < 5.0
    }

    public var canZoomOut: Bool {
        guard let scaleFactor = scaleFactor else { return true }
        return scaleFactor > 0.25
    }

    public init(documentURL: URL) {
        self.documentURL = documentURL
        self.documentTitle = documentURL.deletingPathExtension().lastPathComponent
        loadDocument(from: documentURL)
    }

    public init(documentID: UUID, documentURL: URL?, title: String) {
        self.documentID = documentID
        self.documentURL = documentURL
        self.documentTitle = title

        if let url = documentURL {
            loadDocument(from: url)
        }
    }

    public func setAnnotations(_ annotations: [AnnotationData]) {
        print("DEBUG: Setting \(annotations.count) annotations on PDFViewerViewModel")
        self.annotations = annotations
        applyAnnotationsToDocument()
    }

    private func applyAnnotationsToDocument() {
        guard let document = pdfDocument else {
            print("DEBUG: Cannot apply annotations - no PDF document loaded")
            return
        }

        print("DEBUG: Applying \(annotations.count) annotations to PDF document")

        // Remove existing highlight annotations
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let existingAnnotations = page.annotations
            for annotation in existingAnnotations {
                if annotation.type == "Highlight" || annotation.type == "Underline" {
                    page.removeAnnotation(annotation)
                }
            }
        }

        // Add annotations from our data
        for annotationData in annotations {
            guard let page = document.page(at: annotationData.pageIndex) else { continue }

            for rect in annotationData.rects {
                let pdfAnnotation = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
                pdfAnnotation.color = AnnotationColorOption(rawValue: annotationData.colorCategory)?.platformColor ?? .yellow
                page.addAnnotation(pdfAnnotation)
            }
        }
    }

    public func createAnnotation(from selection: PDFSelection) {
        guard selectedTool == .highlight else { return }
        guard let pages = selection.pages as? [PDFPage] else { return }

        for page in pages {
            guard let pageIndex = pdfDocument?.index(for: page) else { continue }
            let selectionBounds = selection.bounds(for: page)
            let textSnippet = selection.string

            Task {
                await onCreateAnnotation?(pageIndex, [selectionBounds], textSnippet, selectedColor)
            }
        }
    }

    public func clearAllAnnotations() {
        Task {
            await onDeleteAllAnnotations?()
        }
    }

    public func removeAnnotationAt(pageIndex: Int, bounds: CGRect) async {
        // Find the annotation that matches this page and bounds
        if let annotation = annotations.first(where: { anno in
            anno.pageIndex == pageIndex && anno.rects.contains(where: { rect in
                // Check if the bounds approximately match (allowing for small differences)
                abs(rect.origin.x - bounds.origin.x) < 1 &&
                abs(rect.origin.y - bounds.origin.y) < 1 &&
                abs(rect.size.width - bounds.size.width) < 1 &&
                abs(rect.size.height - bounds.size.height) < 1
            })
        }) {
            // Remove from local array
            annotations.removeAll { $0.id == annotation.id }

            // Remove from persistence
            await onDeleteAnnotation?(annotation.id)

            // Re-apply remaining annotations to document
            applyAnnotationsToDocument()
        } else {
            // If exact match not found, notify handler to remove by position
            await onRemoveAnnotationAt?(pageIndex, bounds)
        }
    }

    public func toggleAnnotationToolbar() {
        showAnnotationToolbar.toggle()
    }

    private func loadDocument(from url: URL) {
        print("DEBUG: Attempting to load PDF from URL: \(url.path)")
        print("DEBUG: File exists: \(FileManager.default.fileExists(atPath: url.path))")

        guard let document = PDFDocument(url: url) else {
            print("ERROR: Failed to create PDFDocument from URL: \(url.path)")
            pageCount = 0
            return
        }

        print("DEBUG: Successfully loaded PDF with \(document.pageCount) pages")
        self.pdfDocument = document
        self.pageCount = document.pageCount

        if pageCount > 0 {
            currentPage = 1
        }
    }

    public func nextPage() {
        guard canGoNext else { return }
        currentPage += 1
    }

    public func previousPage() {
        guard canGoPrevious else { return }
        currentPage -= 1
    }

    public func goToPage(_ pageIndex: Int) {
        guard pageIndex >= 0 && pageIndex < pageCount else { return }
        currentPage = pageIndex + 1
    }

    public func toggleThumbnails() {
        showThumbnails.toggle()
    }

    public func zoomIn() {
        let current = scaleFactor ?? 1.0
        scaleFactor = min(current * 1.2, 5.0)
    }

    public func zoomOut() {
        let current = scaleFactor ?? 1.0
        scaleFactor = max(current / 1.2, 0.25)
    }

    public func actualSize() {
        scaleFactor = 1.0
    }

    public func fitToWidth() {
        // Signal to PDFView to auto-scale to width
        scaleFactor = nil
    }

    public func setZoom(_ percent: Int) {
        scaleFactor = CGFloat(percent) / 100.0
    }

    public func thumbnail(for pageIndex: Int) -> PlatformImage? {
        if let cached = thumbnailCache[pageIndex] {
            return cached
        }

        guard let document = pdfDocument,
              let page = document.page(at: pageIndex) else {
            return nil
        }

        let pageBounds = page.bounds(for: .mediaBox)
        let targetHeight: CGFloat = 150
        let scale = targetHeight / pageBounds.height
        let pixelWidth = Int(ceil(pageBounds.width * scale))
        let pixelHeight = Int(ceil(pageBounds.height * scale))

        // Use CGBitmapContext for cross-platform rendering
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let cgContext = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        cgContext.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        cgContext.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        cgContext.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: cgContext)

        guard let cgImage = cgContext.makeImage() else { return nil }

        #if canImport(AppKit)
        let image = NSImage(cgImage: cgImage, size: CGSize(width: pixelWidth, height: pixelHeight))
        #else
        let image = UIImage(cgImage: cgImage)
        #endif

        thumbnailCache[pageIndex] = image
        return image
    }
}

// MARK: - Annotation Data

public struct AnnotationData: Identifiable, Equatable {
    public let id: UUID
    public var kind: String
    public var pageIndex: Int
    public var rects: [CGRect]
    public var colorCategory: String
    public var textSnippet: String?

    public init(
        id: UUID,
        kind: String = "highlight",
        pageIndex: Int,
        rects: [CGRect],
        colorCategory: String = "yellow",
        textSnippet: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.pageIndex = pageIndex
        self.rects = rects
        self.colorCategory = colorCategory
        self.textSnippet = textSnippet
    }
}
