import CoreData
import Foundation

public final class PersistenceController {
    public typealias Context = NSManagedObjectContext

    public static let shared = PersistenceController()

    public let container: NSPersistentContainer
    public var viewContext: Context { container.viewContext }

    private let logger: WndrLogger

    public init(inMemory: Bool = false, logger: WndrLogger = .persistence) {
        self.logger = logger

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

        if inMemory {
            let storeDescription = NSPersistentStoreDescription()
            storeDescription.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [storeDescription]
        }

        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.shouldDeleteInaccessibleFaults = true
        container.viewContext.undoManager = nil

        container.loadPersistentStores { [weak self] _, error in
            if let error {
                self?.logger.error("Failed to load persistent stores: \(error.localizedDescription)")
            } else {
                self?.logger.info("Persistent stores loaded")
            }
        }
    }

    public func newBackgroundContext() -> Context {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
        context.undoManager = nil
        return context
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
