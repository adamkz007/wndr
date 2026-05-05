// PlatformCompat.swift
// Cross-platform type aliases and helpers for macOS + iPadOS support.
// Import this module to use PlatformImage, PlatformColor, and platform-adaptive views.

import SwiftUI

#if canImport(AppKit)
import AppKit

public typealias PlatformImage = NSImage
public typealias PlatformColor = NSColor

extension NSImage {
    /// Convenience initializer to create an NSImage from a CGImage.
    public convenience init(cgImage: CGImage) {
        self.init(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

#elseif canImport(UIKit)
import UIKit

public typealias PlatformImage = UIImage
public typealias PlatformColor = UIColor
#endif

// MARK: - Cross-Platform Color Helpers

extension Color {
    /// Platform-adaptive background color for controls/toolbars.
    public static var platformControlBackground: Color {
        #if canImport(AppKit)
        return Color(NSColor.controlBackgroundColor)
        #else
        return Color(UIColor.secondarySystemBackground)
        #endif
    }

    /// Platform-adaptive background color for text areas.
    public static var platformTextBackground: Color {
        #if canImport(AppKit)
        return Color(NSColor.textBackgroundColor)
        #else
        return Color(UIColor.systemBackground)
        #endif
    }

    /// Platform-adaptive separator color.
    public static var platformSeparator: Color {
        #if canImport(AppKit)
        return Color(NSColor.separatorColor)
        #else
        return Color(UIColor.separator)
        #endif
    }

    /// Platform-adaptive window/scene background.
    public static var platformWindowBackground: Color {
        #if canImport(AppKit)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(UIColor.systemBackground)
        #endif
    }
}

// MARK: - Cross-Platform Image Loading

extension PlatformImage {
    /// Load an image from a file URL on either platform.
    public static func loadFromURL(_ url: URL) -> PlatformImage? {
        #if canImport(AppKit)
        return NSImage(contentsOf: url)
        #else
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
        #endif
    }

    /// Convert to SwiftUI Image.
    public var swiftUIImage: Image {
        #if canImport(AppKit)
        return Image(nsImage: self)
        #else
        return Image(uiImage: self)
        #endif
    }
}

// MARK: - Platform-Adaptive URL Opening

public func openURL(_ url: URL) {
    #if canImport(AppKit)
    NSWorkspace.shared.open(url)
    #else
    UIApplication.shared.open(url)
    #endif
}

// MARK: - Platform-Adaptive PNG Data

extension PlatformImage {
    /// Returns PNG data for this image on either platform.
    public var pngRepresentation: Data? {
        #if canImport(AppKit)
        guard let tiffData = self.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
        #else
        return self.pngData()
        #endif
    }
}

// MARK: - Cross-Platform PDFKit Color

import PDFKit

/// Returns a platform-native color for annotation use (with alpha for highlight translucency).
public func annotationPlatformColor(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 0.4) -> PlatformColor {
    #if canImport(AppKit)
    return NSColor(red: red, green: green, blue: blue, alpha: alpha)
    #else
    return UIColor(red: red, green: green, blue: blue, alpha: alpha)
    #endif
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

// MARK: - Hover Modifier (no-op on iOS)

extension View {
    /// Applies `.onHover` on macOS, no-op on iOS (where hover is not common).
    public func onHoverIfAvailable(perform action: @escaping (Bool) -> Void) -> some View {
        #if canImport(AppKit)
        return self.onHover(perform: action)
        #else
        return self
        #endif
    }
}
