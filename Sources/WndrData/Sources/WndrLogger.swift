import Foundation
import OSLog

public struct WndrLogger {
    private let logger: Logger

    public static let persistence = WndrLogger(category: "persistence")
    public static let libraryRoot = WndrLogger(category: "library")
    public static let telemetry = WndrLogger(category: "telemetry")

    public init(subsystem: String = "com.wndr.app", category: String) {
        logger = Logger(subsystem: subsystem, category: category)
    }

    public func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    public func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    public func fault(_ message: String) {
        logger.fault("\(message, privacy: .public)")
    }

    public func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
