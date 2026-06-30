import AppKit
import Foundation
import WndrData
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ImportCoordinator: ObservableObject {
    @Published var isImporting = false
    @Published var importProgress: ImportProgress?
    @Published var activeAlert: ImportAlert?
    @Published var statusMessage: String?
    @Published private(set) var lastImportedDocumentIDs: [UUID] = []

    private let importService: ImportService
    private let documentService: DocumentService
    private let libraryRootCoordinator: LibraryRootCoordinator
    private let thumbnailService: ThumbnailService

    struct ImportProgress {
        var current: Int
        var total: Int
        var currentFile: String
    }

    struct ImportAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    init(
        importService: ImportService,
        documentService: DocumentService,
        libraryRootCoordinator: LibraryRootCoordinator,
        thumbnailService: ThumbnailService
    ) {
        self.importService = importService
        self.documentService = documentService
        self.libraryRootCoordinator = libraryRootCoordinator
        self.thumbnailService = thumbnailService
    }

    func clearImportedDocumentIDs() {
        lastImportedDocumentIDs = []
    }

    func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.title = "Import Documents"
        panel.allowedContentTypes = [.pdf]

        guard panel.runModal() == .OK else { return }

        let urls = panel.urls
        guard !urls.isEmpty else { return }

        Task {
            await importDocuments(from: urls)
        }
    }

    func importDocuments(from urls: [URL]) async {
        guard let libraryURL = libraryRootCoordinator.libraryURL else {
            activeAlert = ImportAlert(
                title: "No Library",
                message: "Please select a library location first"
            )
            return
        }

        isImporting = true
        var successCount = 0
        var failureCount = 0
        var duplicateCount = 0
        var importedIDs: [UUID] = []

        await PerformanceMonitor.shared.measure(.importBatch, metadata: ["file_count": String(urls.count)]) {
            for (index, url) in urls.enumerated() {
                importProgress = ImportProgress(
                    current: index + 1,
                    total: urls.count,
                    currentFile: url.lastPathComponent
                )

                do {
                    let importedID = try await importService.importDocument(
                        from: url,
                        in: libraryURL,
                        copyFile: true
                    ).documentID
                    successCount += 1
                    importedIDs.append(importedID)
                    documentService.upsertDocument(importedID)

                    // Generate thumbnail for the imported document
                    if let document = documentService.getDocument(byID: importedID),
                       let fileURL = document.fileURL {
                        await PerformanceMonitor.shared.measure(.thumbnailGeneration) {
                            _ = await thumbnailService.thumbnailURL(for: importedID, pdfURL: fileURL, in: libraryURL)
                        }
                    }
                } catch ImportService.ImportError.duplicateDocument {
                    duplicateCount += 1
                } catch {
                    failureCount += 1
                }
            }
        }

        isImporting = false
        importProgress = nil
        lastImportedDocumentIDs = importedIDs

        // Show quiet status message instead of alert
        if successCount > 0 {
            if duplicateCount > 0 || failureCount > 0 {
                statusMessage = "\(successCount) imported, \(duplicateCount) skipped"
            } else {
                statusMessage = "\(successCount) document\(successCount == 1 ? "" : "s") added"
            }
        } else if duplicateCount > 0 {
            statusMessage = "Already in library"
        } else if failureCount > 0 {
            statusMessage = "Import failed"
        }

        // Auto-dismiss after 3 seconds
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            statusMessage = nil
        }
    }
}
