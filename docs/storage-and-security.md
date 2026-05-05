# Storage & Security

> **Last Updated:** February 7, 2026
> **Implementation Status:** Core storage complete, thumbnail caching implemented, encryption planned

## Local-First Storage ✅

### Library Root Selection
- Users select a library root directory during onboarding
- Security-scoped bookmark persisted for sandbox-safe access
- Bookmark stored in UserDefaults, restored on app launch
- `LibraryRootStore` manages all bookmark operations

### Directory Structure ✅
```text
Library Root/
├── PDFs/
│   └── <doc-uuid>/document.pdf     # Imported PDFs
├── Notes/
│   └── <note-uuid>.md              # Markdown note files
├── Attachments/
│   └── <attachment-uuid>/<file>    # Note attachments
├── Index/
│   ├── Wndr.sqlite                 # Core Data store
│   ├── Wndr.sqlite-shm             # SQLite shared memory
│   ├── Wndr.sqlite-wal             # SQLite write-ahead log
│   └── Thumbnails/
│       └── <doc-uuid>.png          # 80×100px thumbnails (auto-generated on import)
└── Cache/
    ├── OCR/<doc-uuid>.json         # OCR results (planned)
    └── Previews/                   # Generated page previews (planned)
```

### File Management ✅
- PDFs copied to library during import (not referenced)
- Each document in its own UUID-named directory
- Notes stored as human-readable Markdown files
- All paths stored as relative URLs in Core Data

## Import Pipeline ✅

### Deduplication
- SHA-256 checksum computed during import
- Duplicate detection prevents re-importing same file
- User notified if duplicate detected

### Metadata Extraction
- PDF title, authors, page count extracted automatically
- Creation date captured from file metadata
- OCR status detected (text layer presence)

### Thumbnail Caching ✅
- `ThumbnailService` generates 80×100px PNG thumbnails from PDF first page
- Stored in `Index/Thumbnails/<doc-uuid>.png`
- Generated automatically on import
- Validated on access (minimum 200 bytes to detect corrupt/blank images)
- Bulk regeneration on first launch (one-time, gated by UserDefaults flag)
- Thread-safe (actor-based) rendering via CGBitmapContext

### Storage Calculation ✅
- `DocumentService.calculateTotalStorage()` computes total library size
- Recursive directory enumeration with error handling
- Displayed in content list status bar

## Backup & Restore

### Implemented ✅
- Standard file-based backup (Time Machine compatible)
- All data in user-accessible directory structure
- Core Data SQLite uses journaling for integrity

### Planned 🚧
- Built-in export to portable archive (zip + manifest)
- Checksum verification audit
- Restore flow with UUID relinking
- Time Machine reminder if library not in backup

## Security Controls

### Implemented ✅
- macOS sandbox compliance
- Security-scoped bookmarks for persistent access
- No network services or telemetry by default
- All data stored locally

### Planned 🚧
- SQLCipher encryption for Core Data + FTS databases
- User-supplied passphrase stored in Keychain
- Sensitive collection locking (passcode/Touch ID)
- Audit log of imports, deletions, metadata edits

## Privacy Considerations ✅

### Current Implementation
- No network requests during normal operation
- No analytics or crash reporting without consent
- No cloud dependencies
- Spotlight integration not implemented (privacy default)

### Data Handling
- User data never leaves device
- No external service dependencies
- Markdown files editable outside app
- PDFs remain standard format

## Sandboxing ✅

### Entitlements
- App sandboxed per macOS requirements
- User-selected directories via security-scoped bookmarks
- Read/write access to library root only

### File Access Pattern
```swift
// Accessing library files
let url = libraryRootStore.libraryURL
let success = url.startAccessingSecurityScopedResource()
defer { url.stopAccessingSecurityScopedResource() }

// Perform file operations...
```

## Compliance Notes

### Implemented
- Hardened Runtime enabled
- Sandboxed application
- Local-only data storage

### Planned 🚧
- GDPR/CCPA data export functionality
- Secure wipe documentation
- Third-party library license audit

## Key Files

| File | Purpose |
|------|---------|
| `LibraryRootStore.swift` | Security bookmark management |
| `LibraryRootCoordinator.swift` | Library selection UI flow |
| `PersistenceController.swift` | Core Data stack with merge policies |
| `ImportService.swift` | File copying and checksum verification |
| `ThumbnailService.swift` | PDF thumbnail generation and caching |
| `DocumentService.swift` | Storage calculation, content search |
