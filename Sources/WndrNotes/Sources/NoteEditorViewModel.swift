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
    private var autoSaveEnabled: Bool = true
    private let autoSaveDelay: TimeInterval = 2.0
    private var activeLinkRange: Range<String.Index>?
    private var pendingLinkSuggestionUpdate: DispatchWorkItem?

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
