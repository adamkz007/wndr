// LibraryRootCoordinator_iPad.swift
// iPadOS library root management. Uses app sandbox (Documents directory)
// instead of NSOpenPanel-based folder selection.

import Combine
import Foundation
import SwiftUI
import WndrData
import WndrKit

@MainActor
final class LibraryRootCoordinator_iPad: ObservableObject, LibraryRootHandling {
    @Published private(set) var libraryURL: URL?
    @Published var activeAlert: AlertDescriptor?

    private let store: LibraryRootStore
    private let telemetry: TelemetryClient

    init(store: LibraryRootStore, telemetry: TelemetryClient) {
        self.store = store
        self.telemetry = telemetry
    }

    /// On iPadOS, "choosing" a library just creates the default one.
    func presentLibraryChooser() {
        Task {
            let defaultURL = await store.defaultiPadLibraryURL()
            do {
                try await store.createLibraryStructure(at: defaultURL)
                try await store.persistBookmark(for: defaultURL)
                activate(url: defaultURL)
                telemetry.record(event: .librarySelectionSucceeded)
            } catch {
                telemetry.record(error)
                presentRecovery(for: error)
            }
        }
    }

    func activate(url: URL) {
        libraryURL = url
    }

    func presentRecovery(for error: Error) {
        activeAlert = AlertDescriptor(
            title: "Library Access Failed",
            message: error.localizedDescription,
            primaryButton: .init(title: "Retry") { [weak self] in
                self?.presentLibraryChooser()
            },
            secondaryButton: .init(title: "Cancel", role: .cancel)
        )
    }
}
