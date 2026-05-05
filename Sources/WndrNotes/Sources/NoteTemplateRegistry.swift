import Foundation

public struct NoteTemplate: Identifiable, Hashable {
    public let id: String
    public var title: String
    public var body: String

    public init(id: String, title: String, body: String) {
        self.id = id
        self.title = title
        self.body = body
    }
}

public final class NoteTemplateRegistry {
    public static let shared = NoteTemplateRegistry()

    public private(set) var templates: [NoteTemplate]

    private init() {
        templates = [
            NoteTemplate(id: "literature_review", title: "Literature Review", body: "# Summary\n\n# Key Findings\n\n# Follow-up"),
            NoteTemplate(id: "meeting", title: "Meeting Notes", body: "# Agenda\n\n# Decisions\n\n# Action Items")
        ]
    }

    public func template(withID id: String) -> NoteTemplate? {
        templates.first { $0.id == id }
    }
}
