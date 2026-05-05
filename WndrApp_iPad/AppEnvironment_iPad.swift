// AppEnvironment_iPad.swift
// Central dependency container for the iPadOS app.

import Combine
import Foundation
import WndrData
import WndrKit

@MainActor
final class AppEnvironment_iPad: ObservableObject {
    @Published private(set) var isBootstrapped = false
    @Published private(set) var libraryURL: URL?

    let persistenceController: PersistenceController
    let libraryRootStore: LibraryRootStore
    var libraryCoordinator: LibraryRootCoordinator_iPad
    let featureFlags: FeatureFlagStore
    let telemetry: TelemetryClient
    let documentService: DocumentService
    let annotationService: AnnotationService
    let collectionService: CollectionService
    let importService: ImportService
    let thumbnailService: ThumbnailService
    var importCoordinator: ImportCoordinator_iPad

    private var cancellables = Set<AnyCancellable>()

    init(
        persistenceController: PersistenceController = .shared,
        libraryRootStore: LibraryRootStore = LibraryRootStore(),
        featureFlags: FeatureFlagStore = FeatureFlagStore(defaults: .standard),
        telemetry: TelemetryClient = TelemetryClient(subsystem: "com.wndr.app")
    ) {
        self.persistenceController = persistenceController
        self.libraryRootStore = libraryRootStore
        self.featureFlags = featureFlags
        self.telemetry = telemetry
        self.libraryCoordinator = LibraryRootCoordinator_iPad(store: libraryRootStore, telemetry: telemetry)
        self.documentService = DocumentService(persistenceController: persistenceController)
        self.annotationService = AnnotationService(persistenceController: persistenceController)
        self.collectionService = CollectionService(persistenceController: persistenceController)
        self.importService = ImportService(
            persistenceController: persistenceController,
            libraryStore: libraryRootStore
        )
        self.thumbnailService = ThumbnailService(libraryStore: libraryRootStore)
        self.importCoordinator = ImportCoordinator_iPad(
            importService: importService,
            documentService: documentService,
            thumbnailService: thumbnailService
        )

        // Sync libraryURL from coordinator to trigger SwiftUI updates
        libraryCoordinator.$libraryURL
            .receive(on: DispatchQueue.main)
            .sink { [weak self] url in
                self?.libraryURL = url
            }
            .store(in: &cancellables)
    }

    func bootstrap() async {
        guard isBootstrapped == false else { return }

        // Try to restore existing library bookmark
        do {
            if let bookmark = try await libraryRootStore.restorePersistedBookmark() {
                libraryCoordinator.activate(url: bookmark)
            } else {
                // On iPadOS, auto-create library in Documents if none exists
                await autoCreateLibraryIfNeeded()
            }
        } catch {
            telemetry.record(error)
            // Fallback: auto-create
            await autoCreateLibraryIfNeeded()
        }

        isBootstrapped = true

        // One-time thumbnail regeneration
        await regenerateThumbnailsIfNeeded()

        // One-time tag color assignment for existing tags
        await assignColorsToExistingTags()
    }

    /// Creates a default library in the app's Documents directory.
    func createDefaultLibrary() {
        Task {
            let defaultURL = await libraryRootStore.defaultiPadLibraryURL()
            do {
                try await libraryRootStore.createLibraryStructure(at: defaultURL)
                try await libraryRootStore.persistBookmark(for: defaultURL)
                await MainActor.run {
                    libraryCoordinator.activate(url: defaultURL)
                }
            } catch {
                telemetry.record(error)
                libraryCoordinator.activeAlert = AlertDescriptor(
                    title: "Library Creation Failed",
                    message: error.localizedDescription,
                    primaryButton: .init(title: "Try Again") { [weak self] in
                        self?.createDefaultLibrary()
                    },
                    secondaryButton: .init(title: "Cancel", role: .cancel)
                )
            }
        }
    }

    private func autoCreateLibraryIfNeeded() async {
        let defaultURL = await libraryRootStore.defaultiPadLibraryURL()
        let fm = FileManager.default
        // Check if library structure exists
        let indexPath = defaultURL.appendingPathComponent("Index", isDirectory: true).path
        if fm.fileExists(atPath: indexPath) {
            // Library exists, activate it
            libraryCoordinator.activate(url: defaultURL)
            try? await libraryRootStore.persistBookmark(for: defaultURL)
        }
        // Otherwise, wait for user to tap "Create Library"
    }

    // MARK: - One-Time Thumbnail Regeneration

    private static let thumbnailRegenerationKey = "wndr.thumbnails.regenerated.v1"

    private func regenerateThumbnailsIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: Self.thumbnailRegenerationKey) else { return }
        guard let libraryURL = libraryURL else { return }

        documentService.fetchAllDocuments()
        let documents: [(id: UUID, pdfURL: URL)] = documentService.documents.compactMap { dto in
            guard let url = dto.fileURL else { return nil }
            return (dto.id, url)
        }

        guard !documents.isEmpty else {
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
        UserDefaults.standard.set(true, forKey: Self.thumbnailRegenerationKey)
    }

    // MARK: - One-Time Tag Color Assignment

    private static let tagColorAssignmentKey = "wndr.tags.colors.assigned.v1"

    private func assignColorsToExistingTags() async {
        guard !UserDefaults.standard.bool(forKey: Self.tagColorAssignmentKey) else { return }

        let logger = WndrLogger(category: "tags")
        logger.info("Starting one-time tag color assignment for existing tags")

        // Fetch all existing tags
        collectionService.fetchAllTags()
        let existingTags = collectionService.tags

        guard !existingTags.isEmpty else {
            UserDefaults.standard.set(true, forKey: Self.tagColorAssignmentKey)
            return
        }

        // Check if any tags need color assignment (have default blue or no color)
        let defaultBlueColor = "#3B82F6"
        let tagsNeedingColors = existingTags.filter { tag in
            tag.color == nil || tag.color == defaultBlueColor
        }

        guard !tagsNeedingColors.isEmpty else {
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

        UserDefaults.standard.set(true, forKey: Self.tagColorAssignmentKey)
        logger.info("One-time tag color assignment completed")
    }
}
