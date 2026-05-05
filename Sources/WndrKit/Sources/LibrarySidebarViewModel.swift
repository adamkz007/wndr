import Combine
import Foundation

@MainActor
public final class LibrarySidebarViewModel: ObservableObject {
    @Published public var selectedItem: SidebarSelection? = .allDocuments
    @Published public var collections: [CollectionItem] = []
    @Published public var tags: [TagItem] = []
    @Published public var documentCount: Int = 0
    @Published public var unsortedDocumentCount: Int = 0
    @Published public var noteCount: Int = 0
    @Published public var pendingEditCollectionID: UUID?
    @Published public var pendingEditTagID: UUID?

    public var onCreateTag: ((String, String?) async -> UUID?)? = nil
    public var onCreateCollection: ((String, String?) async -> UUID?)? = nil

    public init() {}

    public func createCollection() {
        Task {
            if let onCreateCollection = onCreateCollection,
               let collectionID = await onCreateCollection("New Collection", "folder") {
                await MainActor.run {
                    selectedItem = .collection(collectionID)
                    pendingEditCollectionID = collectionID
                }
            }
        }
    }

    public func createTag() {
        Task {
            if let onCreateTag = onCreateTag,
               let tagID = await onCreateTag("New Tag", nil) {
                await MainActor.run {
                    selectedItem = .tag(tagID)
                    pendingEditTagID = tagID
                }
            }
        }
    }

    public func refresh() {
        // Will be connected to Core Data in later steps
    }
}
