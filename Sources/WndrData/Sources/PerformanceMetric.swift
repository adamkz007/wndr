import Foundation

/// Named performance measurements tracked across the app.
public enum PerformanceMetric: String, CaseIterable, Sendable {
    case appLaunch = "app_launch"
    case libraryBootstrap = "library_bootstrap"
    case listRefresh = "list_refresh"
    case documentOpen = "document_open"
    case annotationUpdate = "annotation_update"
    case contentSearch = "content_search"
    case importBatch = "import_batch"
    case thumbnailGeneration = "thumbnail_generation"
}
