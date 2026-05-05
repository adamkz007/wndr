// iPadKeyboardShortcuts.swift
// Keyboard shortcuts for external keyboards on iPadOS.
// Mirrors the macOS shortcuts for consistent cross-platform experience.

import SwiftUI

/// Keyboard shortcut modifiers that apply to iPadOS views.
/// These are added via `.keyboardShortcut()` modifiers on buttons/actions
/// and show in the iPad's keyboard shortcut overlay (hold ⌘).
///
/// Standard shortcuts carried over from macOS:
///   ⌘I  — Import Document
///   ⌘N  — New Note
///   ⌘S  — Save Note
///   ⌥⌘I — Toggle Inspector
///   ⌘,⇧ — Change Library
///
/// All shortcuts are applied inline in the views via `.keyboardShortcut()`.
/// This file provides additional discoverability.

struct iPadShortcutOverlay: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Library") {
                    ShortcutRow(keys: "⌘ I", description: "Import PDF")
                    ShortcutRow(keys: "⌘ N", description: "New Note")
                }

                Section("Editor") {
                    ShortcutRow(keys: "⌘ S", description: "Save Note")
                }

                Section("Navigation") {
                    ShortcutRow(keys: "⌥ ⌘ I", description: "Toggle Inspector")
                }

                Section("PDF Viewer") {
                    ShortcutRow(keys: "← →", description: "Previous / Next Page")
                    ShortcutRow(keys: "⌘ + / ⌘ -", description: "Zoom In / Out")
                }
            }
            .navigationTitle("Keyboard Shortcuts")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct ShortcutRow: View {
    let keys: String
    let description: String

    var body: some View {
        HStack {
            Text(description)
            Spacer()
            Text(keys)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.12))
                )
        }
    }
}
