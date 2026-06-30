import Foundation
import SwiftUI
import WndrData
import WndrKit

/// Applies targeted in-memory updates to sidebar and content view models
/// without triggering full library reloads.
@MainActor
struct LibraryViewStateSync {
    let environment: AppEnvironment
    let sidebarViewModel: LibrarySidebarViewModel
    let contentViewModel: ContentAreaViewModel
    @Binding var availableTags: [DocumentTagItem]
    @Binding var availableCollections: [CollectionMenuItem]

    private var libraryURL: URL? { environment.libraryURL }

    // MARK: - Full Sync (initial load and recovery only)

    func syncFullLibraryFromService() {
        PerformanceMonitor.shared.begin(.listRefresh)
        defer { PerformanceMonitor.shared.end(.listRefresh, metadata: ["scope": "full"]) }

        environment.documentService.fetchAllDocuments()
        environment.documentService.fetchAllNotes()
        environment.collectionService.fetchAllTags()
        environment.collectionService.fetchAllCollections()
        applyServiceSnapshotToViewModels()
    }

    func applyServiceSnapshotToViewModels() {
        syncSidebarStateFromService()
        syncAvailableFiltersFromService()
        syncPrimaryContentFromService()
        syncContentModeFromSelection()
        updatePerformanceProfile()
    }

    // MARK: - Targeted Document Updates

    func applyDocumentChange(_ documentID: UUID) {
        PerformanceMonitor.shared.begin(.listRefresh)
        defer { PerformanceMonitor.shared.end(.listRefresh, metadata: ["scope": "document", "id": documentID.uuidString]) }

        guard let dto = environment.documentService.upsertDocument(documentID) else { return }
        let item = RootViewMapper.documentItem(from: dto, libraryURL: libraryURL)
        replaceDocumentItem(item)
        syncSidebarCounts()
        syncContentModeFromSelection()
    }

    func applyDocumentDeletion(_ documentID: UUID) {
        PerformanceMonitor.shared.begin(.listRefresh)
        defer { PerformanceMonitor.shared.end(.listRefresh, metadata: ["scope": "document_delete"]) }

        environment.documentService.removeDocumentFromMemory(documentID)
        contentViewModel.documents.removeAll { $0.id == documentID }
        syncSidebarCounts()
        syncContentModeFromSelection()
    }

    // MARK: - Targeted Note Updates

    func applyNoteChange(_ noteID: UUID) {
        PerformanceMonitor.shared.begin(.listRefresh)
        defer { PerformanceMonitor.shared.end(.listRefresh, metadata: ["scope": "note"]) }

        guard let dto = environment.documentService.upsertNote(noteID) else { return }
        let item = RootViewMapper.noteItem(from: dto)
        replaceNoteItem(item)
        syncSidebarCounts()
        syncContentModeFromSelection()
    }

    func applyNoteDeletion(_ noteID: UUID) {
        PerformanceMonitor.shared.begin(.listRefresh)
        defer { PerformanceMonitor.shared.end(.listRefresh, metadata: ["scope": "note_delete"]) }

        environment.documentService.removeNoteFromMemory(noteID)
        contentViewModel.notes.removeAll { $0.id == noteID }
        syncSidebarCounts()
        syncContentModeFromSelection()
    }

    // MARK: - Collection / Tag Mutation Side Effects

    func applyCollectionMutation(_ result: CollectionMutationResult) {
        PerformanceMonitor.shared.begin(.listRefresh)
        defer { PerformanceMonitor.shared.end(.listRefresh, metadata: ["scope": "collection"]) }

        if let deletedCollectionID = result.deletedCollectionID {
            environment.documentService.clearCollectionFromDocuments(deletedCollectionID)
            contentViewModel.documents = contentViewModel.documents.map { item in
                var updated = item
                if updated.collectionID == deletedCollectionID {
                    updated.collectionID = nil
                }
                return updated
            }
        }

        if let documentID = result.affectedDocumentID {
            if let dto = environment.documentService.upsertDocument(documentID) {
                replaceDocumentItem(RootViewMapper.documentItem(from: dto, libraryURL: libraryURL))
            }
        }

        syncSidebarCollectionsFromService()
        syncAvailableCollectionsFromService()
        syncSidebarCounts()
        syncContentModeFromSelection()
    }

    func applyTagMutation(_ result: CollectionMutationResult) {
        PerformanceMonitor.shared.begin(.listRefresh)
        defer { PerformanceMonitor.shared.end(.listRefresh, metadata: ["scope": "tag"]) }

        if let deletedTagID = result.deletedTagID {
            environment.documentService.removeTagFromAllDocuments(deletedTagID)
            contentViewModel.documents = contentViewModel.documents.map { item in
                var updated = item
                updated.tags.removeAll { $0.id == deletedTagID }
                return updated
            }
        }

        if let tagID = result.renamedTagID, let newName = result.renamedTagName {
            environment.documentService.renameTagInAllDocuments(tagID, newName: newName)
            contentViewModel.documents = contentViewModel.documents.map { item in
                var updated = item
                if let index = updated.tags.firstIndex(where: { $0.id == tagID }) {
                    updated.tags[index].name = newName
                }
                return updated
            }
        }

        if let documentID = result.affectedDocumentID,
           let dto = environment.documentService.upsertDocument(documentID) {
            replaceDocumentItem(RootViewMapper.documentItem(from: dto, libraryURL: libraryURL))
        }

        syncSidebarTagsFromService()
        syncAvailableTagsFromService()
        syncContentModeFromSelection()
    }

    func applyImportedDocuments(_ documentIDs: [UUID]) {
        PerformanceMonitor.shared.begin(.listRefresh)
        defer {
            PerformanceMonitor.shared.end(.listRefresh, metadata: ["scope": "import", "count": String(documentIDs.count)])
        }

        for documentID in documentIDs {
            guard let dto = environment.documentService.upsertDocument(documentID) else { continue }
            let item = RootViewMapper.documentItem(from: dto, libraryURL: libraryURL)
            if !contentViewModel.documents.contains(where: { $0.id == documentID }) {
                contentViewModel.documents.insert(item, at: 0)
            } else {
                replaceDocumentItem(item)
            }
        }

        syncSidebarCounts()
        if contentViewModel.contentMode == .empty, !contentViewModel.documents.isEmpty {
            contentViewModel.contentMode = .documentList
        }
        syncContentModeFromSelection()
        updatePerformanceProfile()
    }

    // MARK: - Private Helpers

    private func replaceDocumentItem(_ item: DocumentItem) {
        if let index = contentViewModel.documents.firstIndex(where: { $0.id == item.id }) {
            contentViewModel.documents[index] = item
        } else {
            contentViewModel.documents.insert(item, at: 0)
        }
    }

    private func replaceNoteItem(_ item: NoteItem) {
        if let index = contentViewModel.notes.firstIndex(where: { $0.id == item.id }) {
            contentViewModel.notes[index] = item
        } else {
            contentViewModel.notes.insert(item, at: 0)
        }
    }

    private func syncSidebarStateFromService() {
        syncSidebarCounts()
        syncSidebarTagsFromService()
        syncSidebarCollectionsFromService()
    }

    private func syncSidebarCounts() {
        sidebarViewModel.documentCount = environment.documentService.documents.count
        sidebarViewModel.unsortedDocumentCount = environment.documentService.documents.filter { $0.collectionID == nil }.count
        sidebarViewModel.noteCount = environment.documentService.notes.count
    }

    private func syncSidebarTagsFromService() {
        sidebarViewModel.tags = RootViewMapper.tagItems(from: environment.collectionService.tags)
    }

    private func syncSidebarCollectionsFromService() {
        sidebarViewModel.collections = RootViewMapper.collectionItems(from: environment.collectionService.collections)
    }

    private func syncAvailableFiltersFromService() {
        syncAvailableTagsFromService()
        syncAvailableCollectionsFromService()
    }

    private func syncAvailableTagsFromService() {
        availableTags = RootViewMapper.documentTagItems(from: environment.collectionService.tags)
    }

    private func syncAvailableCollectionsFromService() {
        availableCollections = RootViewMapper.collectionMenuItems(from: environment.collectionService.collections)
    }

    private func syncPrimaryContentFromService() {
        contentViewModel.documents = RootViewMapper.documentItems(
            from: environment.documentService.documents,
            libraryURL: libraryURL
        )
        contentViewModel.notes = RootViewMapper.noteItems(from: environment.documentService.notes)
    }

    private func syncContentModeFromSelection() {
        if let selection = sidebarViewModel.selectedItem {
            contentViewModel.contentMode = RootViewMapper.contentMode(
                for: selection,
                documentCount: contentViewModel.documents.count,
                noteCount: contentViewModel.notes.count
            )
        }
    }

    private func updatePerformanceProfile() {
        PerformanceMonitor.shared.updateProfile(
            documentCount: environment.documentService.documents.count,
            noteCount: environment.documentService.notes.count
        )
    }
}

/// Shared DTO-to-view-item mapping used by app composition and view-state sync.
enum RootViewMapper {
    static func documentItems(from dtos: [DocumentDTO], libraryURL: URL?) -> [DocumentItem] {
        dtos.map { documentItem(from: $0, libraryURL: libraryURL) }
    }

    static func documentItem(from dto: DocumentDTO, libraryURL: URL?) -> DocumentItem {
        DocumentItem(
            id: dto.id,
            title: dto.title,
            subtitle: dto.subtitle,
            authors: dto.authors,
            pageCount: dto.pageCount,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            fileURL: dto.fileURL,
            thumbnailURL: thumbnailURL(for: dto.id, libraryURL: libraryURL),
            fileSizeBytes: fileSizeBytes(for: dto.fileURL),
            documentType: dto.documentType,
            tags: dto.tags.map(documentTagItem),
            collectionID: dto.collectionID
        )
    }

    static func noteItems(from dtos: [NoteDTO]) -> [NoteItem] {
        dtos.map(noteItem)
    }

    static func noteItem(from dto: NoteDTO) -> NoteItem {
        NoteItem(
            id: dto.id,
            title: dto.title,
            preview: dto.preview,
            pinned: dto.pinned,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }

    static func tagItems(from dtos: [TagDTO]) -> [TagItem] {
        dtos.map(tagItem)
    }

    static func tagItem(from dto: TagDTO) -> TagItem {
        TagItem(id: dto.id, name: dto.name, color: dto.color, itemCount: dto.itemCount)
    }

    static func documentTagItems(from dtos: [TagDTO]) -> [DocumentTagItem] {
        dtos.map(documentTagItem)
    }

    static func documentTagItem(from dto: TagDTO) -> DocumentTagItem {
        DocumentTagItem(id: dto.id, name: dto.name, color: dto.color)
    }

    static func documentTagItem(from dto: DocumentTagDTO) -> DocumentTagItem {
        DocumentTagItem(id: dto.id, name: dto.name, color: dto.color)
    }

    static func collectionItems(from dtos: [CollectionDTO]) -> [CollectionItem] {
        dtos.map(collectionItem)
    }

    static func collectionItem(from dto: CollectionDTO) -> CollectionItem {
        CollectionItem(id: dto.id, name: dto.name, icon: dto.icon, documentCount: dto.documentCount)
    }

    static func collectionMenuItems(from dtos: [CollectionDTO]) -> [CollectionMenuItem] {
        dtos.map(collectionMenuItem)
    }

    static func collectionMenuItem(from dto: CollectionDTO) -> CollectionMenuItem {
        CollectionMenuItem(id: dto.id, name: dto.name)
    }

    static func contentMode(
        for selection: SidebarSelection,
        documentCount: Int,
        noteCount: Int
    ) -> WndrKit.ContentMode {
        switch selection {
        case .allDocuments, .unsortedDocuments, .collection, .tag:
            return documentCount == 0 ? .empty : .documentList
        case .allNotes:
            return noteCount == 0 ? .empty : .noteList
        }
    }

    static func thumbnailURL(for documentID: UUID, libraryURL: URL?) -> URL? {
        guard let libraryURL else { return nil }
        let indexURL = libraryURL.appendingPathComponent("Index", isDirectory: true)
        let thumbURL = indexURL.appendingPathComponent("Thumbnails", isDirectory: true)
            .appendingPathComponent("\(documentID.uuidString).png")
        return FileManager.default.fileExists(atPath: thumbURL.path) ? thumbURL : nil
    }

    /// Resolves the file size for a document once at mapping time so row
    /// rendering never performs a synchronous filesystem lookup.
    static func fileSizeBytes(for fileURL: URL?) -> Int64? {
        guard let fileURL else { return nil }
        let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
        if let size = values?.fileSize {
            return Int64(size)
        }
        return nil
    }
}
