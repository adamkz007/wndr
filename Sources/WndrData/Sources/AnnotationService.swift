import Combine
import CoreData
import Foundation

@MainActor
public final class AnnotationService: ObservableObject {
    @Published public private(set) var annotations: [AnnotationDTO] = []

    private let persistenceController: PersistenceController
    private let logger: WndrLogger

    public init(
        persistenceController: PersistenceController,
        logger: WndrLogger = WndrLogger(category: "annotations")
    ) {
        self.persistenceController = persistenceController
        self.logger = logger
    }

    // MARK: - Fetch

    public func fetchAnnotations(for documentID: UUID) {
        let context = persistenceController.viewContext
        let fetchRequest = Annotation.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "document.id == %@", documentID as CVarArg)
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(keyPath: \Annotation.pageIndex, ascending: true),
            NSSortDescriptor(keyPath: \Annotation.createdAt, ascending: true)
        ]

        do {
            let results = try context.fetch(fetchRequest)
            annotations = results.compactMap { AnnotationDTO(from: $0) }
            logger.info("Fetched \(annotations.count) annotations for document")
        } catch {
            logger.error("Failed to fetch annotations: \(error.localizedDescription)")
        }
    }

    // MARK: - Create

    public func createHighlight(
        in documentID: UUID,
        pageIndex: Int,
        rects: [[String: Double]],
        textSnippet: String?,
        colorCategory: String = "yellow"
    ) async throws -> UUID {
        let context = persistenceController.newBackgroundContext()

        // Fetch document
        let documentRequest = Document.fetchRequest()
        documentRequest.predicate = NSPredicate(format: "id == %@", documentID as CVarArg)
        guard let document = try context.fetch(documentRequest).first else {
            throw AnnotationError.documentNotFound
        }

        let annotation = Annotation(context: context)
        annotation.id = UUID()
        annotation.kind = "highlight"
        annotation.pageIndex = Int32(pageIndex)
        annotation.colorCategory = colorCategory
        annotation.textSnippet = textSnippet
        annotation.createdAt = Date()
        annotation.updatedAt = Date()
        annotation.document = document

        // Store rects as JSON data
        let rectsData = try JSONSerialization.data(withJSONObject: rects)
        annotation.rects = rectsData

        try context.save()
        logger.info("Created highlight annotation: \(annotation.id!.uuidString)")

        await MainActor.run {
            fetchAnnotations(for: documentID)
        }

        return annotation.id!
    }

    public func createNote(
        in documentID: UUID,
        pageIndex: Int,
        position: CGPoint,
        content: String
    ) async throws -> UUID {
        let context = persistenceController.newBackgroundContext()

        let documentRequest = Document.fetchRequest()
        documentRequest.predicate = NSPredicate(format: "id == %@", documentID as CVarArg)
        guard let document = try context.fetch(documentRequest).first else {
            throw AnnotationError.documentNotFound
        }

        let annotation = Annotation(context: context)
        annotation.id = UUID()
        annotation.kind = "note"
        annotation.pageIndex = Int32(pageIndex)
        annotation.textSnippet = content
        annotation.createdAt = Date()
        annotation.updatedAt = Date()
        annotation.document = document

        // Store position as single rect
        let rect: [String: Double] = ["x": Double(position.x), "y": Double(position.y), "width": 20, "height": 20]
        let rectsData = try JSONSerialization.data(withJSONObject: [rect])
        annotation.rects = rectsData

        try context.save()
        logger.info("Created note annotation: \(annotation.id!.uuidString)")

        await MainActor.run {
            fetchAnnotations(for: documentID)
        }

        return annotation.id!
    }

    // MARK: - Update

    public func updateAnnotation(
        _ id: UUID,
        colorCategory: String? = nil,
        textSnippet: String? = nil
    ) async throws {
        let context = persistenceController.newBackgroundContext()
        let fetchRequest = Annotation.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)

        guard let annotation = try context.fetch(fetchRequest).first else {
            throw AnnotationError.annotationNotFound
        }

        if let color = colorCategory {
            annotation.colorCategory = color
        }
        if let text = textSnippet {
            annotation.textSnippet = text
        }
        annotation.updatedAt = Date()

        try context.save()
        logger.info("Updated annotation: \(id.uuidString)")

        if let docID = annotation.document?.id {
            await MainActor.run {
                fetchAnnotations(for: docID)
            }
        }
    }

    // MARK: - Delete

    public func deleteAnnotation(_ id: UUID) async throws {
        let context = persistenceController.newBackgroundContext()
        let fetchRequest = Annotation.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)

        guard let annotation = try context.fetch(fetchRequest).first else {
            throw AnnotationError.annotationNotFound
        }

        let documentID = annotation.document?.id

        context.delete(annotation)
        try context.save()
        logger.info("Deleted annotation: \(id.uuidString)")

        if let docID = documentID {
            await MainActor.run {
                fetchAnnotations(for: docID)
            }
        }
    }

    // MARK: - Bulk Operations

    public func deleteAllAnnotations(for documentID: UUID) async throws {
        let context = persistenceController.newBackgroundContext()
        let fetchRequest = Annotation.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "document.id == %@", documentID as CVarArg)

        let results = try context.fetch(fetchRequest)
        for annotation in results {
            context.delete(annotation)
        }

        try context.save()
        logger.info("Deleted all annotations for document: \(documentID.uuidString)")

        await MainActor.run {
            fetchAnnotations(for: documentID)
        }
    }
}

// MARK: - Errors

public enum AnnotationError: LocalizedError {
    case documentNotFound
    case annotationNotFound
    case invalidCoordinates

    public var errorDescription: String? {
        switch self {
        case .documentNotFound:
            return "Document not found"
        case .annotationNotFound:
            return "Annotation not found"
        case .invalidCoordinates:
            return "Invalid annotation coordinates"
        }
    }
}

// MARK: - DTO

public struct AnnotationDTO: Identifiable, Equatable {
    public let id: UUID
    public var kind: AnnotationKind
    public var pageIndex: Int
    public var rects: [CGRect]
    public var colorCategory: String
    public var textSnippet: String?
    public var createdAt: Date
    public var updatedAt: Date?
    public var documentID: UUID?
    public var noteID: UUID?

    init?(from annotation: Annotation) {
        guard let id = annotation.id else { return nil }

        self.id = id
        self.kind = AnnotationKind(rawValue: annotation.kind ?? "highlight") ?? .highlight
        self.pageIndex = Int(annotation.pageIndex)
        self.colorCategory = annotation.colorCategory ?? "yellow"
        self.textSnippet = annotation.textSnippet
        self.createdAt = annotation.createdAt ?? Date()
        self.updatedAt = annotation.updatedAt
        self.documentID = annotation.document?.id
        self.noteID = annotation.note?.id

        // Parse rects from JSON
        if let data = annotation.rects,
           let rectsArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Double]] {
            self.rects = rectsArray.map { dict in
                CGRect(
                    x: CGFloat(dict["x"] ?? 0),
                    y: CGFloat(dict["y"] ?? 0),
                    width: CGFloat(dict["width"] ?? 0),
                    height: CGFloat(dict["height"] ?? 0)
                )
            }
        } else {
            self.rects = []
        }
    }
}

public enum AnnotationKind: String {
    case highlight
    case underline
    case strikethrough
    case note
    case freehand
}

// MARK: - Color Presets

public struct AnnotationColorPreset: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let color: String // Hex color

    public static let presets: [AnnotationColorPreset] = [
        AnnotationColorPreset(id: "yellow", name: "Yellow", color: "#FFEB3B"),
        AnnotationColorPreset(id: "green", name: "Green", color: "#4CAF50"),
        AnnotationColorPreset(id: "blue", name: "Blue", color: "#2196F3"),
        AnnotationColorPreset(id: "pink", name: "Pink", color: "#E91E63"),
        AnnotationColorPreset(id: "orange", name: "Orange", color: "#FF9800"),
        AnnotationColorPreset(id: "purple", name: "Purple", color: "#9C27B0"),
    ]

    public static func preset(for id: String) -> AnnotationColorPreset? {
        presets.first { $0.id == id }
    }
}
