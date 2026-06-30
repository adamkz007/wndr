// PlatformCompat.swift
// Type aliases and helpers for the macOS app.
// Import this module to use PlatformImage, PlatformColor, and shared view helpers.

import AppKit
import PDFKit
import SwiftUI

public typealias PlatformImage = NSImage
public typealias PlatformColor = NSColor

extension NSImage {
    /// Convenience initializer to create an NSImage from a CGImage.
    public convenience init(cgImage: CGImage) {
        self.init(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

// MARK: - Color Helpers

extension Color {
    /// Background color for controls/toolbars.
    public static var platformControlBackground: Color {
        Color(NSColor.controlBackgroundColor)
    }

    /// Background color for text areas.
    public static var platformTextBackground: Color {
        Color(NSColor.textBackgroundColor)
    }

    /// Separator color.
    public static var platformSeparator: Color {
        Color(NSColor.separatorColor)
    }

    /// Window background color.
    public static var platformWindowBackground: Color {
        Color(NSColor.windowBackgroundColor)
    }
}

// MARK: - Image Loading

extension PlatformImage {
    /// Load an image from a file URL.
    public static func loadFromURL(_ url: URL) -> PlatformImage? {
        NSImage(contentsOf: url)
    }

    /// Convert to SwiftUI Image.
    public var swiftUIImage: Image {
        Image(nsImage: self)
    }
}

// MARK: - URL Opening

public func openURL(_ url: URL) {
    NSWorkspace.shared.open(url)
}

// MARK: - PNG Data

extension PlatformImage {
    /// Returns PNG data for this image.
    public var pngRepresentation: Data? {
        guard let tiffData = self.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

// MARK: - PDFKit Color

/// Returns a native color for annotation use (with alpha for highlight translucency).
public func annotationPlatformColor(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 0.4) -> PlatformColor {
    NSColor(red: red, green: green, blue: blue, alpha: alpha)
}

/// Returns a system-named platform color.
public func systemPlatformColor(_ name: String) -> PlatformColor {
    switch name {
    case "yellow": return .systemYellow
    case "green": return .systemGreen
    case "blue": return .systemBlue
    case "pink": return .systemPink
    case "orange": return .systemOrange
    case "purple": return .systemPurple
    default: return .systemYellow
    }
}

// MARK: - Hover Modifier

extension View {
    /// Applies `.onHover` on macOS.
    public func onHoverIfAvailable(perform action: @escaping (Bool) -> Void) -> some View {
        self.onHover(perform: action)
    }
}
