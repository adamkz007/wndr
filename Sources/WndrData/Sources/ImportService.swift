import CoreData
import CryptoKit
import Foundation
import PDFKit
import UniformTypeIdentifiers

/// Supported document types for import.
public enum DocumentType: String {
    case pdf
    case epub

    public static func from(pathExtension ext: String) -> DocumentType? {
        switch ext.lowercased() {
        case "pdf": return .pdf
        case "epub": return .epub
        default: return nil
        }
    }

    public static let supportedExtensions: Set<String> = ["pdf", "epub"]
}

public actor ImportService {
    public enum ImportError: LocalizedError {
        case unsupportedFileType
        case fileNotFound
        case duplicateDocument
        case copyFailed(Error)
        case metadataExtractionFailed
        case custom(String)

        public var errorDescription: String? {
            switch self {
            case .unsupportedFileType:
                return "The file type is not supported"
            case .fileNotFound:
                return "The file could not be found"
            case .duplicateDocument:
                return "This document already exists in the library"
            case .copyFailed(let error):
                return "Failed to copy file: \(error.localizedDescription)"
            case .metadataExtractionFailed:
                return "Failed to extract document metadata"
            case .custom(let message):
                return message
            }
        }
    }

    public struct ImportResult {
        public let documentID: UUID
        public let wasDedup: Bool
        public let needsOCR: Bool
    }

    private let persistenceController: PersistenceController
    private let libraryStore: LibraryRootStore
    private let logger: WndrLogger
    private let fileManager: FileManager

    public init(
        persistenceController: PersistenceController,
        libraryStore: LibraryRootStore,
        logger: WndrLogger = WndrLogger(category: "import"),
        fileManager: FileManager = .default
    ) {
        self.persistenceController = persistenceController
        self.libraryStore = libraryStore
        self.logger = logger
        self.fileManager = fileManager
    }

    public func importDocument(
        from sourceURL: URL,
        in libraryURL: URL,
        copyFile: Bool = true
    ) async throws -> ImportResult {
        logger.info("Starting import: \(sourceURL.lastPathComponent)")

        // Validate file type
        let ext = sourceURL.pathExtension.lowercased()
        guard let docType = DocumentType.from(pathExtension: ext) else {
            throw ImportError.unsupportedFileType
        }

        // Check if file exists
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory) else {
            throw ImportError.fileNotFound
        }

        // Check if it's a directory instead of a file
        if isDirectory.boolValue {
            logger.error("Cannot import directory as document: \(sourceURL.lastPathComponent)")
            // Special message for EPUB directories
            if ext == "epub" {
                throw ImportError.custom("The EPUB appears to be an extracted directory. Please compress it as a .epub file first.")
            }
            throw ImportError.custom("Cannot import directory. Please select a file instead.")
        }

        // Calculate checksum for deduplication
        let checksum = try calculateChecksum(for: sourceURL)
        logger.info("Calculated checksum: \(checksum)")

        // Check for duplicates
        let context = persistenceController.newBackgroundContext()
        if let existing = try await findExistingDocument(withChecksum: checksum, in: context) {
            logger.info("Document already exists with ID: \(existing.id?.uuidString ?? "unknown")")
            throw ImportError.duplicateDocument
        }

        // Extract metadata based on document type
        let metadata: DocumentMetadata
        switch docType {
        case .pdf:
            metadata = try await extractPDFMetadata(from: sourceURL)
        case .epub:
            metadata = try await extractEPUBMetadata(from: sourceURL)
        }

        // Create document entity
        let documentID = UUID()
        let document = Document(context: context)
        document.id = documentID

        // Determine document title (will be used for filename too)
        let documentTitle = metadata.title ?? sourceURL.deletingPathExtension().lastPathComponent
        document.title = documentTitle
        document.subtitle = metadata.subtitle
        document.authors = metadata.authors
        document.source = metadata.source
        document.publicationDate = metadata.publicationDate
        document.keywords = metadata.keywords
        document.checksum = checksum
        document.pageCount = Int32(metadata.pageCount)
        document.ocrStatus = metadata.needsOCR ? "pending" : "complete"
        document.documentType = docType.rawValue
        document.createdAt = Date()
        document.updatedAt = Date()

        // Copy file to library
        if copyFile {
            let destinationURL: URL
            switch docType {
            case .pdf:
                destinationURL = await libraryStore.documentURL(for: documentID, in: libraryURL, filename: documentTitle)
            case .epub:
                destinationURL = await libraryStore.epubURL(for: documentID, in: libraryURL, filename: documentTitle)
            }
            try await copyDocument(from: sourceURL, to: destinationURL)
            document.fileURL = destinationURL
            logger.info("Copied \(docType.rawValue) to: \(destinationURL.path)")
        } else {
            document.fileURL = sourceURL
        }

        // Save context
        try context.save()
        logger.info("Document saved with ID: \(documentID.uuidString) (type: \(docType.rawValue))")

        return ImportResult(
            documentID: documentID,
            wasDedup: false,
            needsOCR: metadata.needsOCR
        )
    }

    public func importMultipleDocuments(
        from urls: [URL],
        in libraryURL: URL
    ) async -> [Result<ImportResult, Error>] {
        var results: [Result<ImportResult, Error>] = []

        for url in urls {
            do {
                let result = try await importDocument(from: url, in: libraryURL)
                results.append(.success(result))
            } catch {
                results.append(.failure(error))
                logger.error("Import failed for \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        return results
    }

    // MARK: - Private Methods

    private func calculateChecksum(for url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func findExistingDocument(
        withChecksum checksum: String,
        in context: NSManagedObjectContext
    ) async throws -> Document? {
        let fetchRequest = Document.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "checksum == %@", checksum)
        fetchRequest.fetchLimit = 1

        return try context.fetch(fetchRequest).first
    }

    private struct DocumentMetadata {
        var title: String?
        var subtitle: String?
        var authors: [String]?
        var source: String?
        var publicationDate: Date?
        var keywords: [String]?
        var pageCount: Int
        var needsOCR: Bool
    }

    private func extractPDFMetadata(from url: URL) async throws -> DocumentMetadata {
        guard let document = PDFDocument(url: url) else {
            throw ImportError.metadataExtractionFailed
        }

        let attributes = document.documentAttributes ?? [:]

        let title = attributes[PDFDocumentAttribute.titleAttribute] as? String
        let author = attributes[PDFDocumentAttribute.authorAttribute] as? String
        let subject = attributes[PDFDocumentAttribute.subjectAttribute] as? String
        let keywords = attributes[PDFDocumentAttribute.keywordsAttribute] as? [String]
        let creationDate = attributes[PDFDocumentAttribute.creationDateAttribute] as? Date

        var authors: [String]?
        if let author = author {
            authors = author.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }

        // Check if PDF needs OCR (has no text layer)
        let needsOCR = await checkNeedsOCR(document: document)

        return DocumentMetadata(
            title: title,
            subtitle: subject,
            authors: authors,
            source: nil,
            publicationDate: creationDate,
            keywords: keywords,
            pageCount: document.pageCount,
            needsOCR: needsOCR
        )
    }

    private func extractEPUBMetadata(from url: URL) async throws -> DocumentMetadata {
        let epubParser = EPUBParser()
        do {
            let epubMeta = try epubParser.extractMetadata(from: url)
            return DocumentMetadata(
                title: epubMeta.title,
                subtitle: epubMeta.description,
                authors: epubMeta.authors.isEmpty ? nil : epubMeta.authors,
                source: epubMeta.publisher,
                publicationDate: nil,
                keywords: nil,
                pageCount: 0, // EPUBs don't have fixed page counts
                needsOCR: false
            )
        } catch {
            logger.error("EPUB metadata extraction failed: \(error.localizedDescription)")
            // Fall back to filename-based metadata
            return DocumentMetadata(
                title: nil,
                subtitle: nil,
                authors: nil,
                source: nil,
                publicationDate: nil,
                keywords: nil,
                pageCount: 0,
                needsOCR: false
            )
        }
    }

    private func checkNeedsOCR(document: PDFDocument) async -> Bool {
        // Check first few pages for text content
        let pagesToCheck = min(3, document.pageCount)

        for i in 0..<pagesToCheck {
            guard let page = document.page(at: i) else { continue }
            if let text = page.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false // Has text, doesn't need OCR
            }
        }

        return true // No text found, needs OCR
    }

    private func copyDocument(from source: URL, to destination: URL) async throws {
        let directory = destination.deletingLastPathComponent()

        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            throw ImportError.copyFailed(error)
        }
    }
}
