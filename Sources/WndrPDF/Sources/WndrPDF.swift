import Combine
import Foundation
import OSLog
import PDFKit

public final class PDFWorkspaceCoordinator: ObservableObject {
    private static let logger = Logger(subsystem: "com.wndr.pdf", category: "workspace")

    @Published public private(set) var document: PDFDocument?

    public init() {}

    public func openDocument(at url: URL) {
        guard let pdfDocument = PDFDocument(url: url) else {
            Self.logger.error("Failed to load PDF at \(url.path, privacy: .public)")
            return
        }
        document = pdfDocument
        Self.logger.debug("Loaded PDF document with \(pdfDocument.pageCount) pages")
    }
}
