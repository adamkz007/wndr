import Foundation
import Combine

public struct FeatureFlag: Identifiable, Hashable {
    public enum Availability {
        case enabled
        case disabled
        case requiresRestart
    }

    public let id: String
    public var title: String
    public var description: String
    public var availability: Availability

    public init(
        id: String,
        title: String,
        description: String,
        availability: Availability = .enabled
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.availability = availability
    }
}

public final class FeatureFlagStore: ObservableObject {
    private enum Keys {
        static func key(for flag: FeatureFlag) -> String { "feature.flag.\(flag.id)" }
    }

    private let defaults: UserDefaults
    @Published private(set) var overrides: [String: Bool]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.overrides = defaults.dictionaryRepresentation()
            .filter { $0.key.starts(with: "feature.flag.") }
            .compactMapValues { $0 as? Bool }
    }

    public func isEnabled(_ flag: FeatureFlag, default defaultValue: Bool = false) -> Bool {
        if let override = overrides[flag.id] {
            return override
        }
        return defaultValue
    }

    @MainActor
    public func setEnabled(_ enabled: Bool, for flag: FeatureFlag) {
        overrides[flag.id] = enabled
        defaults.set(enabled, forKey: Keys.key(for: flag))
    }

    @MainActor
    public func reset(_ flag: FeatureFlag) {
        overrides.removeValue(forKey: flag.id)
        defaults.removeObject(forKey: Keys.key(for: flag))
    }
}
