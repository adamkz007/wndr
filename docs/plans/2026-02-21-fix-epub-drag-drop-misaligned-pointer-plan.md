---
title: Fix Fatal Error with Misaligned Raw Pointer When Drag-Dropping EPUB Files
type: fix
status: active
date: 2026-02-21
---

# Fix Fatal Error with Misaligned Raw Pointer When Drag-Dropping EPUB Files

## Overview

The Look app crashes with "Fatal error: load from misaligned raw pointer" when users drag and drop EPUB files into the application. This crash does not occur when using the file picker import method or in Apple Books when handling the same files. The issue stems from unsafe memory access in the EPUB ZIP parser that assumes properly aligned memory, which isn't guaranteed with drag & drop data buffers.

## Problem Statement / Motivation

Users cannot reliably import EPUB files via drag and drop, which is a primary import method for document management apps. The crash is fatal and provides no recovery mechanism, resulting in complete data loss of any unsaved work. This significantly impacts the user experience and makes the EPUB feature appear broken despite being fully implemented.

The crash occurs specifically in `Sources/LookData/Sources/EPUBParser.swift` at lines 384 and 392 where `buffer.load(fromByteOffset:as:)` is used to read UInt16 and UInt32 values from potentially misaligned memory addresses.

## Proposed Solution

Replace unsafe aligned memory access with safe byte-by-byte reading in the ZIPReader implementation. This involves:

1. **Immediate fix**: Modify `readUInt16` and `readUInt32` methods in `EPUBParser.swift` to use manual byte reading
2. **Improve data handling**: Prioritize file URLs over in-memory data in drag & drop handlers
3. **Add error recovery**: Implement proper error handling to prevent fatal crashes

## Technical Considerations

### Memory Alignment Requirements
- `buffer.load(fromByteOffset:as:)` requires proper alignment (2-byte for UInt16, 4-byte for UInt32)
- Drag & drop via NSItemProvider may provide misaligned data buffers
- File-backed data (URLs) typically provides aligned memory access

### Platform Differences
- macOS uses AppKit-backed drag & drop with NSItemProvider
- Solution should remain robust across different drag data sources

### Performance Implications
- Manual byte reading is slightly slower than aligned loads
- Impact is negligible for EPUB parsing (one-time operation)
- Safety outweighs minor performance difference

## System-Wide Impact

- **Interaction graph**: Drag & drop → ImportCoordinator → ImportService → EPUBParser → ZIPReader (crash point)
- **Error propagation**: Currently no error handling - crash terminates entire app
- **State lifecycle risks**: Crash during import leaves no orphaned state (import not completed)
- **API surface parity**: File picker import works correctly, drag & drop needs same reliability
- **Integration test scenarios**:
  - Drag various EPUB files with different ZIP structures
  - Drag multiple files simultaneously
  - Drag corrupted/invalid EPUB files

## Acceptance Criteria

- [ ] EPUB files can be imported via drag & drop without crashing
- [ ] macOS drag & drop handles EPUB files correctly
- [ ] Invalid or corrupted EPUB files fail gracefully with error messages
- [ ] Performance of EPUB parsing remains acceptable (< 1 second for typical books)
- [ ] Existing file picker import continues to work
- [ ] All existing EPUB features (highlighting, customization) remain functional

## Success Metrics

- Zero crashes when drag & dropping valid EPUB files
- Graceful error handling for invalid files
- Import success rate matches file picker method
- No regression in EPUB parsing performance

## Dependencies & Risks

### Dependencies
- No external dependencies required
- Uses existing Swift standard library features

### Risks
- **Regression risk**: Low - isolated to ZIP reading logic
- **Performance risk**: Low - minimal impact from safe memory access
- **Data risk**: None - read-only operations

## Implementation Details

### Phase 1: Fix Memory Alignment Issue

**File: `Sources/LookData/Sources/EPUBParser.swift`**

Replace unsafe memory access in ZIPReader (lines 383-394):

```swift
// OLD (crashes on misaligned memory):
private func readUInt16(at offset: Int) -> UInt16? {
    guard offset + 2 <= data.count else { return nil }
    return data.withUnsafeBytes { buffer in
        buffer.load(fromByteOffset: offset, as: UInt16.self).littleEndian
    }
}

// NEW (safe for any alignment):
private func readUInt16(at offset: Int) -> UInt16? {
    guard offset + 2 <= data.count else { return nil }
    return data.withUnsafeBytes { buffer in
        let byte0 = buffer[offset]
        let byte1 = buffer[offset + 1]
        return UInt16(byte0) | (UInt16(byte1) << 8)
    }
}

// Similar fix for readUInt32:
private func readUInt32(at offset: Int) -> UInt32? {
    guard offset + 4 <= data.count else { return nil }
    return data.withUnsafeBytes { buffer in
        let byte0 = buffer[offset]
        let byte1 = buffer[offset + 1]
        let byte2 = buffer[offset + 2]
        let byte3 = buffer[offset + 3]
        return UInt32(byte0) |
               (UInt32(byte1) << 8) |
               (UInt32(byte2) << 16) |
               (UInt32(byte3) << 24)
    }
}
```

### Phase 2: Improve Drag & Drop Handler

**File: `Sources/LookKit/Sources/LibraryView.swift` (lines 332-339)**

Prioritize file URLs over data loading:

```swift
.onDrop(of: [.pdf, .epub], isTargeted: nil) { providers in
    for provider in providers {
        // Try to get file URL first (aligned memory access)
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { (url, error) in
                // Process URL-based import
            }
        } else {
            // Fallback to data if URL not available
            provider.loadDataRepresentation(forTypeIdentifier: UTType.epub.identifier) { (data, error) in
                // Process with alignment-safe parser
            }
        }
    }
    return true
}
```

### Phase 3: Add Error Recovery

**File: `Sources/LookData/Sources/ImportService.swift`**

Wrap EPUB parsing in proper error handling:

```swift
private func processEPUBImport(from url: URL) async throws -> Document {
    do {
        let metadata = try await EPUBParser.extractMetadata(from: url)
        // ... rest of import logic
    } catch {
        LookLogger.persistence.error("EPUB import failed: \(error)")
        throw ImportError.invalidEPUBFile(error.localizedDescription)
    }
}
```

## Testing Plan

1. **Unit Tests**
   - Test ZIPReader with various aligned/misaligned buffers
   - Test UInt16/UInt32 reading with edge cases
   - Verify little-endian conversion

2. **Integration Tests**
   - Import EPUBs via drag & drop
   - Import EPUBs via file picker
   - Test with various EPUB files (different publishers, sizes)
   - Test with corrupted ZIP structures

3. **Platform Testing**
   - macOS: Test drag from Finder
  - macOS: Test drag from Finder
   - Verify identical behavior across platforms

4. **Regression Testing**
   - Verify existing EPUB features still work
   - Test highlighting persistence
   - Test reader customization settings

## References & Research

### Internal References
- Bug location: `Sources/LookData/Sources/EPUBParser.swift:384`
- Drag handler: `Sources/LookKit/Sources/LibraryView.swift:332`
- Import service: `Sources/LookData/Sources/ImportService.swift:251`
- Working implementation: Apple Books (no crash with same files)

### External References
- [Swift Memory Layout and Alignment](https://developer.apple.com/documentation/swift/memorylayout)
- [Safe Buffer Pointer Access](https://developer.apple.com/documentation/swift/unsafebufferpointer)
- [NSItemProvider Drag and Drop](https://developer.apple.com/documentation/uikit/drag_and_drop)

### Related Work
- Original EPUB implementation: Completed in Phase 6 (Feb 7, 2026)
- STATUS.md: Documents EPUB feature as complete
