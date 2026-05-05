import Combine
import Foundation

@MainActor
public final class InspectorPanelViewModel: ObservableObject {
    @Published public var inspectorMode: InspectorMode = .none

    public init() {}

    public func showDocument(_ document: DocumentItem) {
        inspectorMode = .document(document)
    }

    public func showNote(_ note: NoteItem) {
        inspectorMode = .note(note)
    }

    public func clear() {
        inspectorMode = .none
    }
}
