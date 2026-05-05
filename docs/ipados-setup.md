# iPadOS Target Setup Guide

This document explains how to add the iPadOS target to the Wndr Xcode project.

## Overview

The Wndr codebase now supports both macOS and iPadOS through shared frameworks with platform-conditional compilation. The shared frameworks (`WndrKit`, `WndrData`, `WndrPDF`, `WndrNotes`, `WndrAutomation`) compile for both platforms. Platform-specific app shells live in:

- `Sources/WndrApp/` — macOS entry point
- `Sources/WndrApp_iPad/` — iPadOS entry point

## Adding the iPadOS Target in Xcode

### Step 1: Add New Target

1. Open `Wndr.xcodeproj` in Xcode
2. Go to **File → New → Target...**
3. Select **iOS → App**
4. Configure the fields as follows:
   - **Product Name:** `WndrApp_iPad`
   - **Team:** Select your development team (e.g. "Adam KZ (Personal Team)")
   - **Organization Identifier:** `com.wndr` — This is the reverse-DNS prefix that, combined with the Product Name, forms the Bundle Identifier. Use `com.wndr` to keep it consistent with the macOS target (`com.wndr.app`). The resulting Bundle Identifier will be `com.wndr.WndrApp-iPad`. You can edit it later under the target's **General** tab if you prefer `com.wndr.app.ipad`.
   - **Interface:** SwiftUI
   - **Language:** Swift
   - **Testing System:** None (tests will be added later)
   - **Storage:** None (the project uses Core Data via the `WndrData` framework, not SwiftData)
   - Leave **Host in CloudKit** unchecked
   - **Project:** Wndr
5. Click **Finish**

### Step 2: Remove Auto-Generated Files

Xcode creates default files. Remove them and use our source files instead:

1. Delete the auto-generated `ContentView.swift`, `WndrApp_iPadApp.swift`, and `Assets.xcassets` from the new target
2. Add the following source files to the `WndrApp_iPad` target:
   - `Sources/WndrApp_iPad/Sources/WndrApp_iPad.swift`
   - `Sources/WndrApp_iPad/Sources/AppEnvironment_iPad.swift`
   - `Sources/WndrApp_iPad/Sources/LibraryRootCoordinator_iPad.swift`
   - `Sources/WndrApp_iPad/Sources/ImportCoordinator_iPad.swift`
   - `Sources/WndrApp_iPad/Sources/ContentWrapper_iPad.swift`
   - `Sources/WndrApp_iPad/Sources/iPadKeyboardShortcuts.swift`
3. Add `Sources/WndrApp_iPad/Resources/Info.plist` as the Info.plist for the target

### Step 3: Add Framework Dependencies

The iPadOS target needs to link the same shared frameworks:

1. In the **Project Navigator** (left sidebar), click the top-level **Wndr** project file (the blue icon at the very top of the file tree)
2. In the editor area that appears, you'll see a list of **TARGETS** in the left column. Click **WndrApp_iPad**
3. Along the top of the editor you'll see tabs: **General**, **Signing & Capabilities**, **Resource Tags**, **Info**, **Build Settings**, etc. Click the **General** tab
4. Scroll down to the **Frameworks, Libraries, and Embedded Content** section
5. Click the **+** button at the bottom of that section
6. In the search/filter dialog, find and add each of these (one at a time):
   - `WndrKit.framework`
   - `WndrData.framework`
   - `WndrPDF.framework`
   - `WndrNotes.framework`
   - `WndrAutomation.framework`
7. For each framework, make sure the **Embed** column says **Do Not Embed** (since they're built as part of the same project, not external binaries)

### Step 4: Configure Framework Targets for iOS

Each shared framework needs to be compiled for iOS as well:

1. For each framework target (`WndrKit`, `WndrData`, `WndrPDF`, `WndrNotes`, `WndrAutomation`):
   - Select the target → **Build Settings**
   - Set **Supported Platforms** to include `iOS`
   - Set **iOS Deployment Target** to `17.0`
   - Or add `iOS` to `SUPPORTED_PLATFORMS`

**Alternative (simpler):** In the project-level build settings, set `SUPPORTED_PLATFORMS = "macosx iphonesimulator iphoneos"` and `TARGETED_DEVICE_FAMILY = "1,2"`.

### Step 5: Add Shared Support Files

Make sure `Shared/Support/Telemetry.swift` is included in the iPadOS target's compile sources.

### Step 6: Add Core Data Model

The `WndrModel.xcdatamodeld` in `WndrData` must be accessible to the iPadOS target. Since it's in the `WndrData` framework (which is linked), this should work automatically.

### Step 7: Configure Signing & Capabilities

1. Select the `WndrApp_iPad` target
2. Under **Signing & Capabilities**:
   - Enable **Automatic Signing**
   - Set your Development Team
3. Optionally add capabilities:
   - **iCloud** (for future cross-device sync)
   - **App Groups** (for shared data between extensions)

## Build Settings

Key build settings for the iPadOS target:

```
PRODUCT_BUNDLE_IDENTIFIER = com.wndr.app.ipad
INFOPLIST_FILE = Sources/WndrApp_iPad/Resources/Info.plist
TARGETED_DEVICE_FAMILY = 2  (iPad only)
IPHONEOS_DEPLOYMENT_TARGET = 17.0
SWIFT_VERSION = 5.9
```

## Architecture Decisions

### Storage

- **macOS:** User-selected library root via `NSOpenPanel` + security-scoped bookmarks
- **iPadOS:** Library stored in app's `Documents/Library/` directory. Auto-created on first launch. Accessible via Files.app.

### File Import

- **macOS:** `NSOpenPanel` for file selection
- **iPadOS:** `UIDocumentPickerViewController` presented as a sheet. Files copied into the app sandbox.

### UI Adaptations

- **HSplitView** (macOS-only) → `GeometryReader` + `HStack` on iPadOS
- **NSViewRepresentable** → `UIViewRepresentable` for `PDFView`
- **`.onHover`** → No-op on iPadOS (not applicable without pointer)
- **`.help()`** → Removed on iPadOS (tooltip concept doesn't apply)
- **`.menuStyle(.borderlessButton)`** → Standard menu on iPadOS

### Performance

- PDF rendering uses `PDFView.usePageViewController(true)` on iPadOS for smooth touch scrolling
- Thumbnails use `CGBitmapContext` (not `NSImage.lockFocus`) for thread-safe cross-platform rendering
- Same Core Data merge policies and background contexts

### Apple Pencil

- PDF annotation highlights work with Apple Pencil through `PDFView`'s built-in selection handling
- Same debounced auto-highlight behavior as macOS
- Color presets and annotation tools identical

## Testing

Build and run the `WndrApp_iPad` scheme on an iPad simulator or device:

```bash
xcodebuild -scheme WndrApp_iPad -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' build
```

## Feature Parity Checklist

| Feature | macOS | iPadOS |
|---------|-------|--------|
| Three-pane NavigationSplitView | ✅ | ✅ |
| PDF import with deduplication | ✅ | ✅ |
| PDF viewing with zoom/navigation | ✅ | ✅ |
| PDF annotations (highlight/color) | ✅ | ✅ |
| PDF thumbnail sidebar | ✅ | ✅ |
| Markdown editor with live preview | ✅ | ✅ |
| Formatting toolbar | ✅ | ✅ |
| Auto-save with debounce | ✅ | ✅ |
| Content search (filename + body) | ✅ | ✅ |
| Collections & Tags | ✅ | ✅ |
| Document context menus | ✅ | ✅ (long-press) |
| Drag-and-drop import | ✅ | ✅ |
| Document info popover | ✅ | ✅ |
| Status bar with item count | ✅ | ✅ |
| Light/dark mode | ✅ | ✅ |
| Keyboard shortcuts | ✅ | ✅ (external keyboard) |
| About panel | ✅ | — (not applicable) |
| AppleScript | ✅ | — (not available on iOS) |
| Security-scoped bookmarks | ✅ | — (uses app sandbox) |
| Apple Pencil annotation | — | ✅ |
| Touch-optimized PDF scrolling | — | ✅ |
