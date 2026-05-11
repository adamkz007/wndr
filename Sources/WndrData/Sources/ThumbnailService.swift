import Foundation
import PDFKit
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

public actor ThumbnailService {
    private let libraryStore: LibraryRootStore
    private let logger: WndrLogger
    private let fileManager: FileManager

    public static let thumbnailSize = CGSize(width: 80, height: 100)

    public init(
        libraryStore: LibraryRootStore,
        logger: WndrLogger = WndrLogger(category: "thumbnails"),
        fileManager: FileManager = .default
    ) {
        self.libraryStore = libraryStore
        self.logger = logger
        self.fileManager = fileManager
    }

    /// Minimum file size (bytes) for a valid PNG thumbnail.
    /// A real rendered page thumbnail will always be larger than this.
    private static let minimumValidThumbnailSize: Int = 200

    /// Returns the thumbnail URL for a document, generating it if necessary.
    /// Also validates existing thumbnails and regenerates corrupt/blank ones.
    public func thumbnailURL(for documentID: UUID, pdfURL: URL, in libraryURL: URL) async -> URL? {
        let thumbURL = await libraryStore.thumbnailURL(for: documentID, in: libraryURL)

        // Check if thumbnail already exists AND is valid (non-empty)
        if fileManager.fileExists(atPath: thumbURL.path) {
            if let attrs = try? fileManager.attributesOfItem(atPath: thumbURL.path),
               let fileSize = attrs[.size] as? Int,
               fileSize >= Self.minimumValidThumbnailSize {
                return thumbURL
            }
            // Thumbnail exists but appears corrupt/blank – delete and regenerate
            try? fileManager.removeItem(at: thumbURL)
            logger.info("Removed invalid thumbnail for \(documentID), regenerating")
        }

        // Generate thumbnail from the document's first PDF page.
        do {
            try await generateThumbnail(from: pdfURL, to: thumbURL)
            return thumbURL
        } catch {
            logger.error("Failed to generate thumbnail for \(documentID): \(error.localizedDescription)")
            return nil
        }
    }

    /// Check if a thumbnail exists for a document
    public func hasThumbnail(for documentID: UUID, in libraryURL: URL) async -> Bool {
        let thumbURL = await libraryStore.thumbnailURL(for: documentID, in: libraryURL)
        return fileManager.fileExists(atPath: thumbURL.path)
    }

    /// Generate a thumbnail from a PDF file.
    ///
    /// Uses `CGBitmapContext` so that rendering works correctly from any thread
    /// (actors, background queues, etc.) and is cross-platform (macOS + iPadOS).
    public func generateThumbnail(from pdfURL: URL, to destinationURL: URL) async throws {
        guard let document = PDFDocument(url: pdfURL),
              let page = document.page(at: 0) else {
            throw ThumbnailError.pdfLoadFailed
        }

        // Get the page bounds
        let pageBounds = page.bounds(for: .mediaBox)
        guard pageBounds.width > 0, pageBounds.height > 0 else {
            throw ThumbnailError.pdfLoadFailed
        }

        // Calculate scale to fit thumbnail size while maintaining aspect ratio
        let scaleX = Self.thumbnailSize.width / pageBounds.width
        let scaleY = Self.thumbnailSize.height / pageBounds.height
        let scale = min(scaleX, scaleY)

        let pixelWidth = Int(ceil(pageBounds.width * scale))
        let pixelHeight = Int(ceil(pageBounds.height * scale))

        // Create a CGBitmapContext – works reliably from any thread and platform
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
            throw ThumbnailError.imageConversionFailed
        }

        // Fill with white background
        cgContext.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        cgContext.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        // Scale and draw the PDF page
        cgContext.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: cgContext)

        // Extract CGImage and convert to PNG
        guard let cgImage = cgContext.makeImage() else {
            throw ThumbnailError.imageConversionFailed
        }

        let pngData: Data?
        #if canImport(AppKit)
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        pngData = bitmapRep.representation(using: .png, properties: [:])
        #else
        let uiImage = UIImage(cgImage: cgImage)
        pngData = uiImage.pngData()
        #endif

        guard let imageData = pngData else {
            throw ThumbnailError.imageConversionFailed
        }

        // Ensure directory exists
        let directory = destinationURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        // Write thumbnail to disk
        try imageData.write(to: destinationURL)
        logger.info("Generated thumbnail at: \(destinationURL.path)")
    }

    /// Regenerate thumbnails for all provided documents, deleting any existing ones first.
    /// Returns the count of successes and failures.
    public func regenerateAllThumbnails(
        documents: [(id: UUID, pdfURL: URL)],
        libraryURL: URL
    ) async -> (succeeded: Int, failed: Int) {
        logger.info("Starting bulk thumbnail regeneration for \(documents.count) documents")
        var succeeded = 0
        var failed = 0

        for (documentID, pdfURL) in documents {
            // Delete existing thumbnail so we get a fresh render
            try? await deleteThumbnail(for: documentID, in: libraryURL)

            // Regenerate
            if let _ = await thumbnailURL(for: documentID, pdfURL: pdfURL, in: libraryURL) {
                succeeded += 1
            } else {
                failed += 1
            }
        }

        logger.info("Bulk thumbnail regeneration complete: \(succeeded) succeeded, \(failed) failed")
        return (succeeded, failed)
    }

    /// Delete thumbnail for a document
    public func deleteThumbnail(for documentID: UUID, in libraryURL: URL) async throws {
        let thumbURL = await libraryStore.thumbnailURL(for: documentID, in: libraryURL)
        if fileManager.fileExists(atPath: thumbURL.path) {
            try fileManager.removeItem(at: thumbURL)
            logger.info("Deleted thumbnail for document: \(documentID)")
        }
    }

    public enum ThumbnailError: LocalizedError {
        case pdfLoadFailed
        case imageConversionFailed

        public var errorDescription: String? {
            switch self {
            case .pdfLoadFailed:
                return "Failed to load PDF document"
            case .imageConversionFailed:
                return "Failed to convert thumbnail image"
            }
        }
    }
}
