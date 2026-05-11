import SwiftUI

public struct ContentAreaDocumentHandlerKey: EnvironmentKey {
    public static let defaultValue: ((UUID, URL?, String) -> AnyView)? = nil
}

public struct ContentAreaNoteHandlerKey: EnvironmentKey {
    public static let defaultValue: ((UUID, String, String) -> AnyView)? = nil
}

public struct ContentAreaDropHandlerKey: EnvironmentKey {
    public static let defaultValue: (([URL]) -> Void)? = nil
}

public struct ContentAreaDocumentLinkedNotesHandlerKey: EnvironmentKey {
    public static let defaultValue: ((UUID) -> [NoteItem])? = nil
}

extension EnvironmentValues {
    public var contentAreaDocumentHandler: ((UUID, URL?, String) -> AnyView)? {
        get { self[ContentAreaDocumentHandlerKey.self] }
        set { self[ContentAreaDocumentHandlerKey.self] = newValue }
    }

    public var contentAreaNoteHandler: ((UUID, String, String) -> AnyView)? {
        get { self[ContentAreaNoteHandlerKey.self] }
        set { self[ContentAreaNoteHandlerKey.self] = newValue }
    }

    public var contentAreaDropHandler: (([URL]) -> Void)? {
        get { self[ContentAreaDropHandlerKey.self] }
        set { self[ContentAreaDropHandlerKey.self] = newValue }
    }

    public var contentAreaDocumentLinkedNotesHandler: ((UUID) -> [NoteItem])? {
        get { self[ContentAreaDocumentLinkedNotesHandlerKey.self] }
        set { self[ContentAreaDocumentLinkedNotesHandlerKey.self] = newValue }
    }
}
