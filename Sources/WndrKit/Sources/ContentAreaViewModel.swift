import Combine
import Foundation
import SwiftUI

// MARK: - Search Types

public enum SearchMode: Equatable, Hashable {
    case fileName
    case content
}

// MARK: - Sort Options

public enum SortOption: String, CaseIterable {
    case titleAscending = "Title A → Z"
    case titleDescending = "Title Z → A"
    case dateNewest = "Date Modified (Newest)"
    case dateOldest = "Date Modified (Oldest)"

    public var icon: String {
        switch self {
        case .titleAscending:
            return "textformat.abc"
        case .titleDescending:
            return "textformat.abc"
        case .dateNewest:
            return "calendar.badge.clock"
        case .dateOldest:
            return "calendar.badge.clock"
        }
    }

    public var label: String {
        switch self {
        case .titleAscending:
            return "Title (A → Z)"
        case .titleDescending:
            return "Title (Z → A)"
        case .dateNewest:
            return "Newest First"
        case .dateOldest:
            return "Oldest First"
        }
    }
}

public struct SearchResultItem: Identifiable, Equatable {
    public let id: UUID
    public let title: String
    public let snippet: String
    public let kind: SearchResultKind
    public let fileURL: URL?
    public let thumbnailURL: URL?
    public let pageIndex: Int?

    public init(
        id: UUID,
        title: String,
        snippet: String,
        kind: SearchResultKind,
        fileURL: URL? = nil,
        thumbnailURL: URL? = nil,
        pageIndex: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.snippet = snippet
        self.kind = kind
        self.fileURL = fileURL
        self.thumbnailURL = thumbnailURL
        self.pageIndex = pageIndex
    }

    public enum SearchResultKind: Equatable {
        case document
        case note
    }
}

// MARK: - Content Area View Model

@MainActor
public final class ContentAreaViewModel: ObservableObject {
    @Published public var contentMode: ContentMode = .empty
    @Published public var documents: [DocumentItem] = []
    @Published public var notes: [NoteItem] = []
    @Published public var isGridView: Bool = false
    @Published public var totalStorageBytes: Int64 = 0

    // New note sheet
    @Published public var showingNewNoteSheet: Bool = false

    // Search state
    @Published public var searchText: String = ""
    @Published public var searchMode: SearchMode = .fileName
    @Published public var isSearchingContent: Bool = false
    @Published public var contentSearchResults: [SearchResultItem] = []

    // Sort state
    @Published public var sortOption: SortOption = .dateNewest

    public var documentService: AnyObject?
    public var onImport: (() -> Void)?
    public var onRefresh: ((SidebarSelection?) -> Void)?
    public var onCreateNote: ((String) async -> UUID?)?

    /// Called to perform content search. The implementation should append results to
    /// `contentSearchResults` progressively as they are found. Runs within a cancellable Task.
    public var onContentSearch: ((String) async -> Void)?

    private var contentSearchTask: Task<Void, Never>?
    private var searchDebouncer: AnyCancellable?

    public init() {
        setupSearchDebounce()
    }

    // MARK: - Search Debounce

    private func setupSearchDebounce() {
        searchDebouncer = $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] text in
                guard let self = self else { return }
                if self.searchMode == .content {
                    self.performContentSearch(query: text)
                }
            }
    }

    // MARK: - File Name Filtering and Sorting

    public var filteredDocuments: [DocumentItem] {
        let filtered: [DocumentItem]
        if searchMode == .fileName && !searchText.isEmpty {
            let query = searchText.lowercased()
            filtered = documents.filter { $0.title.lowercased().contains(query) }
        } else {
            filtered = documents
        }

        return sortDocuments(filtered)
    }

    public var filteredNotes: [NoteItem] {
        let filtered: [NoteItem]
        if searchMode == .fileName && !searchText.isEmpty {
            let query = searchText.lowercased()
            filtered = notes.filter { $0.title.lowercased().contains(query) }
        } else {
            filtered = notes
        }

        return sortNotes(filtered)
    }

    private func sortDocuments(_ docs: [DocumentItem]) -> [DocumentItem] {
        switch sortOption {
        case .titleAscending:
            return docs.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .titleDescending:
            return docs.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        case .dateNewest:
            return docs.sorted {
                let date0 = $0.updatedAt ?? $0.createdAt ?? Date.distantPast
                let date1 = $1.updatedAt ?? $1.createdAt ?? Date.distantPast
                return date0 > date1
            }
        case .dateOldest:
            return docs.sorted {
                let date0 = $0.updatedAt ?? $0.createdAt ?? Date.distantFuture
                let date1 = $1.updatedAt ?? $1.createdAt ?? Date.distantFuture
                return date0 < date1
            }
        }
    }

    private func sortNotes(_ noteList: [NoteItem]) -> [NoteItem] {
        switch sortOption {
        case .titleAscending:
            return noteList.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .titleDescending:
            return noteList.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        case .dateNewest:
            return noteList.sorted {
                let date0 = $0.updatedAt ?? $0.createdAt ?? Date.distantPast
                let date1 = $1.updatedAt ?? $1.createdAt ?? Date.distantPast
                return date0 > date1
            }
        case .dateOldest:
            return noteList.sorted {
                let date0 = $0.updatedAt ?? $0.createdAt ?? Date.distantFuture
                let date1 = $1.updatedAt ?? $1.createdAt ?? Date.distantFuture
                return date0 < date1
            }
        }
    }

    /// Whether a content search is active (mode is content and query is non-empty)
    public var isContentSearchActive: Bool {
        searchMode == .content && !searchText.isEmpty
    }

    // MARK: - Search Actions

    public func clearSearch() {
        searchText = ""
        contentSearchResults = []
        contentSearchTask?.cancel()
        isSearchingContent = false
    }

    public func setSearchMode(_ mode: SearchMode) {
        guard mode != searchMode else { return }
        searchMode = mode
        contentSearchResults = []
        contentSearchTask?.cancel()
        isSearchingContent = false

        if mode == .content && !searchText.isEmpty {
            performContentSearch(query: searchText)
        }
    }

    private func performContentSearch(query: String) {
        contentSearchTask?.cancel()

        guard !query.isEmpty else {
            contentSearchResults = []
            isSearchingContent = false
            return
        }

        isSearchingContent = true
        contentSearchResults = []

        contentSearchTask = Task {
            await onContentSearch?(query)

            if !Task.isCancelled {
                isSearchingContent = false
            }
        }
    }

    // MARK: - Content Navigation

    public func updateContent(for selection: SidebarSelection?) {
        // Clear search when navigating
        clearSearch()

        guard let selection = selection else {
            contentMode = .empty
            documents = []
            notes = []
            return
        }

        // Request refresh from parent
        onRefresh?(selection)

        switch selection {
        case .allDocuments, .unsortedDocuments:
            contentMode = documents.isEmpty ? .empty : .documentList
        case .allNotes:
            contentMode = notes.isEmpty ? .empty : .noteList
        case .collection, .tag:
            contentMode = documents.isEmpty ? .empty : .documentList
        }
    }

    public func selectDocument(_ id: UUID) {
        contentMode = .documentDetail(id)
    }

    public func selectNote(_ id: UUID) {
        contentMode = .noteDetail(id)
    }

    public func toggleViewMode() {
        isGridView.toggle()
    }

    public func showImportPanel() {
        onImport?()
    }

    public func showNewNoteSheet() {
        showingNewNoteSheet = true
    }

    public func createNewNote() {
        createNote(withTitle: "Untitled Note")
    }

    public func createNote(withTitle title: String) {
        Task {
            if let noteID = await onCreateNote?(title) {
                // Switch to the new note
                contentMode = .noteDetail(noteID)
            }
        }
    }
}
