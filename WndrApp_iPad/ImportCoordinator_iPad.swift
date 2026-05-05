// ImportCoordinator_iPad.swift
// iPadOS document import using UIDocumentPickerViewController.

import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WndrData

@MainActor
final class ImportCoordinator_iPad: ObservableObject {
    @Published var isImporting = false
    @Published var importProgress: ImportProgress?
    @Published var activeAlert: ImportAlert?
    @Published var statusMessage: String?
    @Published var showDocumentPicker = false

    /// Set this before import begins so documents can be imported to the correct library.
    var libraryURL: URL?

    private let importService: ImportService
    private let documentService: DocumentService
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
        thumbnailService: ThumbnailService
    ) {
        self.importService = importService
        self.documentService = documentService
        self.thumbnailService = thumbnailService
    }

    /// Present the iPadOS document picker for importing PDFs.
    func presentImportPicker() {
        showDocumentPicker = true
    }

    /// Import documents from the provided URLs (called by document picker callback).
    func importDocuments(from urls: [URL]) async {
        guard let libraryURL = libraryURL else {
            activeAlert = ImportAlert(
                title: "No Library",
                message: "Please set up a library location first"
            )
            return
        }

        isImporting = true
        var successCount = 0
        var failureCount = 0
        var duplicateCount = 0

        for (index, url) in urls.enumerated() {
            importProgress = ImportProgress(
                current: index + 1,
                total: urls.count,
                currentFile: url.lastPathComponent
            )

            // iPadOS: gain access to security-scoped resource
            let didStart = url.startAccessingSecurityScopedResource()
            defer {
                if didStart { url.stopAccessingSecurityScopedResource() }
            }

            do {
                let importedID = try await importService.importDocument(
                    from: url,
                    in: libraryURL,
                    copyFile: true
                ).documentID
                successCount += 1

                // Generate thumbnail
                if let document = documentService.getDocument(byID: importedID),
                   let pdfURL = document.fileURL {
                    _ = await thumbnailService.thumbnailURL(for: importedID, pdfURL: pdfURL, in: libraryURL)
                }
            } catch ImportService.ImportError.duplicateDocument {
                duplicateCount += 1
            } catch {
                failureCount += 1
            }
        }

        isImporting = false
        importProgress = nil

        documentService.fetchAllDocuments()

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

        // Auto-dismiss
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            statusMessage = nil
        }
    }
}

// MARK: - Document Picker SwiftUI Wrapper

struct DocumentPickerView: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf, .epub], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void

        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            // No action needed
        }
    }
}
