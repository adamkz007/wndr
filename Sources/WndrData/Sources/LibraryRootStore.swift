import Foundation

public actor LibraryRootStore {
    public enum LibraryDirectory: String {
        case pdfs = "PDFs"
        case notes = "Notes"
        case attachments = "Attachments"
        case index = "Index"
        case cache = "Cache"

        var subdirectories: [String] {
            switch self {
            case .index:
                return ["Thumbnails"]
            case .cache:
                return ["OCR", "Previews"]
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
        let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bookmark, forKey: Keys.libraryBookmark)
        logger.info("Stored bookmark for \(url.path)")

        // Create directory structure
        try createLibraryStructure(at: url)

        return bookmark
    }

    public func createLibraryStructure(at libraryURL: URL) throws {
        let directories: [LibraryDirectory] = [.pdfs, .notes, .attachments, .index, .cache]

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

    private func uniqueFileURL(
        in directoryURL: URL,
        desiredFilename: String,
        excluding existingURL: URL? = nil
    ) -> URL {
        let desiredURL = directoryURL.appendingPathComponent(desiredFilename)
        if desiredURL == existingURL || !fileManager.fileExists(atPath: desiredURL.path) {
            return desiredURL
        }

        let baseName = desiredURL.deletingPathExtension().lastPathComponent
        let fileExtension = desiredURL.pathExtension
        var counter = 2

        while true {
            let candidateName = "\(baseName) (\(counter)).\(fileExtension)"
            let candidateURL = directoryURL.appendingPathComponent(candidateName)
            if candidateURL == existingURL || !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            counter += 1
        }
    }

    private func noteFilename(for title: String) -> String {
        sanitizeFilename(title, withExtension: "md")
    }

    private func extractNoteID(fromMarkdown markdown: String) -> UUID? {
        let lines = markdown.components(separatedBy: .newlines)
        guard !lines.isEmpty else { return nil }

        // Only parse YAML front matter at the top of the file.
        guard lines[0].trimmingCharacters(in: .whitespaces) == "---" else {
            return nil
        }

        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" {
                break
            }

            guard trimmed.hasPrefix("id:") else { continue }
            let value = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
            return UUID(uuidString: value)
        }

        return nil
    }

    public func documentURL(for documentID: UUID, in libraryURL: URL, filename: String? = nil) -> URL {
        let pdfsURL = url(for: .pdfs, in: libraryURL)
        let documentDir = pdfsURL.appendingPathComponent(documentID.uuidString, isDirectory: true)

        // Use provided filename or fall back to generic "document.pdf"
        let finalFilename = filename.map { sanitizeFilename($0, withExtension: "pdf") } ?? "document.pdf"
        return documentDir.appendingPathComponent(finalFilename)
    }

    public func noteURL(for noteID: UUID, in libraryURL: URL) -> URL {
        let notesURL = url(for: .notes, in: libraryURL)
        return notesURL.appendingPathComponent("\(noteID.uuidString).md")
    }

    public func noteURL(for noteID: UUID, title: String, in libraryURL: URL) -> URL {
        let notesURL = url(for: .notes, in: libraryURL)
        let existingURL = resolveNoteFile(for: noteID, in: libraryURL)
        let desiredFilename = noteFilename(for: title)
        return uniqueFileURL(in: notesURL, desiredFilename: desiredFilename, excluding: existingURL)
    }

    public func resolveNoteFile(for noteID: UUID, in libraryURL: URL) -> URL? {
        let notesURL = url(for: .notes, in: libraryURL)

        // Backward compatibility: legacy note files were named as <noteID>.md.
        let legacyURL = notesURL.appendingPathComponent("\(noteID.uuidString).md")
        if fileManager.fileExists(atPath: legacyURL.path) {
            return legacyURL
        }

        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: notesURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for fileURL in fileURLs where fileURL.pathExtension.lowercased() == "md" {
            guard let markdown = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            if extractNoteID(fromMarkdown: markdown) == noteID {
                return fileURL
            }
        }

        return nil
    }

    public func renameNoteFile(noteID: UUID, to newTitle: String, in libraryURL: URL) -> URL? {
        let notesURL = url(for: .notes, in: libraryURL)
        guard let currentURL = resolveNoteFile(for: noteID, in: libraryURL) else {
            return nil
        }

        let desiredFilename = noteFilename(for: newTitle)
        let destinationURL = uniqueFileURL(
            in: notesURL,
            desiredFilename: desiredFilename,
            excluding: currentURL
        )

        if destinationURL == currentURL {
            return currentURL
        }

        do {
            try fileManager.moveItem(at: currentURL, to: destinationURL)
            logger.info("Renamed note file from \(currentURL.lastPathComponent) to \(destinationURL.lastPathComponent)")
            return destinationURL
        } catch {
            logger.error("Failed to rename note file: \(error.localizedDescription)")
            return nil
        }
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
        if normalizedType == "pdf" || normalizedType == nil {
            return findDocumentFile(for: documentID, in: libraryURL)
        }
        return nil
    }

    private func renameStoredFile(
        currentURL: URL,
        to newName: String,
        withExtension ext: String,
        kind: String
    ) -> URL? {
        let sanitizedName = sanitizeFilename(newName, withExtension: ext)
        let newURL = currentURL.deletingLastPathComponent().appendingPathComponent(sanitizedName)

        if newURL == currentURL {
            return currentURL
        }

        guard !fileManager.fileExists(atPath: newURL.path) else {
            logger.error("Failed to rename \(kind): target already exists at \(newURL.path)")
            return nil
        }

        do {
            try fileManager.moveItem(at: currentURL, to: newURL)
            logger.info("Renamed \(kind) from \(currentURL.lastPathComponent) to \(sanitizedName)")
            return newURL
        } catch {
            logger.error("Failed to rename \(kind): \(error.localizedDescription)")
            return nil
        }
    }

    /// Renames a PDF file to match the current document title.
    public func renameDocumentFile(documentID: UUID, to newName: String, in libraryURL: URL) -> URL? {
        guard let currentURL = findDocumentFile(for: documentID, in: libraryURL) else {
            logger.error("Cannot find document file for ID: \(documentID)")
            return nil
        }

        return renameStoredFile(currentURL: currentURL, to: newName, withExtension: "pdf", kind: "document")
    }

    /// Deletes all library-managed assets for a document, including its stored file and thumbnail.
    public func deleteStoredDocumentAssets(
        for documentID: UUID,
        preferredFileURL: URL?,
        in libraryURL: URL
    ) throws {
        let pdfDirectoryURL = url(for: .pdfs, in: libraryURL)
            .appendingPathComponent(documentID.uuidString, isDirectory: true)
        let thumbnailFileURL = thumbnailURL(for: documentID, in: libraryURL)

        var urlsToDelete: [URL] = [pdfDirectoryURL, thumbnailFileURL]

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
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        if isStale {
            logger.info("Bookmark was stale, refreshing")
            try persistBookmark(for: url)
        }

        return url
    }

    public func clearBookmark() {
        defaults.removeObject(forKey: Keys.libraryBookmark)
        logger.info("Cleared persisted library bookmark")
    }
}
