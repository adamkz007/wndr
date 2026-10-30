import AppKit
import Combine
import Foundation
import SwiftUI
import WndrData
import WndrKit

@MainActor
final class LibraryRootCoordinator: ObservableObject, LibraryRootHandling {
    @Published private(set) var libraryURL: URL?
    @Published var activeAlert: AlertDescriptor?

    /// Opens a library's resources (e.g. its database) before it becomes active.
    var prepareLibrary: ((URL) throws -> Void)?

    private let store: LibraryRootStore
    private let telemetry: TelemetryClient

    init(store: LibraryRootStore, telemetry: TelemetryClient) {
        self.store = store
        self.telemetry = telemetry
    }

    func presentLibraryChooser() {
        let panel = NSOpenPanel()
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.title = "Choose Library Location"

        guard panel.runModal() == .OK, let url = panel.url else {
            telemetry.record(event: .librarySelectionCancelled)
            return
        }

        // Only remember a library once it has opened, so a broken one is not restored on next launch.
        guard activate(url: url) else { return }
        Task {
            do {
                try await store.persistBookmark(for: url)
                telemetry.record(event: .librarySelectionSucceeded)
            } catch {
                telemetry.record(error)
                presentRecovery(for: error)
            }
        }
    }

    /// Opens the library and makes it active. On failure, shows a recovery alert and
    /// leaves the current library (if any) in place.
    @discardableResult
    func activate(url: URL) -> Bool {
        do {
            try prepareLibrary?(url)
        } catch {
            telemetry.record(error)
            presentRecovery(for: error)
            return false
        }
        libraryURL = url
        return true
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

struct AlertDescriptor: Identifiable {
    struct ButtonDescriptor {
        let title: String
        var role: ButtonRole?
        var action: (() -> Void)?

        init(title: String, role: ButtonRole? = nil, action: (() -> Void)? = nil) {
            self.title = title
            self.role = role
            self.action = action
        }
    }

    let id = UUID()
    let title: String
    let message: String
    var primaryButton: ButtonDescriptor
    var secondaryButton: ButtonDescriptor?

    func toSwiftUIAlert() -> Alert {
        if let secondaryButton {
            return Alert(
                title: Text(title),
                message: Text(message),
                primaryButton: .init(primaryButton),
                secondaryButton: .init(secondaryButton)
            )
        } else {
            return Alert(
                title: Text(title),
                message: Text(message),
                dismissButton: .init(primaryButton)
            )
        }
    }
}

private extension Alert.Button {
    init(_ descriptor: AlertDescriptor.ButtonDescriptor) {
        let action = descriptor.action ?? {}
        if descriptor.role == .cancel {
            self = .cancel(Text(descriptor.title), action: action)
        } else if descriptor.role == .destructive {
            self = .destructive(Text(descriptor.title), action: action)
        } else {
            self = .default(Text(descriptor.title), action: action)
        }
    }
}
