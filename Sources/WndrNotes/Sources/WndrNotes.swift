import Combine
import Foundation

// Re-export public types
@_exported import struct Foundation.UUID

public final class NoteWorkspaceCoordinator: ObservableObject {
    @Published public private(set) var openedNoteIdentifiers: [UUID] = []
    @Published public private(set) var activeNoteID: UUID?

    public init() {}

    public func open(note id: UUID) {
        if openedNoteIdentifiers.contains(id) == false {
            openedNoteIdentifiers.append(id)
        }
        activeNoteID = id
    }

    public func close(note id: UUID) {
        openedNoteIdentifiers.removeAll { $0 == id }
        if activeNoteID == id {
            activeNoteID = openedNoteIdentifiers.last
        }
    }

    public func setActive(note id: UUID) {
        guard openedNoteIdentifiers.contains(id) else { return }
        activeNoteID = id
    }
}
