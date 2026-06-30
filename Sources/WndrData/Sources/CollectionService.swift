import Combine
import CoreData
import Foundation

/// Side effects from a collection or tag mutation that the UI layer should apply incrementally.
public struct CollectionMutationResult: Sendable {
    public let affectedDocumentID: UUID?
    public let affectedCollectionIDs: [UUID]
    public let affectedTagID: UUID?
    public let deletedTagID: UUID?
    public let deletedCollectionID: UUID?
    public let renamedTagID: UUID?
    public let renamedTagName: String?
    public let tagDTO: TagDTO?
    public let collectionDTO: CollectionDTO?

    public init(
        affectedDocumentID: UUID? = nil,
        affectedCollectionIDs: [UUID] = [],
        affectedTagID: UUID? = nil,
        deletedTagID: UUID? = nil,
        deletedCollectionID: UUID? = nil,
        renamedTagID: UUID? = nil,
        renamedTagName: String? = nil,
        tagDTO: TagDTO? = nil,
        collectionDTO: CollectionDTO? = nil
    ) {
        self.affectedDocumentID = affectedDocumentID
        self.affectedCollectionIDs = affectedCollectionIDs
        self.affectedTagID = affectedTagID
        self.deletedTagID = deletedTagID
        self.deletedCollectionID = deletedCollectionID
        self.renamedTagID = renamedTagID
        self.renamedTagName = renamedTagName
        self.tagDTO = tagDTO
        self.collectionDTO = collectionDTO
    }
}

@MainActor
public final class CollectionService: ObservableObject {
    @Published public private(set) var collections: [CollectionDTO] = []
    @Published public private(set) var tags: [TagDTO] = []

    private let persistenceController: PersistenceController
    private let logger: WndrLogger

    // macOS style tag colors (matches Finder tags)
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

    /// Full reload for initial startup and recovery only.
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
        let sortOrder = Int32(collections.count)

        let collection = DocumentCollection(context: context)
        collection.id = UUID()
        collection.name = name
        collection.kind = kind.rawValue
        collection.icon = icon
        collection.sortOrder = sortOrder
        collection.createdAt = Date()

        try context.save()
        let collectionID = collection.id!
        logger.info("Created collection: \(collectionID.uuidString)")

        await MainActor.run {
            if let dto = self.collectionDTO(for: collectionID) {
                collections.append(dto)
            }
        }

        return collectionID
    }

    public func updateCollection(_ id: UUID, name: String? = nil, icon: String? = nil) async throws -> CollectionMutationResult {
        let context = persistenceController.newBackgroundContext()
        let fetchRequest = DocumentCollection.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)

        let results = try context.fetch(fetchRequest)
        guard let collection = results.first else { return CollectionMutationResult() }

        if let name = name {
            collection.name = name
        }
        if let icon = icon {
            collection.icon = icon
        }

        try context.save()
        logger.info("Updated collection: \(id.uuidString)")

        let dto = await MainActor.run { self.collectionDTO(for: id) }
        await MainActor.run {
            if let dto, let index = collections.firstIndex(where: { $0.id == id }) {
                collections[index] = dto
            }
        }
        return CollectionMutationResult(affectedCollectionIDs: [id], collectionDTO: dto)
    }

    public func deleteCollection(_ id: UUID) async throws -> CollectionMutationResult {
        let context = persistenceController.newBackgroundContext()
        let fetchRequest = DocumentCollection.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)

        let results = try context.fetch(fetchRequest)
        guard let collection = results.first else { return CollectionMutationResult() }

        context.delete(collection)
        try context.save()
        logger.info("Deleted collection: \(id.uuidString)")

        await MainActor.run {
            collections.removeAll { $0.id == id }
        }
        return CollectionMutationResult(affectedCollectionIDs: [id], deletedCollectionID: id)
    }

    public func addDocument(_ documentID: UUID, to collectionID: UUID) async throws -> CollectionMutationResult {
        let context = persistenceController.newBackgroundContext()

        let collectionRequest = DocumentCollection.fetchRequest()
        collectionRequest.predicate = NSPredicate(format: "id == %@", collectionID as CVarArg)
        guard let collection = try context.fetch(collectionRequest).first else { return CollectionMutationResult() }

        let documentRequest = Document.fetchRequest()
        documentRequest.predicate = NSPredicate(format: "id == %@", documentID as CVarArg)
        guard let document = try context.fetch(documentRequest).first else { return CollectionMutationResult() }

        collection.addToDocuments(document)
        try context.save()
        logger.info("Added document \(documentID) to collection \(collectionID)")

        await MainActor.run {
            refreshCollectionCounts([collectionID])
        }
        return CollectionMutationResult(
            affectedDocumentID: documentID,
            affectedCollectionIDs: [collectionID]
        )
    }

    /// Sets a document to belong to exactly one collection (exclusive assignment)
    /// Pass nil for collectionID to remove from all collections
    public func setDocumentCollection(_ documentID: UUID, collectionID: UUID?) async throws -> CollectionMutationResult {
        let context = persistenceController.newBackgroundContext()

        let documentRequest = Document.fetchRequest()
        documentRequest.predicate = NSPredicate(format: "id == %@", documentID as CVarArg)
        guard let document = try context.fetch(documentRequest).first else { return CollectionMutationResult() }

        // Remove from all existing collections
        var affectedCollectionIDs = Set<UUID>()
        if let existingCollections = document.collections as? Set<DocumentCollection> {
            for collection in existingCollections {
                if let collectionID = collection.id {
                    affectedCollectionIDs.insert(collectionID)
                }
                collection.removeFromDocuments(document)
            }
        }

        // Add to new collection if specified
        if let collectionID = collectionID {
            let collectionRequest = DocumentCollection.fetchRequest()
            collectionRequest.predicate = NSPredicate(format: "id == %@", collectionID as CVarArg)
            if let collection = try context.fetch(collectionRequest).first {
                collection.addToDocuments(document)
                affectedCollectionIDs.insert(collectionID)
                logger.info("Set document \(documentID) to collection \(collectionID)")
            }
        } else {
            logger.info("Removed document \(documentID) from all collections")
        }

        try context.save()

        await MainActor.run {
            refreshCollectionCounts(Array(affectedCollectionIDs))
        }
        return CollectionMutationResult(
            affectedDocumentID: documentID,
            affectedCollectionIDs: Array(affectedCollectionIDs)
        )
    }

    public func removeDocument(_ documentID: UUID, from collectionID: UUID) async throws -> CollectionMutationResult {
        let context = persistenceController.newBackgroundContext()

        let collectionRequest = DocumentCollection.fetchRequest()
        collectionRequest.predicate = NSPredicate(format: "id == %@", collectionID as CVarArg)
        guard let collection = try context.fetch(collectionRequest).first else { return CollectionMutationResult() }

        let documentRequest = Document.fetchRequest()
        documentRequest.predicate = NSPredicate(format: "id == %@", documentID as CVarArg)
        guard let document = try context.fetch(documentRequest).first else { return CollectionMutationResult() }

        collection.removeFromDocuments(document)
        try context.save()
        logger.info("Removed document \(documentID) from collection \(collectionID)")

        await MainActor.run {
            refreshCollectionCounts([collectionID])
        }
        return CollectionMutationResult(
            affectedDocumentID: documentID,
            affectedCollectionIDs: [collectionID]
        )
    }

    // MARK: - Tags

    /// Full reload for initial startup and recovery only.
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
        let tagID = tag.id!
        logger.info("Created tag: \(tagID.uuidString) with color: \(assignedColor)")

        await MainActor.run {
            if let dto = self.tagDTO(for: tagID) {
                tags.append(dto)
                tags.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
        }

        return tagID
    }

    public func updateTag(_ id: UUID, name: String? = nil, color: String? = nil) async throws -> CollectionMutationResult {
        let context = persistenceController.newBackgroundContext()
        let fetchRequest = Tag.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)

        let results = try context.fetch(fetchRequest)
        guard let tag = results.first else { return CollectionMutationResult() }

        if let name = name {
            tag.name = name
        }
        if let color = color {
            tag.color = color
        }

        try context.save()
        logger.info("Updated tag: \(id.uuidString)")

        let dto = await MainActor.run { self.tagDTO(for: id) }
        await MainActor.run {
            if let dto, let index = tags.firstIndex(where: { $0.id == id }) {
                tags[index] = dto
            }
        }
        return CollectionMutationResult(
            affectedTagID: id,
            renamedTagID: name != nil ? id : nil,
            renamedTagName: name,
            tagDTO: dto
        )
    }

    public func deleteTag(_ id: UUID) async throws -> CollectionMutationResult {
        let context = persistenceController.newBackgroundContext()
        let fetchRequest = Tag.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)

        let results = try context.fetch(fetchRequest)
        guard let tag = results.first else { return CollectionMutationResult() }

        context.delete(tag)
        try context.save()
        logger.info("Deleted tag: \(id.uuidString)")

        await MainActor.run {
            tags.removeAll { $0.id == id }
        }
        return CollectionMutationResult(deletedTagID: id)
    }

    public func addTag(_ tagID: UUID, to documentID: UUID) async throws -> CollectionMutationResult {
        let context = persistenceController.newBackgroundContext()

        let tagRequest = Tag.fetchRequest()
        tagRequest.predicate = NSPredicate(format: "id == %@", tagID as CVarArg)
        guard let tag = try context.fetch(tagRequest).first else { return CollectionMutationResult() }

        let documentRequest = Document.fetchRequest()
        documentRequest.predicate = NSPredicate(format: "id == %@", documentID as CVarArg)
        guard let document = try context.fetch(documentRequest).first else { return CollectionMutationResult() }

        tag.addToDocuments(document)
        try context.save()
        logger.info("Added tag \(tagID) to document \(documentID)")

        let dto = await MainActor.run { self.tagDTO(for: tagID) }
        await MainActor.run {
            refreshTagCount(tagID)
        }
        return CollectionMutationResult(
            affectedDocumentID: documentID,
            affectedTagID: tagID,
            tagDTO: dto
        )
    }

    public func removeTag(_ tagID: UUID, from documentID: UUID) async throws -> CollectionMutationResult {
        let context = persistenceController.newBackgroundContext()

        let tagRequest = Tag.fetchRequest()
        tagRequest.predicate = NSPredicate(format: "id == %@", tagID as CVarArg)
        guard let tag = try context.fetch(tagRequest).first else { return CollectionMutationResult() }

        let documentRequest = Document.fetchRequest()
        documentRequest.predicate = NSPredicate(format: "id == %@", documentID as CVarArg)
        guard let document = try context.fetch(documentRequest).first else { return CollectionMutationResult() }

        tag.removeFromDocuments(document)
        try context.save()
        logger.info("Removed tag \(tagID) from document \(documentID)")

        await MainActor.run {
            refreshTagCount(tagID)
        }
        return CollectionMutationResult(
            affectedDocumentID: documentID,
            affectedTagID: tagID
        )
    }

    public func addTagToNote(_ tagID: UUID, noteID: UUID) async throws -> CollectionMutationResult {
        let context = persistenceController.newBackgroundContext()

        let tagRequest = Tag.fetchRequest()
        tagRequest.predicate = NSPredicate(format: "id == %@", tagID as CVarArg)
        guard let tag = try context.fetch(tagRequest).first else { return CollectionMutationResult() }

        let noteRequest = Note.fetchRequest()
        noteRequest.predicate = NSPredicate(format: "id == %@", noteID as CVarArg)
        guard let note = try context.fetch(noteRequest).first else { return CollectionMutationResult() }

        tag.addToNotes(note)
        try context.save()
        logger.info("Added tag \(tagID) to note \(noteID)")

        await MainActor.run {
            refreshTagCount(tagID)
        }
        return CollectionMutationResult(affectedTagID: tagID)
    }

    // MARK: - Incremental Count Refresh

    private func collectionDTO(for id: UUID) -> CollectionDTO? {
        let context = persistenceController.viewContext
        let fetchRequest = DocumentCollection.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        fetchRequest.fetchLimit = 1
        guard let collection = try? context.fetch(fetchRequest).first else { return nil }
        return CollectionDTO(from: collection)
    }

    private func tagDTO(for id: UUID) -> TagDTO? {
        let context = persistenceController.viewContext
        let fetchRequest = Tag.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        fetchRequest.fetchLimit = 1
        guard let tag = try? context.fetch(fetchRequest).first else { return nil }
        return TagDTO(from: tag)
    }

    private func refreshCollectionCounts(_ collectionIDs: [UUID]) {
        let context = persistenceController.viewContext
        for collectionID in Set(collectionIDs) {
            guard let index = collections.firstIndex(where: { $0.id == collectionID }) else { continue }
            let fetchRequest = DocumentCollection.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", collectionID as CVarArg)
            fetchRequest.fetchLimit = 1
            if let collection = try? context.fetch(fetchRequest).first {
                collections[index] = CollectionDTO(from: collection)
            }
        }
    }

    private func refreshTagCount(_ tagID: UUID) {
        let context = persistenceController.viewContext
        guard let index = tags.firstIndex(where: { $0.id == tagID }) else { return }
        let fetchRequest = Tag.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", tagID as CVarArg)
        fetchRequest.fetchLimit = 1
        if let tag = try? context.fetch(fetchRequest).first {
            tags[index] = TagDTO(from: tag)
        }
    }
}

// MARK: - Data Transfer Objects

public enum CollectionKind: String, Sendable {
    case manual
    case smart
    case bundle
}

public struct CollectionDTO: Identifiable, Sendable {
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

public struct TagDTO: Identifiable, Sendable {
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
