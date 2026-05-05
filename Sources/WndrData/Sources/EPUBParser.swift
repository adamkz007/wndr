import Compression
import Foundation

// MARK: - EPUB Data Models

/// Represents a fully parsed EPUB book ready for rendering.
public struct EPUBBook {
    public let metadata: EPUBMetadata
    public let spine: [EPUBSpineItem]
    public let manifest: [String: EPUBManifestItem]
    public let extractedURL: URL
    public let opfDirectory: String

    /// Resolves a spine item's href to a full filesystem URL.
    public func resolvedURL(for spineItem: EPUBSpineItem) -> URL {
        if opfDirectory.isEmpty {
            return extractedURL.appendingPathComponent(spineItem.href)
        }
        return extractedURL.appendingPathComponent(opfDirectory)
            .appendingPathComponent(spineItem.href)
    }

    /// Resolves any relative path within the EPUB.
    public func resolvedURL(for relativePath: String) -> URL {
        if opfDirectory.isEmpty {
            return extractedURL.appendingPathComponent(relativePath)
        }
        return extractedURL.appendingPathComponent(opfDirectory)
            .appendingPathComponent(relativePath)
    }
}

public struct EPUBMetadata {
    public var title: String?
    public var authors: [String]
    public var language: String?
    public var publisher: String?
    public var description: String?
    public var coverImagePath: String?
    public var identifier: String?
    public var date: String?

    public init(
        title: String? = nil,
        authors: [String] = [],
        language: String? = nil,
        publisher: String? = nil,
        description: String? = nil,
        coverImagePath: String? = nil,
        identifier: String? = nil,
        date: String? = nil
    ) {
        self.title = title
        self.authors = authors
        self.language = language
        self.publisher = publisher
        self.description = description
        self.coverImagePath = coverImagePath
        self.identifier = identifier
        self.date = date
    }
}

public struct EPUBSpineItem: Identifiable {
    public let id: String
    public let href: String
    public var title: String?
    public let index: Int
}

public struct EPUBManifestItem {
    public let id: String
    public let href: String
    public let mediaType: String
}

// MARK: - EPUB Errors

public enum EPUBError: LocalizedError {
    case invalidZIPFile
    case corruptEntry(String)
    case decompressionFailed(String)
    case invalidEPUBStructure(String)
    case missingContent(String)
    case extractionFailed(String)
    case xmlParsingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidZIPFile:
            return "Not a valid ZIP/EPUB file"
        case .corruptEntry(let path):
            return "Corrupt ZIP entry: \(path)"
        case .decompressionFailed(let detail):
            return "Decompression failed: \(detail)"
        case .invalidEPUBStructure(let detail):
            return "Invalid EPUB structure: \(detail)"
        case .missingContent(let path):
            return "Missing EPUB content: \(path)"
        case .extractionFailed(let detail):
            return "EPUB extraction failed: \(detail)"
        case .xmlParsingFailed(let detail):
            return "XML parsing failed: \(detail)"
        }
    }
}

// MARK: - ZIP Reader (Pure Swift, cross-platform)

/// Minimal ZIP archive reader using Apple's Compression framework for DEFLATE.
private struct ZIPReader {
    // ZIP signatures
    private static let eocdSignature: UInt32 = 0x06054b50
    private static let centralDirSignature: UInt32 = 0x02014b50
    private static let localFileSignature: UInt32 = 0x04034b50

    struct Entry {
        let path: String
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let compressionMethod: UInt16
        let localHeaderOffset: UInt32
    }

    private let data: Data

    init(data: Data) throws {
        guard data.count >= 22 else {
            throw EPUBError.invalidZIPFile
        }

        // Quick check: ZIP files should start with "PK" (0x504B)
        if data.count >= 2 {
            let firstTwo = data.prefix(2)
            if firstTwo[0] != 0x50 || firstTwo[1] != 0x4B {
                throw EPUBError.invalidZIPFile
            }
        }

        self.data = data
    }

    init(contentsOf url: URL) throws {
        let fileData: Data
        do {
            fileData = try Data(contentsOf: url)
        } catch {
            throw EPUBError.extractionFailed("Failed to read file: \(error.localizedDescription)")
        }

        guard fileData.count >= 22 else {
            throw EPUBError.invalidZIPFile
        }

        // Quick check: ZIP files should start with "PK" (0x504B)
        if fileData.count >= 2 {
            let firstTwo = fileData.prefix(2)
            if firstTwo[0] != 0x50 || firstTwo[1] != 0x4B {
                throw EPUBError.invalidEPUBStructure("File does not appear to be a ZIP/EPUB file (missing PK signature)")
            }
        }

        self.data = fileData
    }

    /// Extract all files to a destination directory.
    func extractAll(to destination: URL) throws {
        let entries = try readCentralDirectory()
        let fm = FileManager.default

        for entry in entries {
            // Skip directories
            guard !entry.path.hasSuffix("/") else {
                let dirURL = destination.appendingPathComponent(entry.path, isDirectory: true)
                try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
                continue
            }

            let fileData = try extractEntry(entry)
            let fileURL = destination.appendingPathComponent(entry.path)

            // Create parent directories
            let parentDir = fileURL.deletingLastPathComponent()
            if !fm.fileExists(atPath: parentDir.path) {
                try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }

            try fileData.write(to: fileURL)
        }
    }

    /// Extract a single file by path.
    func extractFile(at path: String) throws -> Data {
        let entries = try readCentralDirectory()
        guard let entry = entries.first(where: { $0.path == path }) else {
            throw EPUBError.missingContent(path)
        }
        return try extractEntry(entry)
    }

    // MARK: - Private

    private func readCentralDirectory() throws -> [Entry] {
        // Find End of Central Directory record (search from end)
        guard let eocdOffset = findEOCD() else {
            throw EPUBError.invalidEPUBStructure("Could not find End of Central Directory record")
        }

        // Validate EOCD offset
        guard eocdOffset + 22 <= data.count else {
            throw EPUBError.invalidEPUBStructure("Invalid EOCD offset: \(eocdOffset) in file of size \(data.count)")
        }

        // Parse EOCD
        guard let totalEntries = readUInt16(at: eocdOffset + 10),
              let centralDirOffset = readUInt32(at: eocdOffset + 16) else {
            throw EPUBError.invalidEPUBStructure("Could not read EOCD values at offset \(eocdOffset)")
        }

        // Validate values (allow 0 entries for empty archives, but not more than reasonable)
        guard totalEntries < 10000 else {
            throw EPUBError.invalidZIPFile
        }

        // If no entries, return empty array
        if totalEntries == 0 {
            return []
        }

        // Validate central directory offset
        guard centralDirOffset > 0 && Int(centralDirOffset) < data.count - 46 else {
            throw EPUBError.invalidZIPFile
        }

        // Parse central directory entries
        var entries: [Entry] = []
        var offset = Int(centralDirOffset)

        for _ in 0..<totalEntries {
            guard offset + 46 <= data.count else { break }

            guard let sig = readUInt32(at: offset),
                  sig == Self.centralDirSignature,
                  let compressionMethod = readUInt16(at: offset + 10),
                  let compressedSize = readUInt32(at: offset + 20),
                  let uncompressedSize = readUInt32(at: offset + 24),
                  let fileNameLengthU16 = readUInt16(at: offset + 28),
                  let extraFieldLengthU16 = readUInt16(at: offset + 30),
                  let fileCommentLengthU16 = readUInt16(at: offset + 32),
                  let localHeaderOffset = readUInt32(at: offset + 42) else {
                // If we can't read the central directory entry properly, stop parsing
                break
            }

            let fileNameLength = Int(fileNameLengthU16)
            let extraFieldLength = Int(extraFieldLengthU16)
            let fileCommentLength = Int(fileCommentLengthU16)

            let nameStart = offset + 46
            guard nameStart + fileNameLength <= data.count else { break }
            let nameData = data[nameStart..<(nameStart + fileNameLength)]
            let path = String(data: nameData, encoding: .utf8) ?? ""

            entries.append(Entry(
                path: path,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                compressionMethod: compressionMethod,
                localHeaderOffset: localHeaderOffset
            ))

            offset = nameStart + fileNameLength + extraFieldLength + fileCommentLength
        }

        return entries
    }

    private func extractEntry(_ entry: Entry) throws -> Data {
        let localOffset = Int(entry.localHeaderOffset)
        guard localOffset + 30 <= data.count else {
            throw EPUBError.corruptEntry(entry.path)
        }

        guard let sig = readUInt32(at: localOffset),
              sig == Self.localFileSignature,
              let localFileNameLengthU16 = readUInt16(at: localOffset + 26),
              let localExtraLengthU16 = readUInt16(at: localOffset + 28) else {
            throw EPUBError.corruptEntry(entry.path)
        }

        let localFileNameLength = Int(localFileNameLengthU16)
        let localExtraLength = Int(localExtraLengthU16)
        let dataStart = localOffset + 30 + localFileNameLength + localExtraLength
        let compressedSize = Int(entry.compressedSize)

        guard dataStart + compressedSize <= data.count else {
            throw EPUBError.corruptEntry(entry.path)
        }

        let compressedData = data[dataStart..<(dataStart + compressedSize)]

        switch entry.compressionMethod {
        case 0: // Stored (no compression)
            return Data(compressedData)

        case 8: // Deflate
            return try decompressDeflate(
                Data(compressedData),
                uncompressedSize: Int(entry.uncompressedSize),
                path: entry.path
            )

        default:
            throw EPUBError.decompressionFailed(
                "Unsupported compression method \(entry.compressionMethod) for \(entry.path)"
            )
        }
    }

    private func decompressDeflate(_ compressed: Data, uncompressedSize: Int, path: String) throws -> Data {
        guard uncompressedSize > 0 else { return Data() }

        // Allocate output buffer with some headroom
        let bufferSize = max(uncompressedSize, compressed.count * 4)
        let outputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { outputBuffer.deallocate() }

        let decompressedSize = compressed.withUnsafeBytes { inputBuffer -> Int in
            guard let baseAddress = inputBuffer.baseAddress else { return 0 }
            return compression_decode_buffer(
                outputBuffer,
                bufferSize,
                baseAddress.assumingMemoryBound(to: UInt8.self),
                compressed.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard decompressedSize > 0 else {
            throw EPUBError.decompressionFailed("Failed to decompress \(path)")
        }

        return Data(bytes: outputBuffer, count: decompressedSize)
    }

    private func findEOCD() -> Int? {
        // EOCD is at least 22 bytes and at most 22 + 65535 bytes from end
        let minEOCDSize = 22
        guard data.count >= minEOCDSize else { return nil }

        // Limit search to last 64KB + 22 bytes (standard ZIP comment limit)
        let maxCommentSize = 65535
        let searchStart = max(0, data.count - maxCommentSize - minEOCDSize)
        let searchEnd = data.count - minEOCDSize

        // Search backwards for EOCD signature (more likely to be near the end)
        for i in stride(from: searchEnd, through: searchStart, by: -1) {
            // Check bounds before reading
            if i + 4 > data.count { continue }

            if let sig = readUInt32(at: i), sig == Self.eocdSignature {
                // Verify this is likely a valid EOCD by checking the comment length
                if i + 22 <= data.count {
                    if let commentLength = readUInt16(at: i + 20) {
                        if i + 22 + Int(commentLength) == data.count {
                            return i
                        }
                    }
                    // Even if comment length doesn't match perfectly, accept it
                    // Some ZIP files have incorrect comment lengths
                    return i
                }
            }
        }
        return nil
    }

    private func readUInt16(at offset: Int) -> UInt16? {
        guard offset >= 0 && offset + 2 <= data.count else {
            return nil
        }
        return data.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: offset, as: UInt16.self).littleEndian
        }
    }

    private func readUInt32(at offset: Int) -> UInt32? {
        guard offset >= 0 && offset + 4 <= data.count else {
            return nil
        }
        return data.withUnsafeBytes { buffer in
            buffer.load(fromByteOffset: offset, as: UInt32.self).littleEndian
        }
    }
}

// MARK: - EPUB Parser

public final class EPUBParser {
    private let fileManager = FileManager.default
    private let logger: WndrLogger

    public init(logger: WndrLogger = WndrLogger(category: "epub")) {
        self.logger = logger
    }

    /// Parse an EPUB file: extract contents and read structure.
    public func parse(epubURL: URL, extractTo destination: URL) throws -> EPUBBook {
        logger.info("Parsing EPUB: \(epubURL.lastPathComponent)")

        // 1. Extract ZIP contents
        try extractEPUB(from: epubURL, to: destination)

        // 2. Parse container.xml to find OPF path
        let containerURL = destination.appendingPathComponent("META-INF/container.xml")
        guard fileManager.fileExists(atPath: containerURL.path) else {
            throw EPUBError.invalidEPUBStructure("Missing META-INF/container.xml")
        }
        let containerData = try Data(contentsOf: containerURL)
        let opfPath = try parseContainerXML(data: containerData)
        logger.info("Found OPF at: \(opfPath)")

        // 3. Parse OPF file
        let opfURL = destination.appendingPathComponent(opfPath)
        guard fileManager.fileExists(atPath: opfURL.path) else {
            throw EPUBError.missingContent(opfPath)
        }
        let opfData = try Data(contentsOf: opfURL)
        let opfDirectory = (opfPath as NSString).deletingLastPathComponent

        let book = try parseOPF(data: opfData, opfDirectory: opfDirectory, extractedURL: destination)
        logger.info("Parsed EPUB: \"\(book.metadata.title ?? "Untitled")\" with \(book.spine.count) chapters")

        return book
    }

    /// Extract metadata only (without full extraction) for import.
    public func extractMetadata(from epubURL: URL) throws -> EPUBMetadata {
        logger.info("Extracting metadata from: \(epubURL.lastPathComponent)")
        logger.info("Full path: \(epubURL.path)")

        // Check if file exists and is readable
        let fm = FileManager.default
        guard fm.fileExists(atPath: epubURL.path) else {
            logger.error("EPUB file does not exist at path: \(epubURL.path)")
            throw EPUBError.invalidEPUBStructure("File not found")
        }

        guard fm.isReadableFile(atPath: epubURL.path) else {
            logger.error("EPUB file is not readable: \(epubURL.path)")
            throw EPUBError.invalidEPUBStructure("File not readable")
        }

        // Get file size for debugging
        if let attrs = try? fm.attributesOfItem(atPath: epubURL.path),
           let fileSize = attrs[.size] as? Int64 {
            logger.info("EPUB file size: \(fileSize) bytes")
        }

        do {
            let zipReader = try ZIPReader(contentsOf: epubURL)
            logger.info("Successfully created ZIP reader")

            // Read container.xml from ZIP
            let containerData = try zipReader.extractFile(at: "META-INF/container.xml")
            logger.info("Successfully extracted container.xml (\(containerData.count) bytes)")

            let opfPath = try parseContainerXML(data: containerData)
            logger.info("OPF path from container.xml: \(opfPath)")

            // Read OPF from ZIP
            let opfData = try zipReader.extractFile(at: opfPath)
            logger.info("Successfully extracted OPF file (\(opfData.count) bytes)")

            let metadata = try parseOPFMetadata(data: opfData)
            logger.info("Successfully parsed metadata - Title: \(metadata.title ?? "Unknown")")

            return metadata
        } catch {
            logger.error("Failed to extract EPUB metadata: \(error.localizedDescription)")
            throw error
        }
    }

    /// Extract the cover image data from an EPUB file.
    public func extractCoverImage(from epubURL: URL) throws -> Data? {
        let zipReader = try ZIPReader(contentsOf: epubURL)

        // Read container.xml
        let containerData = try zipReader.extractFile(at: "META-INF/container.xml")
        let opfPath = try parseContainerXML(data: containerData)
        let opfDirectory = (opfPath as NSString).deletingLastPathComponent

        // Read OPF
        let opfData = try zipReader.extractFile(at: opfPath)
        let metadata = try parseOPFMetadata(data: opfData)

        // Try to get cover image path
        guard let coverPath = metadata.coverImagePath else { return nil }

        let fullCoverPath: String
        if opfDirectory.isEmpty {
            fullCoverPath = coverPath
        } else {
            fullCoverPath = "\(opfDirectory)/\(coverPath)"
        }

        return try? zipReader.extractFile(at: fullCoverPath)
    }

    // MARK: - Private

    private func extractEPUB(from sourceURL: URL, to destination: URL) throws {
        // Create destination if needed
        if !fileManager.fileExists(atPath: destination.path) {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        }

        let zipReader = try ZIPReader(contentsOf: sourceURL)
        try zipReader.extractAll(to: destination)
        logger.info("Extracted EPUB to: \(destination.path)")
    }

    // MARK: - XML Parsing

    /// Parse container.xml to find the OPF file path.
    private func parseContainerXML(data: Data) throws -> String {
        let delegate = ContainerXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()

        guard let opfPath = delegate.opfPath else {
            throw EPUBError.invalidEPUBStructure("Could not find rootfile in container.xml")
        }
        return opfPath
    }

    /// Parse OPF metadata, manifest, and spine.
    private func parseOPF(data: Data, opfDirectory: String, extractedURL: URL) throws -> EPUBBook {
        let delegate = OPFXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()

        guard !delegate.spineItemRefs.isEmpty else {
            throw EPUBError.invalidEPUBStructure("Empty spine in OPF")
        }

        // Build manifest dictionary
        var manifest: [String: EPUBManifestItem] = [:]
        for item in delegate.manifestItems {
            manifest[item.id] = item
        }

        // Build spine from spine references
        var spine: [EPUBSpineItem] = []
        for (index, idref) in delegate.spineItemRefs.enumerated() {
            guard let manifestItem = manifest[idref] else { continue }
            spine.append(EPUBSpineItem(
                id: idref,
                href: manifestItem.href,
                title: nil, // Will be populated from TOC if available
                index: index
            ))
        }

        // Try to populate chapter titles from TOC
        if let tocID = delegate.tocID, let tocItem = manifest[tocID] {
            let tocURL: URL
            if opfDirectory.isEmpty {
                tocURL = extractedURL.appendingPathComponent(tocItem.href)
            } else {
                tocURL = extractedURL.appendingPathComponent(opfDirectory)
                    .appendingPathComponent(tocItem.href)
            }
            if let tocData = try? Data(contentsOf: tocURL) {
                let titles = parseTOC(data: tocData, mediaType: tocItem.mediaType)
                for i in 0..<spine.count {
                    let href = spine[i].href
                    // Match by href (strip fragment identifier)
                    let baseHref = href.components(separatedBy: "#").first ?? href
                    if let title = titles[baseHref] {
                        spine[i].title = title
                    }
                }
            }
        }

        // If no chapter titles, generate default names
        for i in 0..<spine.count where spine[i].title == nil {
            spine[i].title = "Chapter \(i + 1)"
        }

        return EPUBBook(
            metadata: delegate.metadata,
            spine: spine,
            manifest: manifest,
            extractedURL: extractedURL,
            opfDirectory: opfDirectory
        )
    }

    /// Parse OPF for metadata only.
    private func parseOPFMetadata(data: Data) throws -> EPUBMetadata {
        let delegate = OPFXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.metadata
    }

    /// Parse NCX or XHTML TOC to get chapter titles.
    private func parseTOC(data: Data, mediaType: String) -> [String: String] {
        let delegate = TOCXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.titles // href -> title mapping
    }
}

// MARK: - XML Parser Delegates

/// Parses container.xml to extract the OPF file path.
private class ContainerXMLDelegate: NSObject, XMLParserDelegate {
    var opfPath: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        if elementName == "rootfile" || elementName.hasSuffix(":rootfile") {
            opfPath = attributes["full-path"]
        }
    }
}

/// Parses the OPF file for metadata, manifest, and spine.
private class OPFXMLDelegate: NSObject, XMLParserDelegate {
    var metadata = EPUBMetadata()
    var manifestItems: [EPUBManifestItem] = []
    var spineItemRefs: [String] = []
    var tocID: String?

    private var currentElement = ""
    private var currentText = ""
    private var inMetadata = false
    private var coverImageID: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName
        currentElement = localName
        currentText = ""

        switch localName {
        case "metadata":
            inMetadata = true

        case "item":
            if let id = attributes["id"],
               let href = attributes["href"],
               let mediaType = attributes["media-type"] {
                manifestItems.append(EPUBManifestItem(id: id, href: href, mediaType: mediaType))

                // Check for cover image
                if let properties = attributes["properties"], properties.contains("cover-image") {
                    metadata.coverImagePath = href
                }
            }

        case "itemref":
            if let idref = attributes["idref"] {
                spineItemRefs.append(idref)
            }

        case "spine":
            tocID = attributes["toc"]

        case "meta":
            if inMetadata {
                // OPF2 cover meta element: <meta name="cover" content="cover-image-id"/>
                if attributes["name"] == "cover", let content = attributes["content"] {
                    coverImageID = content
                }
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if inMetadata && !text.isEmpty {
            switch localName {
            case "title":
                metadata.title = text
            case "creator":
                metadata.authors.append(text)
            case "language":
                metadata.language = text
            case "publisher":
                metadata.publisher = text
            case "description":
                metadata.description = text
            case "identifier":
                metadata.identifier = text
            case "date":
                metadata.date = text
            default:
                break
            }
        }

        if localName == "metadata" {
            inMetadata = false

            // Resolve cover image path from manifest if found via OPF2 meta
            if metadata.coverImagePath == nil, let coverID = coverImageID {
                metadata.coverImagePath = manifestItems.first(where: { $0.id == coverID })?.href
            }
        }
    }
}

/// Parses NCX or XHTML navigation TOC to map chapter hrefs to titles.
private class TOCXMLDelegate: NSObject, XMLParserDelegate {
    var titles: [String: String] = [:] // href -> title

    private var currentElement = ""
    private var currentText = ""
    private var currentNavPointHref: String?
    private var currentTitle: String?
    private var inNavLabel = false
    private var inText = false
    private var inNavPoint = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName
        currentElement = localName
        currentText = ""

        switch localName {
        case "navPoint":
            inNavPoint = true
            currentNavPointHref = nil
            currentTitle = nil
        case "navLabel":
            inNavLabel = true
        case "text":
            inText = true
        case "content":
            if inNavPoint, let src = attributes["src"] {
                // Strip fragment identifier for matching
                currentNavPointHref = src.components(separatedBy: "#").first
            }
        case "a":
            // XHTML nav: <a href="chapter1.xhtml">Chapter 1</a>
            if let href = attributes["href"] {
                currentNavPointHref = href.components(separatedBy: "#").first
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch localName {
        case "text":
            if inNavLabel && !text.isEmpty {
                currentTitle = text
            }
            inText = false
        case "navLabel":
            inNavLabel = false
        case "navPoint":
            if let href = currentNavPointHref, let title = currentTitle {
                titles[href] = title
            }
            inNavPoint = false
        case "a":
            // XHTML nav
            if let href = currentNavPointHref, !text.isEmpty {
                titles[href] = text
            }
            currentNavPointHref = nil
        default:
            break
        }
    }
}
