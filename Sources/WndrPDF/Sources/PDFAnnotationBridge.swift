import Foundation
import PDFKit

#if os(macOS)
import AppKit
public typealias PlatformColor = NSColor
#elseif os(iOS)
import UIKit
public typealias PlatformColor = UIColor
#else
#error("Unsupported platform: PDFAnnotationBridge requires macOS or iOS")
#endif

public struct PDFAnnotationBridge {

    /// Creates highlight annotations for specified selections on a page
    public static func createHighlight(
        on page: PDFPage,
        selections: [PDFSelection],
        color: PlatformColor = .systemYellow
    ) -> [PDFAnnotation] {
        return selections.compactMap { selection in
            let bounds = selection.bounds(for: page)
            guard !bounds.isEmpty else { return nil }

            let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
            annotation.color = color
            page.addAnnotation(annotation)
            return annotation
        }
    }

    /// Creates a highlight annotation from normalized rects
    public static func createHighlight(
        on page: PDFPage,
        normalizedRects: [CGRect],
        color: PlatformColor = .systemYellow
    ) -> [PDFAnnotation] {
        let pageBounds = page.bounds(for: .mediaBox)

        return normalizedRects.compactMap { normalizedRect in
            // Convert normalized (0-1) coordinates to page coordinates
            let rect = CGRect(
                x: normalizedRect.origin.x * pageBounds.width,
                y: normalizedRect.origin.y * pageBounds.height,
                width: normalizedRect.width * pageBounds.width,
                height: normalizedRect.height * pageBounds.height
            )

            guard !rect.isEmpty else { return nil }

            let annotation = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
            annotation.color = color
            page.addAnnotation(annotation)
            return annotation
        }
    }

    /// Gets the current selection's text from a PDF view
    public static func selectedText(from pdfView: PDFView) -> String? {
        guard let selection = pdfView.currentSelection else { return nil }
        return selection.string
    }

    /// Gets normalized rects for current selection
    public static func selectionRects(from pdfView: PDFView) -> [(pageIndex: Int, rects: [CGRect])]? {
        guard let selection = pdfView.currentSelection,
              let document = pdfView.document else { return nil }

        var result: [(pageIndex: Int, rects: [CGRect])] = []

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let pageBounds = page.bounds(for: .mediaBox)

            let selectionRects = selection.selectionsByLine()
                .compactMap { lineSelection -> CGRect? in
                    let bounds = lineSelection.bounds(for: page)
                    guard !bounds.isEmpty else { return nil }

                    // Normalize to 0-1 coordinates
                    return CGRect(
                        x: bounds.origin.x / pageBounds.width,
                        y: bounds.origin.y / pageBounds.height,
                        width: bounds.width / pageBounds.width,
                        height: bounds.height / pageBounds.height
                    )
                }

            if !selectionRects.isEmpty {
                result.append((pageIndex: pageIndex, rects: selectionRects))
            }
        }

        return result.isEmpty ? nil : result
    }

    /// Color preset mapping
    public static func color(for category: String) -> PlatformColor {
        switch category {
        case "yellow": return .systemYellow
        case "green": return .systemGreen
        case "blue": return .systemBlue
        case "pink": return .systemPink
        case "orange": return .systemOrange
        case "purple": return .systemPurple
        default: return .systemYellow
        }
    }
}
