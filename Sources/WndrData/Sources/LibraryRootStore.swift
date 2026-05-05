import Foundation

public actor LibraryRootStore {
    public enum LibraryDirectory: String {
        case pdfs = "PDFs"
        case epubs = "EPUBs"
        case notes = "Notes"
        case attachments = "Attachments"
        case index = "Index"
        case cache = "Cache"

        var subdirectories: [String] {
            switch self {
            case .index:
                return ["Thumbnails"]
            case .cache:
                return ["OCR", "Previews", "EPUB"]
            default:
                return []
            }
        }
    }

    private enum Keys {
        static let libraryBookmark = "library.root.bookmark"
    }

    private let defaults: UserDefaults
    private let logger: WndrLogger
    private let fileManager: FileManager

    public init(
        defaults: UserDefaults = .standard,
        logger: WndrLogger = .libraryRoot,
        fileManager: FileManager = .default
    ) {
        self.defaults = defaults
        self.logger = logger
        self.fileManager = fileManager
    }

    @discardableResult
    public func persistBookmark(for url: URL) throws -> Data {
        #if os(macOS)
        let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        // iPadOS: use standard bookmarks (app sandbox handles security)
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
        defaults.set(bookmark, forKey: Keys.libraryBookmark)
        logger.info("Stored bookmark for \(url.path)")

        // Create directory structure
        try createLibraryStructure(at: url)

        return bookmark
    }

    public func createLibraryStructure(at libraryURL: URL) throws {
        let directories: [LibraryDirectory] = [.pdfs, .epubs, .notes, .attachments, .index, .cache]

        for directory in directories {
            let directoryURL = libraryURL.appendingPathComponent(directory.rawValue, isDirectory: true)

            if !fileManager.fileExists(atPath: directoryURL.path) {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
                logger.info("Created directory: \(directory.rawValue)")
            }

            // Create subdirectories
            for subdirectory in directory.subdirectories {
                let subdirectoryURL = directoryURL.appendingPathComponent(subdirectory, isDirectory: true)
                if !fileManager.fileExists(atPath: subdirectoryURL.path) {
                    try fileManager.createDirectory(at: subdirectoryURL, withIntermediateDirectories: true, attributes: nil)
                    logger.info("Created subdirectory: \(directory.rawValue)/\(subdirectory)")
                }
            }
        }

        logger.info("Library structure verified at \(libraryURL.path)")
    }

    public func url(for directory: LibraryDirectory, in libraryURL: URL) -> URL {
        libraryURL.appendingPathComponent(directory.rawValue, isDirectory: true)
    }

    /// Sanitizes a filename for safe filesystem storage
    private func sanitizeFilename(_ filename: String, withExtension ext: String) -> String {
        // Remove or replace characters that are problematic for filesystems
        var sanitized = filename
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "*", with: "-")
            .replacingOccurrences(of: "?", with: "-")
            .replacingOccurrences(of: "\"", with: "'")
            .replacingOccurrences(of: "<", with: "-")
            .replacingOccurrences(of: ">", with: "-")
            .replacingOccurrences(of: "|", with: "-")
            .replacingOccurrences(of: "\0", with: "")

        // Trim whitespace and dots
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        while sanitized.hasPrefix(".") {
            sanitized = String(sanitized.dropFirst())
        }

        // Limit length (255 chars is typical filesystem limit, leave room for extension)
        let maxLength = 200
        if sanitized.count > maxLength {
            sanitized = String(sanitized.prefix(maxLength))
        }

        // Ensure we have a valid filename
        if sanitized.isEmpty {
            sanitized = "document"
        }

        // Add extension if not already present
        if !sanitized.lowercased().hasSuffix(".\(ext.lowercased())") {
            sanitized += ".\(ext)"
        }

        return sanitized
    }

    public func documentURL(for documentID: UUID, in libraryURL: URL, filename: String? = nil) -> URL {
        let pdfsURL = url(for: .pdfs, in: libraryURL)
        let documentDir = pdfsURL.appendingPathComponent(documentID.uuidString, isDirectory: true)

        // Use provided filename or fall back to generic "document.pdf"
        let finalFilename = filename.map { sanitizeFilename($0, withExtension: "pdf") } ?? "document.pdf"
        return documentDir.appendingPathComponent(finalFilename)
    }

    public func epubURL(for documentID: UUID, in libraryURL: URL, filename: String? = nil) -> URL {
        let epubsURL = url(for: .epubs, in: libraryURL)
        let documentDir = epubsURL.appendingPathComponent(documentID.uuidString, isDirectory: true)

        // Use provided filename or fall back to generic "document.epub"
        let finalFilename = filename.map { sanitizeFilename($0, withExtension: "epub") } ?? "document.epub"
        return documentDir.appendingPathComponent(finalFilename)
    }

    public func epubCacheURL(for documentID: UUID, in libraryURL: URL) -> URL {
        let cacheURL = url(for: .cache, in: libraryURL)
        return cacheURL.appendingPathComponent("EPUB", isDirectory: true)
            .appendingPathComponent(documentID.uuidString, isDirectory: true)
    }

    public func noteURL(for noteID: UUID, in libraryURL: URL) -> URL {
        let notesURL = url(for: .notes, in: libraryURL)
        return notesURL.appendingPathComponent("\(noteID.uuidString).md")
    }

    public func attachmentURL(for attachmentID: UUID, filename: String, in libraryURL: URL) -> URL {
        let attachmentsURL = url(for: .attachments, in: libraryURL)
        return attachmentsURL.appendingPathComponent(attachmentID.uuidString, isDirectory: true)
            .appendingPathComponent(filename)
    }

    /// Finds the actual PDF file in a document directory (for backward compatibility)
    /// Returns the first PDF file found in the directory, or nil if none exists
    public func findDocumentFile(for documentID: UUID, in libraryURL: URL) -> URL? {
        let pdfsURL = url(for: .pdfs, in: libraryURL)
        let documentDir = pdfsURL.appendingPathComponent(documentID.uuidString, isDirectory: true)

        do {
            let contents = try FileManager.default.contentsOfDirectory(at: documentDir, includingPropertiesForKeys: nil)
            return contents.first { $0.pathExtension.lowercased() == "pdf" }
        } catch {
            return nil
        }
    }

    /// Finds the actual EPUB file in a document directory (for backward compatibility)
    public func findEpubFile(for documentID: UUID, in libraryURL: URL) -> URL? {
        let epubsURL = url(for: .epubs, in: libraryURL)
        let documentDir = epubsURL.appendingPathComponent(documentID.uuidString, isDirectory: true)

        do {
            let contents = try FileManager.default.contentsOfDirectory(at: documentDir, includingPropertiesForKeys: nil)
            return contents.first { $0.pathExtension.lowercased() == "epub" }
        } catch {
            return nil
        }
    }

    /// Resolves the current on-disk location for a document when a stored URL is missing or stale.
    public func resolveDocumentFile(
        for documentID: UUID,
        preferredURL: URL?,
        documentType: String?,
        in libraryURL: URL
    ) -> URL? {
        if let preferredURL, fileManager.fileExists(atPath: preferredURL.path) {
            return preferredURL
        }

        let normalizedType = documentType?.lowercased()
        switch normalizedType {
        case "epub":
            return findEpubFile(for: documentID, in: libraryURL)
                ?? findDocumentFile(for: documentID, in: libraryURL)
        case "pdf":
            return findDocumentFile(for: documentID, in: libraryURL)
                ?? findEpubFile(for: documentID, in: libraryURL)
        default:
            return findDocumentFile(for: documentID, in: libraryURL)
                ?? findEpubFile(for: documentID, in: libraryURL)
        }
    }

    /// Renames a document file from generic "document.pdf" to a meaningful filename
    /// Returns the new URL if successful, or nil if the rename failed
    public func renameDocumentFile(documentID: UUID, to newName: String, in libraryURL: URL) -> URL? {
        guard let currentURL = findDocumentFile(for: documentID, in: libraryURL) else {
            logger.error("Cannot find document file for ID: \(documentID)")
            return nil
        }

        // If it's already using a meaningful name (not "document.pdf"), skip
        if currentURL.lastPathComponent != "document.pdf" {
            logger.info("Document already has meaningful name: \(currentURL.lastPathComponent)")
            return currentURL
        }

        let sanitizedName = sanitizeFilename(newName, withExtension: "pdf")
        let newURL = currentURL.deletingLastPathComponent().appendingPathComponent(sanitizedName)

        // If the new name is the same as current, no need to rename
        if newURL == currentURL {
            return currentURL
        }

        do {
            try FileManager.default.moveItem(at: currentURL, to: newURL)
            logger.info("Renamed document from \(currentURL.lastPathComponent) to \(sanitizedName)")
            return newURL
        } catch {
            logger.error("Failed to rename document: \(error.localizedDescription)")
            return nil
        }
    }

    /// Renames an EPUB file from generic "document.epub" to a meaningful filename
    public func renameEpubFile(documentID: UUID, to newName: String, in libraryURL: URL) -> URL? {
        guard let currentURL = findEpubFile(for: documentID, in: libraryURL) else {
            logger.error("Cannot find EPUB file for ID: \(documentID)")
            return nil
        }

        // If it's already using a meaningful name (not "document.epub"), skip
        if currentURL.lastPathComponent != "document.epub" {
            logger.info("EPUB already has meaningful name: \(currentURL.lastPathComponent)")
            return currentURL
        }

        let sanitizedName = sanitizeFilename(newName, withExtension: "epub")
        let newURL = currentURL.deletingLastPathComponent().appendingPathComponent(sanitizedName)

        // If the new name is the same as current, no need to rename
        if newURL == currentURL {
            return currentURL
        }

        do {
            try FileManager.default.moveItem(at: currentURL, to: newURL)
            logger.info("Renamed EPUB from \(currentURL.lastPathComponent) to \(sanitizedName)")
            return newURL
        } catch {
            logger.error("Failed to rename EPUB: \(error.localizedDescription)")
            return nil
        }
    }

    /// Deletes all library-managed assets for a document, including its stored file,
    /// extracted EPUB cache, and thumbnail.
    public func deleteStoredDocumentAssets(
        for documentID: UUID,
        preferredFileURL: URL?,
        in libraryURL: URL
    ) throws {
        let pdfDirectoryURL = url(for: .pdfs, in: libraryURL)
            .appendingPathComponent(documentID.uuidString, isDirectory: true)
        let epubDirectoryURL = url(for: .epubs, in: libraryURL)
            .appendingPathComponent(documentID.uuidString, isDirectory: true)
        let epubCacheDirectoryURL = epubCacheURL(for: documentID, in: libraryURL)
        let thumbnailFileURL = thumbnailURL(for: documentID, in: libraryURL)

        var urlsToDelete: [URL] = [pdfDirectoryURL, epubDirectoryURL, epubCacheDirectoryURL, thumbnailFileURL]

        if let preferredFileURL,
           preferredFileURL.path.hasPrefix(libraryURL.path),
           !urlsToDelete.contains(preferredFileURL) {
            urlsToDelete.append(preferredFileURL)
        }

        for url in urlsToDelete {
            guard fileManager.fileExists(atPath: url.path) else { continue }
            do {
                try fileManager.removeItem(at: url)
                logger.info("Deleted stored asset at \(url.path)")
            } catch {
                logger.error("Failed to delete stored asset at \(url.path): \(error.localizedDescription)")
                throw error
            }
        }
    }

    public func thumbnailURL(for documentID: UUID, in libraryURL: URL) -> URL {
        let indexURL = url(for: .index, in: libraryURL)
        return indexURL.appendingPathComponent("Thumbnails", isDirectory: true)
            .appendingPathComponent("\(documentID.uuidString).png")
    }

    public func restorePersistedBookmark() async throws -> URL? {
        guard let data = defaults.data(forKey: Keys.libraryBookmark) else {
            return nil
        }

        var isStale = false
        #if os(macOS)
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        #else
        let url = try URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        #endif

        if isStale {
            logger.info("Bookmark was stale, refreshing")
            try persistBookmark(for: url)
        }

        return url
    }

    /// Returns the default library URL for iPadOS (inside the app's Documents directory).
    public func defaultiPadLibraryURL() -> URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents.appendingPathComponent("Library", isDirectory: true)
    }

    public func clearBookmark() {
        defaults.removeObject(forKey: Keys.libraryBookmark)
        logger.info("Cleared persisted library bookmark")
    }
}
