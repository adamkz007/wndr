import Combine
import CoreData
import Foundation

@MainActor
public final class DocumentService: ObservableObject {
    @Published public private(set) var documents: [DocumentDTO] = []
    @Published public private(set) var notes: [NoteDTO] = []

    private let persistenceController: PersistenceController
    private let logger: WndrLogger
    private var cancellables = Set<AnyCancellable>()

    public init(persistenceController: PersistenceController, logger: WndrLogger = WndrLogger(category: "documents")) {
        self.persistenceController = persistenceController
        self.logger = logger
    }

    public func fetchAllDocuments() {
        let context = persistenceController.viewContext
        let fetchRequest = Document.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Document.createdAt, ascending: false)]

        do {
            let results = try context.fetch(fetchRequest)
            documents = results.map { DocumentDTO(from: $0) }
            logger.info("Fetched \(documents.count) documents")
        } catch {
            logger.error("Failed to fetch documents: \(error.localizedDescription)")
        }
    }

    public func fetchAllNotes() {
        let context = persistenceController.viewContext
        let fetchRequest = Note.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Note.updatedAt, ascending: false)]

        do {
            let results = try context.fetch(fetchRequest)
            notes = results.map { NoteDTO(from: $0) }
            logger.info("Fetched \(notes.count) notes")
        } catch {
            logger.error("Failed to fetch notes: \(error.localizedDescription)")
        }
    }

    public func fetchDocuments(for collectionID: UUID) {
        let context = persistenceController.viewContext
        let fetchRequest = Document.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "ANY collections.id == %@", collectionID as CVarArg)
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Document.createdAt, ascending: false)]

        do {
            let results = try context.fetch(fetchRequest)
            documents = results.map { DocumentDTO(from: $0) }
            logger.info("Fetched \(documents.count) documents for collection")
        } catch {
            logger.error("Failed to fetch documents for collection: \(error.localizedDescription)")
        }
    }

    public func fetchDocuments(forTag tagID: UUID) {
        let context = persistenceController.viewContext
        let fetchRequest = Document.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "ANY tags.id == %@", tagID as CVarArg)
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Document.createdAt, ascending: false)]

        do {
            let results = try context.fetch(fetchRequest)
            documents = results.map { DocumentDTO(from: $0) }
            logger.info("Fetched \(documents.count) documents for tag")
        } catch {
            logger.error("Failed to fetch documents for tag: \(error.localizedDescription)")
        }
    }

    public func createNote(title: String, body: String = "") async throws -> UUID {
        let context = persistenceController.newBackgroundContext()

        let noteID = UUID()
        let now = Date()

        let note = Note(context: context)
        note.id = noteID
        note.title = title
        note.body = body
        note.createdAt = now
        note.updatedAt = now
        note.pinned = false

        try context.save()
        logger.info("Created note: \(noteID.uuidString)")

        // Insert the new DTO directly instead of re-fetching all notes
        let dto = NoteDTO(id: noteID, title: title, body: body, pinned: false, createdAt: now, updatedAt: now)
        await MainActor.run {
            notes.insert(dto, at: 0)
        }

        return noteID
    }

    public func renameDocument(_ documentID: UUID, title: String, libraryURL: URL? = nil, libraryStore: LibraryRootStore? = nil) async throws {
        let context = persistenceController.newBackgroundContext()
        let fetchRequest = Document.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", documentID as CVarArg)

        let results = try context.fetch(fetchRequest)
        guard let document = results.first else { return }

        let oldTitle = document.title
        document.title = title
        document.updatedAt = Date()

        // Also rename the file on disk if we have the necessary parameters
        if let libraryURL = libraryURL,
           let libraryStore = libraryStore,
           let currentFileURL = document.fileURL,
           oldTitle != title {

            let isEpub = document.documentType == "epub"
            let newURL: URL?

            if isEpub {
                newURL = await libraryStore.renameEpubFile(documentID: documentID, to: title, in: libraryURL)
            } else {
                newURL = await libraryStore.renameDocumentFile(documentID: documentID, to: title, in: libraryURL)
            }

            if let newURL = newURL {
                document.fileURL = newURL
                logger.info("Renamed file from \(currentFileURL.lastPathComponent) to \(newURL.lastPathComponent)")
            }
        }

        try context.save()
        logger.info("Renamed document: \(documentID.uuidString) to \(title)")

        await MainActor.run {
            fetchAllDocuments()
        }
    }

    public func updateDocumentMetadata(_ documentID: UUID, title: String? = nil, subtitle: String? = nil, authors: [String]? = nil, libraryURL: URL? = nil, libraryStore: LibraryRootStore? = nil) async throws {
        let context = persistenceController.newBackgroundContext()
        let fetchRequest = Document.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", documentID as CVarArg)

        let results = try context.fetch(fetchRequest)
        guard let document = results.first else { return }

        let oldTitle = document.title

        if let title = title {
            document.title = title

            // Also rename the file on disk if title changed
            if let libraryURL = libraryURL,
               let libraryStore = libraryStore,
               let currentFileURL = document.fileURL,
               oldTitle != title {

                let isEpub = document.documentType == "epub"
                let newURL: URL?

                if isEpub {
                    newURL = await libraryStore.renameEpubFile(documentID: documentID, to: title, in: libraryURL)
                } else {
                    newURL = await libraryStore.renameDocumentFile(documentID: documentID, to: title, in: libraryURL)
                }

                if let newURL = newURL {
                    document.fileURL = newURL
                    logger.info("Renamed file from \(currentFileURL.lastPathComponent) to \(newURL.lastPathComponent)")
                }
            }
        }
        document.subtitle = subtitle
        document.authors = authors
        document.updatedAt = Date()

        try context.save()
        logger.info("Updated metadata for document: \(documentID.uuidString)")

        await MainActor.run {
            fetchAllDocuments()
        }
    }

    public func deleteDocument(_ documentID: UUID) async throws {
        let context = persistenceController.newBackgroundContext()
        let fetchRequest = Document.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", documentID as CVarArg)

        let results = try context.fetch(fetchRequest)
        guard let document = results.first else { return }

        context.delete(document)
        try context.save()
        logger.info("Deleted document: \(documentID.uuidString)")

        await MainActor.run {
            fetchAllDocuments()
        }
    }

    public func deleteNote(_ noteID: UUID) async throws {
        let context = persistenceController.newBackgroundContext()
        let fetchRequest = Note.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", noteID as CVarArg)

        let results = try context.fetch(fetchRequest)
        guard let note = results.first else { return }

        context.delete(note)
        try context.save()
        logger.info("Deleted note: \(noteID.uuidString)")

        await MainActor.run {
            fetchAllNotes()
        }
    }

    public func updateNote(_ noteID: UUID, title: String, body: String) async throws {
        let context = persistenceController.newBackgroundContext()
        let fetchRequest = Note.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", noteID as CVarArg)

        let results = try context.fetch(fetchRequest)
        guard let note = results.first else {
            logger.error("Note not found: \(noteID.uuidString)")
            return
        }

        note.title = title
        note.body = body
        note.updatedAt = Date()

        try context.save()
        logger.info("Updated note: \(noteID.uuidString)")

        await MainActor.run {
            fetchAllNotes()
        }
    }

    public func toggleNotePinned(_ noteID: UUID) async throws {
        let context = persistenceController.newBackgroundContext()
        let fetchRequest = Note.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", noteID as CVarArg)

        let results = try context.fetch(fetchRequest)
        guard let note = results.first else { return }

        note.pinned.toggle()
        note.updatedAt = Date()

        try context.save()
        logger.info("Toggled pinned for note: \(noteID.uuidString)")

        await MainActor.run {
            fetchAllNotes()
        }
    }

    public func getDocument(byID id: UUID) -> DocumentDTO? {
        let context = persistenceController.viewContext
        let fetchRequest = Document.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        fetchRequest.fetchLimit = 1

        do {
            if let document = try context.fetch(fetchRequest).first {
                return DocumentDTO(from: document)
            }
        } catch {
            logger.error("Failed to fetch document: \(error.localizedDescription)")
        }
        return nil
    }

    /// Repairs stale or missing file URLs by resolving each document back to the current library layout.
    @discardableResult
    public func repairStoredDocumentURLs(libraryURL: URL, libraryStore: LibraryRootStore) async -> Int {
        let context = persistenceController.newBackgroundContext()
        let fetchRequest = Document.fetchRequest()

        do {
            let documents = try context.fetch(fetchRequest)
            var repairedCount = 0

            for document in documents {
                guard let documentID = document.id else { continue }

                let currentURL = document.fileURL
                if let currentURL, FileManager.default.fileExists(atPath: currentURL.path) {
                    continue
                }

                guard let resolvedURL = await libraryStore.resolveDocumentFile(
                    for: documentID,
                    preferredURL: currentURL,
                    documentType: document.documentType,
                    in: libraryURL
                ) else {
                    continue
                }

                if document.fileURL != resolvedURL {
                    document.fileURL = resolvedURL
                    document.updatedAt = Date()
                    repairedCount += 1
                    logger.info("Repaired file URL for document \(documentID.uuidString)")
                }
            }

            if repairedCount > 0 {
                try context.save()
                await MainActor.run {
                    fetchAllDocuments()
                }
            }

            return repairedCount
        } catch {
            logger.error("Failed to repair stored document URLs: \(error.localizedDescription)")
            return 0
        }
    }

    /// Calculates total storage consumed by the library directory (PDFs, Notes, Attachments, etc.)
    public func calculateTotalStorage(libraryURL: URL) -> Int64 {
        let fileManager = FileManager.default
        var totalSize: Int64 = 0

        guard let enumerator = fileManager.enumerator(
            at: libraryURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: { url, error in
                self.logger.error("Storage calc error at \(url.path): \(error.localizedDescription)")
                return true
            }
        ) else {
            logger.error("Failed to enumerate library directory for storage calculation")
            return 0
        }

        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                if resourceValues.isRegularFile == true, let fileSize = resourceValues.fileSize {
                    totalSize += Int64(fileSize)
                }
            } catch {
                logger.error("Failed to read size for \(fileURL.lastPathComponent): \(error.localizedDescription)")
            }
        }

        logger.info("Total library storage: \(totalSize) bytes")
        return totalSize
    }

    /// Searches note titles and bodies for the given query text using case/diacritic-insensitive matching.
    public func searchNoteContent(query: String) -> [NoteDTO] {
        let context = persistenceController.viewContext
        let fetchRequest = Note.fetchRequest()
        fetchRequest.predicate = NSPredicate(
            format: "body CONTAINS[cd] %@ OR title CONTAINS[cd] %@",
            query, query
        )
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Note.updatedAt, ascending: false)]

        do {
            let results = try context.fetch(fetchRequest)
            logger.info("Content search found \(results.count) notes for query: \(query)")
            return results.map { NoteDTO(from: $0) }
        } catch {
            logger.error("Failed to search note content: \(error.localizedDescription)")
            return []
        }
    }

    public func getNote(byID id: UUID) -> NoteDTO? {
        let context = persistenceController.viewContext
        let fetchRequest = Note.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        fetchRequest.fetchLimit = 1

        do {
            if let note = try context.fetch(fetchRequest).first {
                return NoteDTO(from: note)
            }
        } catch {
            logger.error("Failed to fetch note: \(error.localizedDescription)")
        }
        return nil
    }

    /// Migrates existing documents to use meaningful filenames instead of "document.pdf"
    /// This is optional and can be called to update legacy documents
    public func migrateDocumentFilenames(libraryURL: URL, libraryStore: LibraryRootStore) async -> (migrated: Int, failed: Int) {
        let context = persistenceController.newBackgroundContext()
        let fetchRequest = Document.fetchRequest()

        var migratedCount = 0
        var failedCount = 0

        do {
            let documents = try context.fetch(fetchRequest)
            logger.info("Starting filename migration for \(documents.count) documents")

            for document in documents {
                guard let documentID = document.id,
                      let title = document.title,
                      let fileURL = document.fileURL else {
                    continue
                }

                // Skip if not using generic name
                if fileURL.lastPathComponent != "document.pdf" && fileURL.lastPathComponent != "document.epub" {
                    continue
                }

                // Determine type and rename
                let isEpub = document.documentType == "epub"
                let newURL: URL?

                if isEpub {
                    newURL = await libraryStore.renameEpubFile(documentID: documentID, to: title, in: libraryURL)
                } else {
                    newURL = await libraryStore.renameDocumentFile(documentID: documentID, to: title, in: libraryURL)
                }

                if let newURL = newURL, newURL != fileURL {
                    document.fileURL = newURL
                    migratedCount += 1
                    logger.info("Migrated: \(title) -> \(newURL.lastPathComponent)")
                } else if newURL == nil {
                    failedCount += 1
                    logger.error("Failed to migrate: \(title)")
                }
            }

            if migratedCount > 0 {
                try context.save()
                logger.info("Migration complete: \(migratedCount) migrated, \(failedCount) failed")
            }
        } catch {
            logger.error("Migration failed: \(error.localizedDescription)")
        }

        return (migratedCount, failedCount)
    }
}

// MARK: - Data Transfer Objects

public struct DocumentDTO: Identifiable {
    public let id: UUID
    public var title: String
    public var subtitle: String?
    public var authors: [String]?
    public var pageCount: Int
    public var createdAt: Date
    public var updatedAt: Date?
    public var ocrStatus: String?
    public var fileURL: URL?
    public var documentType: String
    public var tags: [DocumentTagDTO]
    public var collectionID: UUID?

    init(from document: Document) {
        self.id = document.id!
        self.title = document.title ?? "Untitled"
        self.subtitle = document.subtitle
        self.authors = document.authors
        self.pageCount = Int(document.pageCount)
        self.createdAt = document.createdAt!
        self.updatedAt = document.updatedAt
        self.ocrStatus = document.ocrStatus
        self.fileURL = document.fileURL
        self.documentType = document.documentType ?? "pdf"

        // DEBUG: Check if file URLs are correct
        if let url = document.fileURL {
            print("DEBUG DocumentDTO: Document \(id) (\(title)) has fileURL: \(url.path)")
            print("DEBUG DocumentDTO: File exists: \(FileManager.default.fileExists(atPath: url.path))")
        } else {
            print("DEBUG DocumentDTO: Document \(id) (\(title)) has nil fileURL!")
        }
        self.tags = (document.tags as? Set<Tag>)?.map { DocumentTagDTO(id: $0.id!, name: $0.name!, color: $0.color) } ?? []
        self.collectionID = (document.collections as? Set<DocumentCollection>)?.first?.id
    }
}

public struct DocumentTagDTO: Identifiable, Equatable, Hashable {
    public let id: UUID
    public var name: String
    public var color: String?

    public init(id: UUID, name: String, color: String? = nil) {
        self.id = id
        self.name = name
        self.color = color
    }
}

public struct NoteDTO: Identifiable {
    public let id: UUID
    public var title: String
    public var body: String
    public var pinned: Bool
    public var createdAt: Date
    public var updatedAt: Date?

    init(from note: Note) {
        self.id = note.id!
        self.title = note.title ?? "Untitled Note"
        self.body = note.body ?? ""
        self.pinned = note.pinned
        self.createdAt = note.createdAt!
        self.updatedAt = note.updatedAt
    }

    public init(id: UUID, title: String, body: String = "", pinned: Bool = false, createdAt: Date, updatedAt: Date?) {
        self.id = id
        self.title = title
        self.body = body
        self.pinned = pinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var preview: String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = 150
        if trimmed.count > limit {
            return String(trimmed.prefix(limit)) + "..."
        }
        return trimmed
    }
}
