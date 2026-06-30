import Foundation

/// Describes repeatable benchmark library sizes for performance regression testing.
public enum BenchmarkLibraryProfile: String, CaseIterable, Sendable {
    case small
    case medium
    case large

    public var documentCount: ClosedRange<Int> {
        switch self {
        case .small: return 10...25
        case .medium: return 100...250
        case .large: return 1_000...2_500
        }
    }

    public var noteCount: ClosedRange<Int> {
        switch self {
        case .small: return 5...15
        case .medium: return 50...150
        case .large: return 500...1_000
        }
    }

    public var tagCount: ClosedRange<Int> {
        switch self {
        case .small: return 3...8
        case .medium: return 10...30
        case .large: return 30...80
        }
    }

    public var collectionCount: ClosedRange<Int> {
        switch self {
        case .small: return 2...5
        case .medium: return 5...15
        case .large: return 15...40
        }
    }

    public var description: String {
        switch self {
        case .small:
            return "Small library (\(documentCount.lowerBound)–\(documentCount.upperBound) PDFs, \(noteCount.lowerBound)–\(noteCount.upperBound) notes)"
        case .medium:
            return "Medium library (\(documentCount.lowerBound)–\(documentCount.upperBound) PDFs, \(noteCount.lowerBound)–\(noteCount.upperBound) notes)"
        case .large:
            return "Large library (\(documentCount.lowerBound)–\(documentCount.upperBound) PDFs, \(noteCount.lowerBound)–\(noteCount.upperBound) notes)"
        }
    }
}
