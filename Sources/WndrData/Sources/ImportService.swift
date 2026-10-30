import CoreData
import CryptoKit
import Foundation
import PDFKit
import UniformTypeIdentifiers

/// Supported document types for import.
public enum DocumentType: String {
    case pdf

    public static func from(pathExtension ext: String) -> DocumentType? {
        switch ext.lowercased() {
        case "pdf": return .pdf
        default: return nil
        }
    }

    public static let supportedExtensions: Set<String> = ["pdf"]
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
            throw ImportError.custom("Cannot import directory. Please select a file instead.")
        }

        // Calculate checksum for deduplication
        let checksum = try calculateChecksum(for: sourceURL)
        logger.info("Calculated checksum: \(checksum)")

        // Check for duplicates
        if try await documentExists(withChecksum: checksum) {
            logger.info("Document already exists with checksum: \(checksum)")
            throw ImportError.duplicateDocument
        }

        // Extract metadata based on document type
        let metadata: DocumentMetadata
        metadata = try await extractPDFMetadata(from: sourceURL)

        let documentID = UUID()

        // Determine document title (will be used for filename too)
        let documentTitle = metadata.title ?? sourceURL.deletingPathExtension().lastPathComponent
        let documentType = docType.rawValue

        // Copy file to library
        let storedFileURL: URL
        if copyFile {
            let destinationURL = await libraryStore.documentURL(for: documentID, in: libraryURL, filename: documentTitle)
            try await copyDocument(from: sourceURL, to: destinationURL)
            storedFileURL = destinationURL
            logger.info("Copied \(documentType) to: \(destinationURL.path)")
        } else {
            storedFileURL = sourceURL
        }

        // Create and save document entity
        do {
            try await persistenceController.performBackgroundTask { context in
                let now = Date()
                let document = Document(context: context)
                document.id = documentID
                document.title = documentTitle
                document.subtitle = metadata.subtitle
                document.authors = metadata.authors
                document.source = metadata.source
                document.publicationDate = metadata.publicationDate
                document.keywords = metadata.keywords
                document.checksum = checksum
                document.pageCount = Int32(metadata.pageCount)
                document.ocrStatus = metadata.needsOCR ? "pending" : "complete"
                document.documentType = documentType
                document.fileURL = storedFileURL
                document.createdAt = now
                document.updatedAt = now
                try context.save()
            }
        } catch {
            if copyFile {
                // The per-document directory is new, so removing it only discards this import's copy.
                try? fileManager.removeItem(at: storedFileURL.deletingLastPathComponent())
            }
            throw error
        }
        logger.info("Document saved with ID: \(documentID.uuidString) (type: \(documentType))")

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

    private func documentExists(withChecksum checksum: String) async throws -> Bool {
        try await persistenceController.performBackgroundTask { context in
            let fetchRequest = Document.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "checksum == %@", checksum)
            fetchRequest.fetchLimit = 1
            return try context.count(for: fetchRequest) > 0
        }
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
