import Combine
import CoreData
import Foundation

@MainActor
public final class CollectionService: ObservableObject {
    @Published public private(set) var collections: [CollectionDTO] = []
    @Published public private(set) var tags: [TagDTO] = []

    private let persistenceController: PersistenceController
    private let logger: WndrLogger

    // macOS/iPadOS style tag colors (matches Finder tags)
    public static let tagColorPalette = [
        "#FF6B6B", // Red
        "#FF9500", // Orange
        "#FFCC00", // Yellow
        "#34C759", // Green
        "#00C7BE", // Teal
        "#007AFF", // Blue
        "#AF52DE"  // Purple
    ]

    /// Get the next color that should be assigned to a new tag
    public var nextTagColor: String {
        let colorIndex = tags.count % Self.tagColorPalette.count
        return Self.tagColorPalette[colorIndex]
    }

    public init(persistenceController: PersistenceController, logger: WndrLogger = WndrLogger(category: "collections")) {
        self.persistenceController = persistenceController
        self.logger = logger
    }

    // MARK: - Collections

    public func fetchAllCollections() {
        let context = persistenceController.viewContext
        let fetchRequest = DocumentCollection.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \DocumentCollection.sortOrder, ascending: true)]

        do {
            let results = try context.fetch(fetchRequest)
            collections = results.map { CollectionDTO(from: $0) }
            logger.info("Fetched \(collections.count) collections")
        } catch {
            logger.error("Failed to fetch collections: \(error.localizedDescription)")
        }
    }

    public func createCollection(name: String, kind: CollectionKind = .manual, icon: String? = nil) async throws -> UUID {
        let context = persistenceController.newBackgroundContext()

        let collection = DocumentCollection(context: context)
        collection.id = UUID()
        collection.name = name
        collection.kind = kind.rawValue
        collection.icon = icon
        collection.sortOrder = Int32(collections.count)
        collection.createdAt = Date()

        try context.save()
        logger.info("Created collection: \(collection.id!.uuidString)")

        await MainActor.run {
            fetchAllCollections()
        }

        return collection.id!
    }

    public func updateCollection(_ id: UUID, name: String? = nil, icon: String? = nil) async throws {
        let context = persistenceController.newBackgroundContext()
        let fetchRequest = DocumentCollection.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)

        let results = try context.fetch(fetchRequest)
        guard let collection = results.first else { return }

        if let name = name {
            collection.name = name
        }
        if let icon = icon {
            collection.icon = icon
        }

        try context.save()
        logger.info("Updated collection: \(id.uuidString)")

        await MainActor.run {
            fetchAllCollections()
        }
    }

    public func deleteCollection(_ id: UUID) async throws {
        let context = persistenceController.newBackgroundContext()
        let fetchRequest = DocumentCollection.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)

        let results = try context.fetch(fetchRequest)
        guard let collection = results.first else { return }

        context.delete(collection)
        try context.save()
        logger.info("Deleted collection: \(id.uuidString)")

        await MainActor.run {
            fetchAllCollections()
        }
    }

    public func addDocument(_ documentID: UUID, to collectionID: UUID) async throws {
        let context = persistenceController.newBackgroundContext()

        let collectionRequest = DocumentCollection.fetchRequest()
        collectionRequest.predicate = NSPredicate(format: "id == %@", collectionID as CVarArg)
        guard let collection = try context.fetch(collectionRequest).first else { return }

        let documentRequest = Document.fetchRequest()
        documentRequest.predicate = NSPredicate(format: "id == %@", documentID as CVarArg)
        guard let document = try context.fetch(documentRequest).first else { return }

        collection.addToDocuments(document)
        try context.save()
        logger.info("Added document \(documentID) to collection \(collectionID)")

        await MainActor.run {
            fetchAllCollections()
        }
    }

    /// Sets a document to belong to exactly one collection (exclusive assignment)
    /// Pass nil for collectionID to remove from all collections
    public func setDocumentCollection(_ documentID: UUID, collectionID: UUID?) async throws {
        let context = persistenceController.newBackgroundContext()

        let documentRequest = Document.fetchRequest()
        documentRequest.predicate = NSPredicate(format: "id == %@", documentID as CVarArg)
        guard let document = try context.fetch(documentRequest).first else { return }

        // Remove from all existing collections
        if let existingCollections = document.collections as? Set<DocumentCollection> {
            for collection in existingCollections {
                collection.removeFromDocuments(document)
            }
        }

        // Add to new collection if specified
        if let collectionID = collectionID {
            let collectionRequest = DocumentCollection.fetchRequest()
            collectionRequest.predicate = NSPredicate(format: "id == %@", collectionID as CVarArg)
            if let collection = try context.fetch(collectionRequest).first {
                collection.addToDocuments(document)
                logger.info("Set document \(documentID) to collection \(collectionID)")
            }
        } else {
            logger.info("Removed document \(documentID) from all collections")
        }

        try context.save()

        await MainActor.run {
            fetchAllCollections()
        }
    }

    public func removeDocument(_ documentID: UUID, from collectionID: UUID) async throws {
        let context = persistenceController.newBackgroundContext()

        let collectionRequest = DocumentCollection.fetchRequest()
        collectionRequest.predicate = NSPredicate(format: "id == %@", collectionID as CVarArg)
        guard let collection = try context.fetch(collectionRequest).first else { return }

        let documentRequest = Document.fetchRequest()
        documentRequest.predicate = NSPredicate(format: "id == %@", documentID as CVarArg)
        guard let document = try context.fetch(documentRequest).first else { return }

        collection.removeFromDocuments(document)
        try context.save()
        logger.info("Removed document \(documentID) from collection \(collectionID)")

        await MainActor.run {
            fetchAllCollections()
        }
    }

    // MARK: - Tags

    public func fetchAllTags() {
        let context = persistenceController.viewContext
        let fetchRequest = Tag.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Tag.name, ascending: true)]

        do {
            let results = try context.fetch(fetchRequest)
            tags = results.map { TagDTO(from: $0) }
            logger.info("Fetched \(tags.count) tags")
        } catch {
            logger.error("Failed to fetch tags: \(error.localizedDescription)")
        }
    }

    public func createTag(name: String, color: String? = nil) async throws -> UUID {
        let context = persistenceController.newBackgroundContext()

        // Auto-assign color from palette if not provided
        let assignedColor: String
        if let color = color {
            assignedColor = color
        } else {
            // Get the count of existing tags to determine the next color
            let tagCount = tags.count
            let colorIndex = tagCount % Self.tagColorPalette.count
            assignedColor = Self.tagColorPalette[colorIndex]
        }

        let tag = Tag(context: context)
        tag.id = UUID()
        tag.name = name
        tag.color = assignedColor
        tag.createdAt = Date()

        try context.save()
        logger.info("Created tag: \(tag.id!.uuidString) with color: \(assignedColor)")

        await MainActor.run {
            fetchAllTags()
        }

        return tag.id!
    }

    public func updateTag(_ id: UUID, name: String? = nil, color: String? = nil) async throws {
        let context = persistenceController.newBackgroundContext()
        let fetchRequest = Tag.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)

        let results = try context.fetch(fetchRequest)
        guard let tag = results.first else { return }

        if let name = name {
            tag.name = name
        }
        if let color = color {
            tag.color = color
        }

        try context.save()
        logger.info("Updated tag: \(id.uuidString)")

        await MainActor.run {
            fetchAllTags()
        }
    }

    public func deleteTag(_ id: UUID) async throws {
        let context = persistenceController.newBackgroundContext()
        let fetchRequest = Tag.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)

        let results = try context.fetch(fetchRequest)
        guard let tag = results.first else { return }

        context.delete(tag)
        try context.save()
        logger.info("Deleted tag: \(id.uuidString)")

        await MainActor.run {
            fetchAllTags()
        }
    }

    public func addTag(_ tagID: UUID, to documentID: UUID) async throws {
        let context = persistenceController.newBackgroundContext()

        let tagRequest = Tag.fetchRequest()
        tagRequest.predicate = NSPredicate(format: "id == %@", tagID as CVarArg)
        guard let tag = try context.fetch(tagRequest).first else { return }

        let documentRequest = Document.fetchRequest()
        documentRequest.predicate = NSPredicate(format: "id == %@", documentID as CVarArg)
        guard let document = try context.fetch(documentRequest).first else { return }

        tag.addToDocuments(document)
        try context.save()
        logger.info("Added tag \(tagID) to document \(documentID)")

        await MainActor.run {
            fetchAllTags()
        }
    }

    public func removeTag(_ tagID: UUID, from documentID: UUID) async throws {
        let context = persistenceController.newBackgroundContext()

        let tagRequest = Tag.fetchRequest()
        tagRequest.predicate = NSPredicate(format: "id == %@", tagID as CVarArg)
        guard let tag = try context.fetch(tagRequest).first else { return }

        let documentRequest = Document.fetchRequest()
        documentRequest.predicate = NSPredicate(format: "id == %@", documentID as CVarArg)
        guard let document = try context.fetch(documentRequest).first else { return }

        tag.removeFromDocuments(document)
        try context.save()
        logger.info("Removed tag \(tagID) from document \(documentID)")

        await MainActor.run {
            fetchAllTags()
        }
    }

    public func addTagToNote(_ tagID: UUID, noteID: UUID) async throws {
        let context = persistenceController.newBackgroundContext()

        let tagRequest = Tag.fetchRequest()
        tagRequest.predicate = NSPredicate(format: "id == %@", tagID as CVarArg)
        guard let tag = try context.fetch(tagRequest).first else { return }

        let noteRequest = Note.fetchRequest()
        noteRequest.predicate = NSPredicate(format: "id == %@", noteID as CVarArg)
        guard let note = try context.fetch(noteRequest).first else { return }

        tag.addToNotes(note)
        try context.save()
        logger.info("Added tag \(tagID) to note \(noteID)")

        await MainActor.run {
            fetchAllTags()
        }
    }
}

// MARK: - Data Transfer Objects

public enum CollectionKind: String {
    case manual
    case smart
    case bundle
}

public struct CollectionDTO: Identifiable {
    public let id: UUID
    public var name: String
    public var icon: String?
    public var kind: CollectionKind
    public var documentCount: Int

    init(from collection: DocumentCollection) {
        self.id = collection.id!
        self.name = collection.name!
        self.icon = collection.icon
        self.kind = CollectionKind(rawValue: collection.kind ?? "manual") ?? .manual
        self.documentCount = collection.documents?.count ?? 0
    }
}

public struct TagDTO: Identifiable {
    public let id: UUID
    public var name: String
    public var color: String?
    public var itemCount: Int

    init(from tag: Tag) {
        self.id = tag.id!
        self.name = tag.name!
        self.color = tag.color
        let docCount = tag.documents?.count ?? 0
        let noteCount = tag.notes?.count ?? 0
        self.itemCount = docCount + noteCount
    }
}
