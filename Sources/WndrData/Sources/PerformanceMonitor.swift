import Foundation
import OSLog

/// Records timing measurements and evaluates them against performance budgets.
@MainActor
public final class PerformanceMonitor: ObservableObject {
    public static let shared = PerformanceMonitor()

    private let logger = WndrLogger(category: "performance")
    private let signposter = OSSignposter(subsystem: "com.wndr.app", category: "performance")
    private var activeIntervals: [PerformanceMetric: (state: OSSignpostIntervalState, startTime: CFAbsoluteTime)] = [:]
    private var launchStartTime: CFAbsoluteTime?
    private(set) public var recordedMeasurements: [PerformanceMeasurement] = []

    @Published public private(set) var activeProfile: BenchmarkLibraryProfile = .small

    private init() {}

    // MARK: - Profile

    /// Updates the active benchmark profile based on library item counts.
    public func updateProfile(documentCount: Int, noteCount: Int) {
        let total = documentCount + noteCount
        if total >= BenchmarkLibraryProfile.large.documentCount.lowerBound {
            activeProfile = .large
        } else if total >= BenchmarkLibraryProfile.medium.documentCount.lowerBound {
            activeProfile = .medium
        } else {
            activeProfile = .small
        }
    }

    // MARK: - Launch Tracking

    public func markLaunchStart() {
        launchStartTime = CFAbsoluteTimeGetCurrent()
    }

    public func markLaunchComplete() {
        guard let start = launchStartTime else { return }
        let durationMs = (CFAbsoluteTimeGetCurrent() - start) * 1_000
        recordDuration(durationMs, for: .appLaunch)
        launchStartTime = nil
    }

    // MARK: - Interval Measurement

    @discardableResult
    public func begin(_ metric: PerformanceMetric) -> PerformanceMetric {
        let state = signposter.beginInterval("PerformanceInterval", id: signposter.makeSignpostID(), "\(metric.rawValue)")
        activeIntervals[metric] = (state, CFAbsoluteTimeGetCurrent())
        return metric
    }

    public func end(_ metric: PerformanceMetric, metadata: [String: String] = [:]) {
        guard let interval = activeIntervals.removeValue(forKey: metric) else { return }
        signposter.endInterval("PerformanceInterval", interval.state)
        let durationMs = (CFAbsoluteTimeGetCurrent() - interval.startTime) * 1_000
        recordDuration(durationMs, for: metric, metadata: metadata)
    }

    /// Measures a synchronous block and records the result.
    @discardableResult
    public func measure<T>(
        _ metric: PerformanceMetric,
        metadata: [String: String] = [:],
        _ work: () throws -> T
    ) rethrows -> T {
        begin(metric)
        defer { end(metric, metadata: metadata) }
        return try work()
    }

    /// Measures an async block and records the result.
    @discardableResult
    public func measure<T>(
        _ metric: PerformanceMetric,
        metadata: [String: String] = [:],
        _ work: () async throws -> T
    ) async rethrows -> T {
        begin(metric)
        defer { end(metric, metadata: metadata) }
        return try await work()
    }

    // MARK: - Recording

    public func recordDuration(
        _ durationMilliseconds: Double,
        for metric: PerformanceMetric,
        metadata: [String: String] = [:]
    ) {
        let budgetResult = PerformanceBudget.budget(for: metric, profile: activeProfile)?
            .evaluate(durationMilliseconds: durationMilliseconds)

        let measurement = PerformanceMeasurement(
            metric: metric,
            durationMilliseconds: durationMilliseconds,
            profile: activeProfile,
            metadata: metadata,
            budgetResult: budgetResult
        )
        recordedMeasurements.append(measurement)

        var logMessage = "\(metric.rawValue)=\(String(format: "%.1f", durationMilliseconds))ms profile=\(activeProfile.rawValue)"
        if !metadata.isEmpty {
            let meta = metadata.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            logMessage += " \(meta)"
        }
        if let budgetResult {
            logMessage += budgetResult.passed ? " PASS" : " FAIL(budget=\(Int(budgetResult.budgetMilliseconds))ms)"
            if !budgetResult.passed {
                logger.error(logMessage)
                return
            }
        }
        logger.info(logMessage)
    }

    public func clearRecordedMeasurements() {
        recordedMeasurements.removeAll()
    }
}

public struct PerformanceMeasurement: Identifiable, Sendable {
    public let id = UUID()
    public let metric: PerformanceMetric
    public let durationMilliseconds: Double
    public let profile: BenchmarkLibraryProfile
    public let metadata: [String: String]
    public let budgetResult: PerformanceBudgetResult?
    public let recordedAt: Date

    init(
        metric: PerformanceMetric,
        durationMilliseconds: Double,
        profile: BenchmarkLibraryProfile,
        metadata: [String: String],
        budgetResult: PerformanceBudgetResult?,
        recordedAt: Date = Date()
    ) {
        self.metric = metric
        self.durationMilliseconds = durationMilliseconds
        self.profile = profile
        self.metadata = metadata
        self.budgetResult = budgetResult
        self.recordedAt = recordedAt
    }
}
