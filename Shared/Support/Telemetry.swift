import Foundation
import OSLog

public struct TelemetryEvent: Equatable {
    public let name: String
    public var metadata: [String: String]

    public init(name: String, metadata: [String: String] = [:]) {
        self.name = name
        self.metadata = metadata
    }

    public static let librarySetupRequired = TelemetryEvent(name: "library_setup_required")
    public static let librarySelectionCancelled = TelemetryEvent(name: "library_selection_cancelled")
    public static let librarySelectionSucceeded = TelemetryEvent(name: "library_selection_succeeded")
}

public final class TelemetryClient {
    private let logger: WndrLogger
    private let queue = DispatchQueue(label: "com.wndr.telemetry", qos: .utility)

    public init(subsystem: String = "com.wndr.app", category: String = "telemetry") {
        self.logger = WndrLogger(subsystem: subsystem, category: category)
    }

    public func record(event: TelemetryEvent) {
        queue.async {
            let metadata = event.metadata.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            if metadata.isEmpty {
                self.logger.info("event=\(event.name)")
            } else {
                self.logger.info("event=\(event.name) metadata=\(metadata)")
            }
        }
    }

    public func record(_ error: Error) {
        queue.async {
            self.logger.error("error=\(error.localizedDescription)")
        }
    }
}
