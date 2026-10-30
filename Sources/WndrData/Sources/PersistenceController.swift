import CoreData
import Foundation

public final class PersistenceController {
    public typealias Context = NSManagedObjectContext

    public enum StoreError: LocalizedError {
        case modelMissing
        case loadFailed(URL, Error)

        public var errorDescription: String? {
            switch self {
            case .modelMissing:
                return "Wndr's data model is missing from the app bundle. Reinstall Wndr."
            case let .loadFailed(url, error):
                return "Wndr couldn't open the library database at \(url.path). \(error.localizedDescription)"
            }
        }
    }

    public static let shared = PersistenceController()

    /// Location of the library's Core Data store, relative to the library root.
    public static func storeURL(forLibrary libraryURL: URL) -> URL {
        libraryURL
            .appendingPathComponent("Index", isDirectory: true)
            .appendingPathComponent("Wndr.sqlite")
    }

    /// Store shared by every library before stores moved into the library folder.
    private static var legacyStoreURL: URL {
        NSPersistentContainer.defaultDirectoryURL().appendingPathComponent("WndrModel.sqlite")
    }

    private static let legacyMigrationKey = "wndr.store.legacyMigratedTo"

    public let container: NSPersistentContainer
    public var viewContext: Context { container.viewContext }

    /// The store currently open, or nil until `loadStore(forLibrary:)` succeeds.
    public private(set) var storeURL: URL?

    private let logger: WndrLogger
    private let defaults: UserDefaults

    /// Creates the stack without opening a store; call `loadStore(forLibrary:)` once a library is chosen.
    /// In-memory controllers open their store immediately.
    public init(inMemory: Bool = false, defaults: UserDefaults = .standard, logger: WndrLogger = .persistence) {
        self.logger = logger
        self.defaults = defaults

        let bundle = Bundle(for: PersistenceController.self)
        let modelURL = bundle.url(forResource: "WndrModel", withExtension: "momd")
        let managedObjectModel: NSManagedObjectModel

        if let modelURL, let model = NSManagedObjectModel(contentsOf: modelURL) {
            managedObjectModel = model
        } else {
            logger.fault("Unable to locate WndrModel.momd in bundle")
            managedObjectModel = NSManagedObjectModel()
        }

        container = NSPersistentContainer(name: "WndrModel", managedObjectModel: managedObjectModel)

        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.shouldDeleteInaccessibleFaults = true
        container.viewContext.undoManager = nil

        if inMemory {
            let storeDescription = NSPersistentStoreDescription()
            storeDescription.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [storeDescription]
            container.loadPersistentStores { [weak self] _, error in
                if let error {
                    self?.logger.error("Failed to load in-memory store: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Opens the store inside `libraryURL`, replacing the store of any previously open library.
    /// The previous store stays open if the new one fails to load.
    public func loadStore(forLibrary libraryURL: URL) throws {
        let url = Self.storeURL(forLibrary: libraryURL)
        guard url != storeURL else { return }
        guard !container.managedObjectModel.entities.isEmpty else {
            logger.fault("Cannot open store: data model is empty")
            throw StoreError.modelMissing
        }

        let coordinator = container.persistentStoreCoordinator
        let newStore: NSPersistentStore
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try migrateLegacyStoreIfNeeded(to: url)
            newStore = try coordinator.addPersistentStore(
                ofType: NSSQLiteStoreType,
                configurationName: nil,
                at: url,
                options: [
                    NSMigratePersistentStoresAutomaticallyOption: true,
                    NSInferMappingModelAutomaticallyOption: true
                ]
            )
        } catch {
            logger.error("Failed to load store at \(url.path): \(error.localizedDescription)")
            throw StoreError.loadFailed(url, error)
        }

        // Objects from the previous library must not outlive its store.
        viewContext.reset()
        for store in coordinator.persistentStores where store !== newStore {
            do {
                try coordinator.remove(store)
            } catch {
                logger.error("Failed to close previous store: \(error.localizedDescription)")
            }
        }

        storeURL = url
        logger.info("Loaded store at \(url.path)")
    }

    /// Copies the pre-library shared store into the first library opened after upgrading.
    /// The legacy file is left in place so it can be recovered manually.
    private func migrateLegacyStoreIfNeeded(to url: URL) throws {
        let fileManager = FileManager.default
        let legacyURL = Self.legacyStoreURL
        guard defaults.string(forKey: Self.legacyMigrationKey) == nil,
              !fileManager.fileExists(atPath: url.path),
              fileManager.fileExists(atPath: legacyURL.path) else {
            return
        }

        try container.persistentStoreCoordinator.replacePersistentStore(
            at: url,
            destinationOptions: nil,
            withPersistentStoreFrom: legacyURL,
            sourceOptions: nil,
            ofType: NSSQLiteStoreType
        )
        defaults.set(url.path, forKey: Self.legacyMigrationKey)
        logger.info("Migrated legacy store from \(legacyURL.path) to \(url.path)")
    }

    public func newBackgroundContext() -> Context {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
        context.undoManager = nil
        return context
    }

    /// Runs `block` on a new background context's private queue, then waits for the view
    /// context to merge the resulting save so main-thread reads afterwards observe it.
    /// Managed objects must not escape `block`; return IDs or value snapshots instead.
    @discardableResult
    public func performBackgroundTask<T>(
        _ block: @escaping @Sendable (Context) throws -> T
    ) async throws -> T {
        let context = newBackgroundContext()
        let result = try await context.perform { try block(context) }
        await viewContext.perform {}
        return result
    }

    public func saveIfNeeded(context: Context) {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            logger.error("Failed to save context: \(error.localizedDescription)")
        }
    }
}

extension NSManagedObjectContext {
    /// Fetches the first `T` whose `id` attribute equals `id`. Call only on this context's queue.
    func first<T: NSManagedObject>(_ type: T.Type, withID id: UUID) throws -> T? {
        let request = NSFetchRequest<T>(entityName: String(describing: type))
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try fetch(request).first
    }
}
