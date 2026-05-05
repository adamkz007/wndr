# Wndr Product Specification

> **Last Updated:** February 7, 2026
> **Implementation Status:** MVP feature set complete

## Target Audience

- **Academic researchers:** Manage large libraries of scholarly articles, annotate PDF papers, and consolidate literature notes.
- **Knowledge workers:** Capture insights from reports, whitepapers, and manuals while keeping Markdown notes linked to sources.
- **Legal and compliance teams:** Review case files, attach structured notes, and maintain an auditable local archive.

## Personas & Goals

| Persona | Primary Goals | Pain Points Today |
| --- | --- | --- |
| Graduate Researcher | Collect papers, annotate, write literature reviews | Context switches between PDF apps and note tools, fragile links |
| Knowledge Lead | Maintain research repository, share briefs | Cloud privacy concerns, inconsistent organization |
| Analyst | Extract key points, produce memos | Manual cross-referencing, duplicated highlights |

## User Workflows

### 1. Import & Organize ✅
- ✅ Drag-and-drop PDFs into Wndr
- ✅ Import via file picker (⌘I)
- ✅ Assign tags and collections during import
- ✅ Automatic SHA-256 deduplication
- 🚧 Automatically run OCR if text layer is missing (detection implemented, OCR pending)

### 2. Read & Annotate ✅
- ✅ Open PDFs in viewer with thumbnails
- ✅ Navigate pages with zoom controls
- ✅ Highlight text with color selection (6 colors)
- ✅ Display modes: single page, continuous, two-up
- 🚧 Draw shapes, add sticky notes
- 🚧 Capture citations and metadata automatically

### 3. Capture Notes ✅
- ✅ Create Markdown notes with live preview
- ✅ Use templates (Literature Review, Meeting Notes, Blank)
- ✅ Formatting toolbar (headings, lists, code, blockquote)
- ✅ Auto-save with word/character count
- ✅ Pin important notes to top of list
- ✅ Wikilink syntax (`[[noteTitle]]`) for cross-referencing
- 🚧 Link notes to active PDF selection
- 🚧 Reference other notes using backlinks (engine pending)

### 4. Link Insights 🚧
- 🚧 Generate bidirectional anchors between notes and PDF highlights
- 🚧 Preview linked highlights while editing notes
- 🚧 Surface backlinks and "See Also" suggestions

### 5. Organize & Retrieve ✅
- ✅ Build collections/folders manually
- ✅ Apply tags with colors
- ✅ Drag documents to collections in sidebar
- ✅ Search by filename or content
- 🚧 Smart groups with rules (author, tag, recency)
- 🚧 Full-text search across PDFs (FTS5)
- 🚧 Save searches as smart groups

### 6. Share & Export 🚧
- 🚧 Export notes with inline highlight references
- 🚧 Generate summary packets (PDF + notes)
- 🚧 QuickLook and share extensions

## Feature Requirements - Implementation Status

### PDF Management
| Feature | Status |
|---------|--------|
| PDF metadata display (title, authors, page count) | ✅ Implemented |
| Automatic de-duplication using SHA-256 checksums | ✅ Implemented |
| PDF metadata editing (title, subtitle, authors via info popover) | ✅ Implemented |
| Document thumbnails in list view | ✅ Implemented |
| Background OCR queue | 🚧 Planned |

### Annotations
| Feature | Status |
|---------|--------|
| Highlight colors (yellow, green, blue, pink, orange, purple) | ✅ Implemented |
| Annotation persistence to Core Data | ✅ Implemented |
| Clear all annotations | ✅ Implemented |
| Filterable annotation list | 🚧 Planned |
| Export annotations to Markdown/CSV/JSON | 🚧 Planned |
| Semantic color meanings | 🚧 Planned |

### Markdown Notes
| Feature | Status |
|---------|--------|
| TextEditor with monospace font (SF Mono) | ✅ Implemented |
| Live preview pane with toggle | ✅ Implemented |
| Formatting toolbar (H1, H2, bullets, numbered list, code, quote) | ✅ Implemented |
| Auto-save (2 second debounce) | ✅ Implemented |
| Word/character count | ✅ Implemented |
| Templates (Blank, Literature Review, Meeting Notes) | ✅ Implemented |
| Note pinning (toggle to top of list) | ✅ Implemented |
| Wikilink syntax (`[[noteTitle]]`) | ✅ Implemented |
| Callouts, tables, math (LaTeX) | 🚧 Planned |
| Attachment embedding | 🚧 Planned |

### Linking
| Feature | Status |
|---------|--------|
| Link data model (Core Data entity) | ✅ Implemented |
| Create note from PDF selection | 🚧 Planned |
| Stable anchors with coordinate rebasing | 🚧 Planned |
| Note-to-note and note-to-collection links | 🚧 Planned |

### Organization
| Feature | Status |
|---------|--------|
| Collections/folders | ✅ Implemented |
| Tags with colors | ✅ Implemented |
| Tag badges on document rows (up to 3 shown, "+N" for more) | ✅ Implemented |
| Collection badges on document rows | ✅ Implemented |
| Rename collections/tags via context menu | ✅ Implemented |
| Document context menu (rename, delete, tags, collection) | ✅ Implemented |
| Exclusive collection assignment (one per document) | ✅ Implemented |
| Drag-and-drop documents to collections in sidebar | ✅ Implemented |
| Status bar with item count and storage size | ✅ Implemented |
| Nested collections | 🚧 Planned |
| Smart rules with conditions | 🚧 Planned |
| Quick capture inbox | 🚧 Planned |

### Search & Discovery
| Feature | Status |
|---------|--------|
| Browse documents by collection/tag | ✅ Implemented |
| Content search bar (filename and content modes) | ✅ Implemented |
| Search results with thumbnails, snippets, page numbers | ✅ Implemented |
| Full-text search indexing (FTS5) | 🚧 Planned |
| "See Also" suggestions (TF-IDF) | 🚧 Planned |
| Saved searches | 🚧 Planned |

### Automation
| Feature | Status |
|---------|--------|
| Keyboard shortcuts (⌘I, ⌘N, ⌘S, ⌥⌘I) | ✅ Implemented |
| Quick Note mini window | 🚧 Planned |
| macOS Shortcuts actions | 🚧 Planned |
| AppleScript dictionary | 🚧 Planned |

### Localization & Accessibility
| Feature | Status |
|---------|--------|
| Light/dark mode support | ✅ Implemented |
| VoiceOver compatibility | ✅ Implemented (SwiftUI default) |
| Dynamic Type scaling | 🚧 Needs verification |
| High-contrast themes | 🚧 Planned |

## Non-Goals (Initial Release)

- No collaborative editing or cloud sync between machines
- No web or iOS companion app
- No AI-generated summaries that rely on cloud services
- No non-PDF document formats (e.g., EPUB, Word) beyond QuickLook previews

## Success Metrics

| Metric | Target | Status |
|--------|--------|--------|
| Library import speed | <5 seconds per 50MB PDF | ✅ Met |
| Search latency | <250ms for typical queries | 🚧 Pending (no search yet) |
| Linking reliability | <1% broken anchors | 🚧 Pending (no linking yet) |
| Crash-free sessions | >99% over 30 days | 🚧 Needs testing |

## MVP Completion Checklist

- [x] Import PDFs via file picker
- [x] Import PDFs via drag & drop
- [x] Browse and open PDFs
- [x] Navigate PDF pages with zoom
- [x] Create new Markdown notes
- [x] Edit and save notes
- [x] Highlight text in PDFs
- [ ] Create note from PDF selection
- [x] Organize with collections and tags
- [ ] Handle 100+ documents performantly (needs testing)
- [ ] No crashes in normal workflows (needs testing)
- [x] Light/dark mode support

## Open Questions

- Should Wndr expose a plug-in architecture for custom import pipelines?
- Do enterprise customers require integration with on-prem document management systems?
- Which file metadata fields should be surfaced to users vs. kept internal?
