import Combine
import Foundation
import WndrAutomation
import WndrData
import WndrKit

@MainActor
final class AppEnvironment: ObservableObject {
    @Published private(set) var isBootstrapped = false
    @Published private(set) var libraryURL: URL?
    @Published var shouldRegenerateThumbnails = false
    @Published var shouldReassignTagColors = false

    let persistenceController: PersistenceController
    let libraryRootStore: LibraryRootStore
    var libraryRootCoordinator: LibraryRootCoordinator
    let featureFlags: FeatureFlagStore
    let telemetry: TelemetryClient
    let automationCoordinator: AutomationCoordinator
    let documentService: DocumentService
    let annotationService: AnnotationService
    let collectionService: CollectionService
    let importService: ImportService
    let thumbnailService: ThumbnailService
    var importCoordinator: ImportCoordinator

    private var cancellables = Set<AnyCancellable>()

    init(
        persistenceController: PersistenceController = .shared,
        libraryRootStore: LibraryRootStore = LibraryRootStore(),
        featureFlags: FeatureFlagStore = FeatureFlagStore(defaults: .standard),
        telemetry: TelemetryClient = TelemetryClient(subsystem: "com.wndr.app"),
        automationCoordinator: AutomationCoordinator = AutomationCoordinator()
    ) {
        self.persistenceController = persistenceController
        self.libraryRootStore = libraryRootStore
        self.featureFlags = featureFlags
        self.telemetry = telemetry
        self.automationCoordinator = automationCoordinator
        self.libraryRootCoordinator = LibraryRootCoordinator(store: libraryRootStore, telemetry: telemetry)
        self.documentService = DocumentService(persistenceController: persistenceController)
        self.annotationService = AnnotationService(persistenceController: persistenceController)
        self.collectionService = CollectionService(persistenceController: persistenceController)
        self.importService = ImportService(
            persistenceController: persistenceController,
            libraryStore: libraryRootStore
        )
        self.thumbnailService = ThumbnailService(libraryStore: libraryRootStore)
        self.importCoordinator = ImportCoordinator(
            importService: importService,
            documentService: documentService,
            libraryRootCoordinator: libraryRootCoordinator,
            thumbnailService: thumbnailService
        )

        automationCoordinator.registerDefaults()

        // Sync libraryURL from coordinator to trigger SwiftUI updates
        libraryRootCoordinator.$libraryURL
            .receive(on: DispatchQueue.main)
            .sink { [weak self] url in
                self?.libraryURL = url
                guard let self, let url else { return }
                Task {
                    await self.repairStoredDocumentURLsIfNeeded(for: url)
                }
            }
            .store(in: &cancellables)
    }

    func bootstrap() async {
        guard isBootstrapped == false else { return }
        do {
            if let bookmark = try await libraryRootStore.restorePersistedBookmark() {
                libraryRootCoordinator.activate(url: bookmark)
            } else {
                telemetry.record(event: .librarySetupRequired)
            }
        } catch {
            telemetry.record(error)
            libraryRootCoordinator.presentRecovery(for: error)
        }
        isBootstrapped = true

        // One-time thumbnail regeneration for existing PDFs
        await regenerateThumbnailsIfNeeded()

        // One-time tag color assignment for existing tags
        await assignColorsToExistingTags()
    }

    // MARK: - One-Time Thumbnail Regeneration

    private static let thumbnailRegenerationKey = "wndr.thumbnails.regenerated.v1"

    /// Runs a one-time bulk regeneration of thumbnails for every existing PDF.
    /// Gated by a UserDefaults flag so it only executes once per library.
    private func regenerateThumbnailsIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: Self.thumbnailRegenerationKey) else { return }
        guard let libraryURL = libraryURL else { return }

        // Fetch all documents to get their IDs and PDF paths
        documentService.fetchAllDocuments()
        let documents: [(id: UUID, pdfURL: URL)] = documentService.documents.compactMap { dto in
            guard let url = dto.fileURL else { return nil }
            return (dto.id, url)
        }

        guard !documents.isEmpty else {
            // No documents yet — mark as done so we don't re-check every launch
            UserDefaults.standard.set(true, forKey: Self.thumbnailRegenerationKey)
            return
        }

        let logger = WndrLogger(category: "thumbnails")
        logger.info("Starting one-time thumbnail regeneration for \(documents.count) existing PDFs")

        let result = await thumbnailService.regenerateAllThumbnails(
            documents: documents,
            libraryURL: libraryURL
        )

        logger.info("One-time thumbnail regeneration finished — \(result.succeeded) succeeded, \(result.failed) failed")

        // Mark as complete so this never runs again
        UserDefaults.standard.set(true, forKey: Self.thumbnailRegenerationKey)
    }

    // MARK: - One-Time Tag Color Assignment

    private static let tagColorAssignmentKey = "wndr.tags.colors.assigned.v1"

    private func repairStoredDocumentURLsIfNeeded(for libraryURL: URL) async {
        let repairedCount = await documentService.repairStoredDocumentURLs(
            libraryURL: libraryURL,
            libraryStore: libraryRootStore
        )
        guard repairedCount > 0 else { return }

        telemetry.record(
            event: TelemetryEvent(
                name: "document_urls_repaired",
                metadata: ["count": String(repairedCount)]
            )
        )
    }

    /// Resets the tag color assignment flag, allowing colors to be reassigned.
    public func resetTagColorAssignmentFlag() {
        UserDefaults.standard.set(false, forKey: Self.tagColorAssignmentKey)
    }

    /// Assigns colors to existing tags that were created before automatic color assignment.
    /// Gated by a UserDefaults flag so it only executes once per library.
    private func assignColorsToExistingTags() async {
        guard !UserDefaults.standard.bool(forKey: Self.tagColorAssignmentKey) else { return }

        let logger = WndrLogger(category: "tags")
        logger.info("Starting one-time tag color assignment for existing tags")

        // Fetch all existing tags
        collectionService.fetchAllTags()
        let existingTags = collectionService.tags

        guard !existingTags.isEmpty else {
            // No tags yet — mark as done so we don't re-check every launch
            UserDefaults.standard.set(true, forKey: Self.tagColorAssignmentKey)
            return
        }

        // Check if any tags need color assignment (have default blue or no color)
        let defaultBlueColor = "#3B82F6"
        let tagsNeedingColors = existingTags.filter { tag in
            tag.color == nil || tag.color == defaultBlueColor
        }

        guard !tagsNeedingColors.isEmpty else {
            // All tags already have proper colors
            UserDefaults.standard.set(true, forKey: Self.tagColorAssignmentKey)
            logger.info("All tags already have assigned colors")
            return
        }

        logger.info("Assigning colors to \(tagsNeedingColors.count) existing tags")

        // Sort tags by name to ensure consistent ordering
        let sortedTags = tagsNeedingColors.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        // Assign colors from the palette
        for (index, tag) in sortedTags.enumerated() {
            let colorIndex = index % CollectionService.tagColorPalette.count
            let newColor = CollectionService.tagColorPalette[colorIndex]

            do {
                try await collectionService.updateTag(tag.id, color: newColor)
                logger.info("Assigned color \(newColor) to tag: \(tag.name)")
            } catch {
                logger.error("Failed to assign color to tag \(tag.name): \(error.localizedDescription)")
            }
        }

        // Mark as complete so this never runs again
        UserDefaults.standard.set(true, forKey: Self.tagColorAssignmentKey)
        logger.info("One-time tag color assignment completed")
    }
}
