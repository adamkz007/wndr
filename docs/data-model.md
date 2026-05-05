# Data Model

> **Last Updated:** February 7, 2026
> **Implementation Status:** Core Data model complete, FTS pending

## Entities

All entities are implemented in `WndrModel.xcdatamodeld`.

### Document ✅
| Attribute | Type | Description |
|-----------|------|-------------|
| `id` | UUID | Primary identifier |
| `title` | String | Document title (extracted or user-set) |
| `subtitle` | String? | Optional subtitle |
| `authors` | Transformable | Array of author names |
| `source` | String? | Journal, publisher |
| `publicationDate` | Date? | Publication date |
| `keywords` | Transformable | Set of keywords |
| `checksum` | String | SHA-256 hash for deduplication |
| `fileURL` | String? | Relative path within library |
| `pageCount` | Int16 | Number of pages |
| `ocrStatus` | String | pending, processing, complete, failed |
| `createdAt` | Date | Import timestamp |
| `updatedAt` | Date | Last modification |

**Relationships:** `annotations`, `notes`, `collections`, `tags`, `attachments`

### Note ✅
| Attribute | Type | Description |
|-----------|------|-------------|
| `id` | UUID | Primary identifier |
| `title` | String | Note title |
| `body` | String | Markdown content |
| `createdAt` | Date | Creation timestamp |
| `updatedAt` | Date | Last modification |
| `frontMatter` | String? | YAML/JSON metadata |
| `pinned` | Bool | Pin to top of list |

**Relationships:** `document` (optional), `annotations`, `links`, `attachments`, `tags`, `collections`

### Annotation ✅
| Attribute | Type | Description |
|-----------|------|-------------|
| `id` | UUID | Primary identifier |
| `kind` | String | highlight, underline, freehand, note |
| `colorCategory` | String | yellow, green, blue, pink, orange, purple |
| `pageIndex` | Int16 | Zero-based page number |
| `rects` | Binary | JSON array of `[[String: Double]]` normalized coordinates |
| `textSnippet` | String? | Selected text content |
| `createdAt` | Date | Creation timestamp |
| `updatedAt` | Date | Last modification |

**Relationships:** `document`, `note` (optional), `tags`

**Note:** `rects` is stored as Binary (not Transformable) containing JSON-serialized coordinate data with `Double` values.

### DocumentCollection ✅
| Attribute | Type | Description |
|-----------|------|-------------|
| `id` | UUID | Primary identifier |
| `name` | String | Collection name |
| `icon` | String? | SF Symbol name |
| `sortOrder` | Int16 | Display order |
| `kind` | String | manual, smart, bundle |
| `ruleDefinition` | String? | JSON for smart group rules |

**Relationships:** `documents`, `notes`, `parentCollection`, `childCollections`

**Note:** Entity renamed from `Collection` to `DocumentCollection` to avoid Swift stdlib conflict.

### Tag ✅
| Attribute | Type | Description |
|-----------|------|-------------|
| `id` | UUID | Primary identifier |
| `name` | String | Tag name |
| `color` | String? | Hex color code |
| `parentTag` | Tag? | For hierarchical tags |

**Relationships:** `documents`, `notes`, `annotations`

### Attachment ✅
| Attribute | Type | Description |
|-----------|------|-------------|
| `id` | UUID | Primary identifier |
| `filename` | String | Original filename |
| `type` | String | image, audio, file |
| `fileURL` | String | Relative path |
| `createdAt` | Date | Creation timestamp |

**Relationships:** `note`, `document` (optional)

### Link ✅
| Attribute | Type | Description |
|-----------|------|-------------|
| `id` | UUID | Primary identifier |
| `sourceID` | UUID | Source entity ID |
| `targetID` | UUID | Target entity ID |
| `kind` | String | note-note, note-annotation, note-document |
| `displayText` | String? | Link text |
| `createdAt` | Date | Creation timestamp |

### SmartRule ❌ REMOVED
~~Previously defined for smart collection rules. Removed to simplify the sidebar to Library/Collections/Tags. Entity still exists in the `.xcdatamodeld` but is unused.~~

| Attribute | Type | Description |
|-----------|------|-------------|
| `id` | UUID | Primary identifier |
| `name` | String | Rule name |
| `predicate` | Binary | NSPredicate archive |
| `scope` | String | documents, notes, annotations |
| `isEnabled` | Bool | Active state |

**Note:** This entity may be re-introduced if smart collections are implemented in a future phase.

## Derived Structures

### Backlinks Index 🚧
- Planned: adjacency list of note-to-note and note-to-annotation references
- Will be maintained by NoteService

### Vector Store 🚧
- Planned: 256-d embeddings per document/note for "See Also"
- Will use Accelerate/BNNS for computation

### Search Index 🚧
- Planned FTS5 tables:
  - `fts_documents(title, authors, text)`
  - `fts_notes(title, body)`
  - `fts_annotations(textSnippet)`

## File Layout ✅

```text
Library Root/
├── PDFs/
│   └── <doc-uuid>/document.pdf
├── Notes/
│   └── <note-uuid>.md
├── Attachments/
│   └── <attachment-uuid>/<original-filename>
├── Index/
│   ├── Wndr.sqlite (Core Data store)
│   ├── Wndr.sqlite-shm
│   ├── Wndr.sqlite-wal
│   └── Thumbnails/
│       └── <doc-uuid>.png (80x100px, generated on import)
└── Cache/
    ├── OCR/<doc-uuid>.json
    └── Previews/<doc-uuid>-<page>.jpg
```

## Data Integrity ✅

**Implemented:**
- SHA-256 checksum verification during import
- Core Data merge policies for conflict resolution
- Atomic saves with SQLite journaling

**Planned:**
- Periodic checksum audits
- Soft-delete with undo support
- Trash folder for deleted files
- Migration scripts for schema changes

## DTO Layer ✅

Data Transfer Objects decouple Core Data entities from views:

```swift
// DocumentDTO (WndrData)
struct DocumentDTO {
    let id: UUID
    var title: String
    var subtitle: String?
    var authors: [String]?
    var pageCount: Int
    var createdAt: Date?
    var updatedAt: Date?
    var fileURL: URL?
    var tags: [TagDTO]
    var collectionID: UUID?
}

// DocumentItem (WndrKit - UI model)
struct DocumentItem {
    let id: UUID
    var title: String
    var subtitle: String?
    var authors: [String]?
    var pageCount: Int
    var createdAt: Date?
    var updatedAt: Date?
    var fileURL: URL?
    var thumbnailURL: URL?  // Index/Thumbnails/<id>.png
    var tags: [DocumentTagItem]
    var collectionID: UUID?
}

// NoteDTO
struct NoteDTO {
    let id: UUID
    var title: String
    var body: String
    var preview: String
    var pinned: Bool
    var updatedAt: Date?
}

// AnnotationDTO
struct AnnotationDTO {
    let id: UUID
    var kind: AnnotationKind
    var pageIndex: Int
    var rects: [[String: Double]]
    var colorCategory: String
    var textSnippet: String?
}
```

## Privacy Considerations ✅

- All metadata stored locally in sandboxed container
- Security-scoped bookmarks for library access
- No network services or telemetry by default

**Planned:**
- Optional SQLCipher encryption for database files
- Sensitivity flags for document masking
