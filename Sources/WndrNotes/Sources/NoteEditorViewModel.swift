import Combine
import Foundation
import SwiftUI

public struct NoteDocumentLinkSuggestion: Identifiable, Equatable {
    public let id: UUID
    public let title: String
    public let subtitle: String?
    public let documentType: String

    public init(id: UUID, title: String, subtitle: String? = nil, documentType: String) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.documentType = documentType
    }
}

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
    /// Description of the most recent failed save; cleared when a save succeeds.
    @Published public private(set) var saveError: String?
    @Published public var showPreview: Bool = false
    @Published public var wordCount: Int = 0
    @Published public var characterCount: Int = 0
    @Published public private(set) var linkSuggestions: [NoteDocumentLinkSuggestion] = []
    @Published public private(set) var isShowingLinkSuggestions: Bool = false
    @Published public private(set) var activeLinkQuery: String = ""
    @Published public var pendingCursorLocation: Int?

    public let noteID: UUID
    public var onSave: ((UUID, String, String) async throws -> Void)?
    public var onDelete: ((UUID) async throws -> Void)?
    public var onSearchDocumentLinks: ((String) -> [NoteDocumentLinkSuggestion])?

    private var saveTask: Task<Void, Never>?
    private var inFlightSave: Task<Void, Never>?
    /// Incremented on every edit so a save can tell whether newer edits arrived while it ran.
    private var revision = 0
    private var isLoading = false
    private var autoSaveEnabled: Bool = true
    private let autoSaveDelay: TimeInterval = 2.0
    private var activeLinkRange: Range<String.Index>?
    private var pendingLinkSuggestionUpdate: DispatchWorkItem?

    /// Every live editor, so unsaved changes can be flushed before the app quits.
    private static let openEditors = NSHashTable<NoteEditorViewModel>.weakObjects()

    public init(noteID: UUID, title: String = "", body: String = "") {
        self.noteID = noteID
        self.title = title
        self.body = body
        updateStats()
        Self.openEditors.add(self)
    }

    // MARK: - Open Editors

    public static var hasUnsavedChanges: Bool {
        openEditors.allObjects.contains { $0.isDirty }
    }

    /// Saves every editor with unsaved changes. Returns false if any of them still has unsaved changes.
    public static func saveAllPending() async -> Bool {
        for editor in openEditors.allObjects where editor.isDirty {
            await editor.save()
        }
        return !hasUnsavedChanges
    }

    /// Drops unsaved changes for a note that no longer exists, so they are not saved later.
    public static func discardChanges(forNoteID noteID: UUID) {
        for editor in openEditors.allObjects where editor.noteID == noteID {
            editor.discardChanges()
        }
    }

    // MARK: - Editing

    /// Replaces the contents with stored values without marking the note dirty.
    public func load(title: String, body: String, lastSaved: Date?) {
        isLoading = true
        self.title = title
        self.body = body
        isLoading = false
        updateStats()
        self.lastSaved = lastSaved
        isDirty = false
        saveError = nil
    }

    private func discardChanges() {
        saveTask?.cancel()
        isDirty = false
        saveError = nil
    }

    private func markDirty() {
        guard !isLoading else { return }
        revision += 1
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

    /// Saves the current contents. Saves never overlap: a call made while one is running
    /// waits for it, then saves anything typed in the meantime.
    public func save() async {
        while let inFlightSave {
            await inFlightSave.value
        }
        guard isDirty, let onSave = onSave else { return }

        let savedRevision = revision
        let title = title
        let body = body
        let task = Task {
            isSaving = true
            defer {
                isSaving = false
                inFlightSave = nil
            }

            do {
                try await onSave(noteID, title, body)
                saveError = nil
                lastSaved = Date()
                if revision == savedRevision {
                    isDirty = false
                } else {
                    // Edits arrived while saving; they are still dirty and need their own save.
                    scheduleAutoSave()
                }
            } catch {
                // Stay dirty so the next edit, Cmd-S or quit retries the save.
                saveError = error.localizedDescription
            }
        }
        inFlightSave = task
        await task.value
    }

    public func delete() async {
        guard let onDelete = onDelete else { return }
        do {
            try await onDelete(noteID)
            discardChanges()
        } catch {
            saveError = error.localizedDescription
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

    public func updateLinkSuggestions(cursorLocation: Int) {
        guard let context = activeLinkContext(cursorLocation: cursorLocation) else {
            activeLinkRange = nil
            setLinkSuggestionState(
                query: "",
                suggestions: [],
                isShowing: false
            )
            return
        }

        activeLinkRange = context.replacementRange
        let suggestions = onSearchDocumentLinks?(context.query) ?? []
        setLinkSuggestionState(
            query: context.query,
            suggestions: suggestions,
            isShowing: !suggestions.isEmpty
        )
    }

    public func applyLinkSuggestion(_ suggestion: NoteDocumentLinkSuggestion) {
        guard let replacementRange = activeLinkRange else { return }

        let replacementText = "[[\(suggestion.title)]]"
        body.replaceSubrange(replacementRange, with: replacementText)

        let cursorOffset = body.distance(from: body.startIndex, to: replacementRange.lowerBound) + replacementText.utf16.count
        pendingCursorLocation = cursorOffset
        clearLinkSuggestions()
    }

    public func clearLinkSuggestions() {
        activeLinkRange = nil
        setLinkSuggestionState(
            query: "",
            suggestions: [],
            isShowing: false
        )
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

    private func activeLinkContext(cursorLocation: Int) -> (query: String, replacementRange: Range<String.Index>)? {
        guard let cursorIndex = stringIndex(forUTF16Offset: cursorLocation) else {
            return nil
        }

        let prefix = body[..<cursorIndex]
        guard let openRange = prefix.range(of: "[[", options: .backwards) else {
            return nil
        }

        let openContentRange = openRange.upperBound..<cursorIndex
        let openContent = String(body[openContentRange])
        if openContent.contains("]]") || openContent.contains("[") || openContent.contains("\n") {
            return nil
        }

        var replacementUpperBound = cursorIndex
        if body[cursorIndex...].hasPrefix("]]") {
            replacementUpperBound = body.index(cursorIndex, offsetBy: 2)
        }

        return (
            query: openContent.trimmingCharacters(in: .whitespacesAndNewlines),
            replacementRange: openRange.lowerBound..<replacementUpperBound
        )
    }

    private func stringIndex(forUTF16Offset offset: Int) -> String.Index? {
        guard offset >= 0, offset <= body.utf16.count else { return nil }
        guard let utf16Index = body.utf16.index(body.utf16.startIndex, offsetBy: offset, limitedBy: body.utf16.endIndex),
              let index = String.Index(utf16Index, within: body) else {
            return nil
        }
        return index
    }

    private func setLinkSuggestionState(
        query: String,
        suggestions: [NoteDocumentLinkSuggestion],
        isShowing: Bool
    ) {
        pendingLinkSuggestionUpdate?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.activeLinkQuery = query
            self.linkSuggestions = suggestions
            self.isShowingLinkSuggestions = isShowing
        }

        pendingLinkSuggestionUpdate = workItem
        DispatchQueue.main.async(execute: workItem)
    }
}
