import Foundation

public enum WndrData {
    public static let persistenceController = PersistenceController.shared

    public static func makeBackgroundContext() -> PersistenceController.Context {
        persistenceController.newBackgroundContext()
    }
}
