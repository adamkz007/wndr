import Combine
import Foundation
import SwiftUI

@MainActor
public final class NoteEditorViewModel: ObservableObject {
    @Published public var title: String {
        didSet { markDirty() }
    }
    @Published public var body: String {
        didSet { markDirty() }
    }
    @Published public var isDirty: Bool = false
    @Published public var isSaving: Bool = false
    @Published public var lastSaved: Date?
    @Published public var showPreview: Bool = false
    @Published public var wordCount: Int = 0
    @Published public var characterCount: Int = 0

    public let noteID: UUID
    public var onSave: ((UUID, String, String) async throws -> Void)?
    public var onDelete: ((UUID) async throws -> Void)?

    private var saveTask: Task<Void, Never>?
    private var autoSaveEnabled: Bool = true
    private let autoSaveDelay: TimeInterval = 2.0

    public init(noteID: UUID, title: String = "", body: String = "") {
        self.noteID = noteID
        self.title = title
        self.body = body
        updateStats()
    }

    private func markDirty() {
        guard !isSaving else { return }
        isDirty = true
        updateStats()
        scheduleAutoSave()
    }

    private func updateStats() {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        characterCount = trimmed.count
        wordCount = trimmed.isEmpty ? 0 : trimmed.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.count
    }

    private func scheduleAutoSave() {
        saveTask?.cancel()
        guard autoSaveEnabled else { return }

        saveTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(autoSaveDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await save()
        }
    }

    public func save() async {
        guard isDirty, let onSave = onSave else { return }
        isSaving = true

        do {
            try await onSave(noteID, title, body)
            isDirty = false
            lastSaved = Date()
        } catch {
            // Error handled by caller
        }

        isSaving = false
    }

    public func delete() async {
        guard let onDelete = onDelete else { return }
        do {
            try await onDelete(noteID)
        } catch {
            // Error handled by caller
        }
    }

    public func togglePreview() {
        showPreview.toggle()
    }

    public func insertTemplate(_ template: String) {
        body += template
    }

    public func insertLink(to noteTitle: String) {
        body += "[[\(noteTitle)]]"
    }

    public func disableAutoSave() {
        autoSaveEnabled = false
        saveTask?.cancel()
    }

    public func enableAutoSave() {
        autoSaveEnabled = true
        if isDirty {
            scheduleAutoSave()
        }
    }
}
