import Foundation

/// Pass/fail performance budgets for the next ship, keyed by benchmark library profile.
public struct PerformanceBudget: Sendable {
    public let metric: PerformanceMetric
    public let profile: BenchmarkLibraryProfile
    /// Maximum allowed duration in milliseconds.
    public let maxMilliseconds: Double

    public init(metric: PerformanceMetric, profile: BenchmarkLibraryProfile, maxMilliseconds: Double) {
        self.metric = metric
        self.profile = profile
        self.maxMilliseconds = maxMilliseconds
    }

    public func evaluate(durationMilliseconds: Double) -> PerformanceBudgetResult {
        let passed = durationMilliseconds <= maxMilliseconds
        return PerformanceBudgetResult(
            metric: metric,
            profile: profile,
            durationMilliseconds: durationMilliseconds,
            budgetMilliseconds: maxMilliseconds,
            passed: passed
        )
    }

    /// Default budgets for the optimisation release.
    public static let defaults: [PerformanceBudget] = [
        // App launch — time from process start to first interactive frame
        PerformanceBudget(metric: .appLaunch, profile: .small, maxMilliseconds: 1_500),
        PerformanceBudget(metric: .appLaunch, profile: .medium, maxMilliseconds: 2_500),
        PerformanceBudget(metric: .appLaunch, profile: .large, maxMilliseconds: 4_000),

        // Library bootstrap — bookmark restore through initial data load
        PerformanceBudget(metric: .libraryBootstrap, profile: .small, maxMilliseconds: 800),
        PerformanceBudget(metric: .libraryBootstrap, profile: .medium, maxMilliseconds: 1_500),
        PerformanceBudget(metric: .libraryBootstrap, profile: .large, maxMilliseconds: 3_000),

        // List refresh — single-item mutation to UI update (target after Milestone 1)
        PerformanceBudget(metric: .listRefresh, profile: .small, maxMilliseconds: 50),
        PerformanceBudget(metric: .listRefresh, profile: .medium, maxMilliseconds: 100),
        PerformanceBudget(metric: .listRefresh, profile: .large, maxMilliseconds: 200),

        // Document open — selection to PDF visible
        PerformanceBudget(metric: .documentOpen, profile: .small, maxMilliseconds: 500),
        PerformanceBudget(metric: .documentOpen, profile: .medium, maxMilliseconds: 800),
        PerformanceBudget(metric: .documentOpen, profile: .large, maxMilliseconds: 1_200),

        // Annotation update — create/update/delete to UI reflect
        PerformanceBudget(metric: .annotationUpdate, profile: .small, maxMilliseconds: 100),
        PerformanceBudget(metric: .annotationUpdate, profile: .medium, maxMilliseconds: 150),
        PerformanceBudget(metric: .annotationUpdate, profile: .large, maxMilliseconds: 200),

        // Content search — query submit to first results (legacy brute-force baseline)
        PerformanceBudget(metric: .contentSearch, profile: .small, maxMilliseconds: 1_000),
        PerformanceBudget(metric: .contentSearch, profile: .medium, maxMilliseconds: 5_000),
        PerformanceBudget(metric: .contentSearch, profile: .large, maxMilliseconds: 15_000),

        // Import — single PDF end-to-end
        PerformanceBudget(metric: .importBatch, profile: .small, maxMilliseconds: 2_000),
        PerformanceBudget(metric: .importBatch, profile: .medium, maxMilliseconds: 3_000),
        PerformanceBudget(metric: .importBatch, profile: .large, maxMilliseconds: 5_000),

        // Thumbnail generation — single PDF
        PerformanceBudget(metric: .thumbnailGeneration, profile: .small, maxMilliseconds: 500),
        PerformanceBudget(metric: .thumbnailGeneration, profile: .medium, maxMilliseconds: 800),
        PerformanceBudget(metric: .thumbnailGeneration, profile: .large, maxMilliseconds: 1_200),
    ]

    public static func budget(for metric: PerformanceMetric, profile: BenchmarkLibraryProfile) -> PerformanceBudget? {
        defaults.first { $0.metric == metric && $0.profile == profile }
    }
}

public struct PerformanceBudgetResult: Sendable {
    public let metric: PerformanceMetric
    public let profile: BenchmarkLibraryProfile
    public let durationMilliseconds: Double
    public let budgetMilliseconds: Double
    public let passed: Bool
}
