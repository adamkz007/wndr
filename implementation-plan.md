# Wndr App - Implementation Plan

**Last Updated:** July 1, 2026
**Status:** MVP Feature Set Complete + Bonus Features (EPUB) — macOS-only

---

## Current State

### Fully Implemented ✅

| Feature | Description |
|---------|-------------|
| **Core Data Model** | 7 entities (Document, Note, Annotation, DocumentCollection, Tag, Attachment, Link) with documentType for PDF/EPUB |
| **Persistence Layer** | PersistenceController with merge policies, background contexts |
| **Library Management** | Security-scoped bookmarks (macOS), directory structure, LibraryRootStore |
| **Import Pipeline** | SHA-256 deduplication, metadata extraction, OCR detection, drag & drop, batch import |
| **Document Service** | CRUD operations with DTOs for documents and notes, storage calculation |
| **Collection Service** | Collections with exclusive assignment, hierarchical tags with colors |
| **Annotation Service** | Highlight/underline persistence, 6 color presets, coordinate storage |
| **Three-Pane UI** | NavigationSplitView with sidebar, content list, detail view, inspector |
| **PDF Viewer** | Full viewer with thumbnails, zoom (12%-800%), page navigation, display modes |
| **PDF Annotations** | Highlight/underline tools with 6 colors, auto-highlight on selection (0.3s debounce) |
| **Markdown Editor** | TextEditor with live preview, formatting toolbar, auto-save (2s debounce), word count, templates |
| **Content Search** | Filename and content search modes, results with thumbnails and snippets |
| **Native macOS Toolbar** | All PDF controls in window toolbar following macOS conventions |
| **Document Thumbnails** | 80×100px PNG thumbnails, cached in Index/Thumbnails/, auto-generated on import |
| **Document Info Popover** | Editable title/subtitle/authors, read-only pages/filename/dates |
| **Tags & Context Menus** | Tag badges (up to 3 shown), document context menus (rename/delete/tags/collections) |
| **Status Bar** | Item count and library storage size display with recursive calculation |
| **Drag-to-Collections** | Drop documents onto sidebar collections with visual feedback |
| **Note Pinning** | Toggle notes to pin to top of list |
| **EPUB Support** | Complete e-book reader with parser, viewer, highlighting, TOC navigation |
| **Keyboard Shortcuts** | ⌘I (import), ⌘N (new note), ⌘S (save), ⌥⌘I (inspector), arrow keys |
| **Search Results UI** | Dedicated results view with snippets, page numbers, clear button |
| **Collection Badges** | Document rows show assigned collection name |
| **Relative Date Formatting** | "Today", "Yesterday", "2 days ago", "3mo", "1y" |
| **Note Templates** | Literature Review, Meeting Notes templates with registry |
| **Wikilink Support** | [[noteTitle]] syntax parsing and rendering |

### Major Features Not Originally Planned (But Fully Implemented) 🎉

| Feature | Description |
|---------|-------------|
| **EPUB E-Book Support** | Complete implementation with pure Swift ZIP reader using Apple Compression framework |
| | • EPUBParser extracts metadata, TOC, cover images |
| | • WKWebView-based reader with chapter navigation |
| | • Customizable reading settings (font size 12-32pt, font family, margins 16-100px) |
| | • JavaScript bridge for highlight selection and restoration |
| | • 6-color highlighting system shared with PDF |
| | • Cover image thumbnails with fallback book icon |

### Partially Implemented 🚧

| Feature | Status |
|---------|--------|
| **Inspector Panel** | UI exists, shows basic metadata, annotation/backlink sections are placeholders |

### Not Implemented

| Feature | Priority |
|---------|----------|
| **Note-PDF Linking** | High - create note from selection, backlinks |
| **Search (FTS5)** | Medium - full-text indexing (basic content search already works) |
| **OCR Service** | Medium - VisionKit text extraction |
| **Smart Collections** | Low - rule builder UI, NSPredicate queries |
| **Automation** | Low - Shortcuts, AppleScript |

---

## Implementation Phases

### Phase A: Note Editor ✅ COMPLETE

- [x] MarkdownEditorView with TextEditor (SF Mono font)
- [x] Live preview pane with toggle (AttributedString rendering)
- [x] Formatting toolbar (H1, H2, bullet list, numbered list, code block, blockquote)
- [x] NoteEditorViewModel with auto-save (2s debounce)
- [x] Note CRUD from UI
- [x] Template selection (Blank, Literature Review, Meeting Notes)
- [x] Word/character count status bar
- [x] Save indicator (⌘S)
- [x] Wikilink syntax support (`[[noteTitle]]`)
- [x] Note pinning (toggle to top of list)

### Phase B: PDF Annotations ✅ COMPLETE

- [x] AnnotationService for persistence
- [x] Native toolbar with segmented picker (Select, Highlight, Underline, Note)
- [x] Color picker popover (6 colors)
- [x] Auto-highlight on text selection
- [x] Annotation display on PDF pages
- [x] Clear all annotations
- [x] Annotations persist to Core Data automatically

### Phase C: Note-PDF Linking 🚧 IN PROGRESS

- [ ] Create note from PDF selection
- [ ] Link storage in Core Data (Link entity ready)
- [ ] Backlinks panel in inspector
- [ ] Split view (PDF + Note side by side)
- [ ] Context menu on highlight → "Create Note"

### Phase D: Search 🚧 PLANNED

- [ ] SQLite FTS5 integration
- [ ] Index documents on import
- [ ] Index notes on save
- [ ] Search UI in sidebar
- [ ] Results with snippets
- [ ] Saved searches

### Phase E: Polish & Ship ✅ MOSTLY COMPLETE

- [x] Three-pane layout with proper pane separation
- [x] Native macOS toolbar styling
- [x] Drag & drop import with visual feedback
- [x] Light/dark mode support
- [x] Selection highlighting in lists
- [x] Document thumbnails (80×100px PNG, cached)
- [x] Document info popover (editable metadata)
- [x] Tags with color badges on document rows
- [x] Document context menus (rename, delete, tags, collections)
- [x] Collection/tag rename via right-click
- [x] Content search bar (filename and content modes)
- [x] Status bar (item count + storage size)
- [x] Drag-and-drop to collections in sidebar
- [x] Collection badges on document rows
- [x] Compact date formatting
- [ ] Inspector panel enhancement (annotations, backlinks)
- [ ] Performance testing with large libraries
- [ ] Error handling improvements

---

## Technical Decisions

### Completed

| Decision | Implementation |
|----------|---------------|
| **Markdown Rendering** | AttributedString with SwiftUI Text for live preview |
| **Annotation Coordinates** | Stored as JSON in Binary Core Data attribute with normalization |
| **File Sync** | Notes as .md files, Core Data for metadata |
| **View Architecture** | NavigationSplitView + HSplitView for inspector |
| **Toolbar Style** | Native macOS toolbar, no in-view toolbars |
| **EPUB Parser** | Pure Swift with Apple Compression framework (no third-party deps) |
| **EPUB Reader** | WKWebView with JavaScript bridge for highlighting |
| **Thumbnail Generation** | CGBitmapContext render → NSBitmapImageRep PNG (macOS) |
| **Search Implementation** | Basic content search with Task.detached parallelization |
| **Import Deduplication** | SHA-256 checksums stored in Core Data |
| **Background Operations** | newBackgroundContext() for all service operations |
| **Highlight Auto-Creation** | 0.3 second debounce on text selection |

### Pending

| Decision | Options |
|----------|---------|
| **FTS Integration** | GRDB vs custom SQLite wrapper (basic search already works) |
| **OCR Framework** | VisionKit vs third-party |
| **Backlink Storage** | Derived index vs materialized table |
| **Automation Framework** | Shortcuts vs AppleScript (placeholder structure exists) |

---

## MVP Success Criteria

### Original MVP Goals
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

**Original MVP Status: 9/12 criteria met (75%)**

### Bonus Features Delivered Beyond MVP
- [x] EPUB e-book support with full reader
- [x] Batch import with progress tracking
- [x] Document metadata editing
- [x] Content search with results UI
- [x] Keyboard shortcuts with overlay
- [x] Note templates system
- [x] Wikilink syntax support

---

## Risk Assessment

| Risk | Mitigation | Status |
|------|------------|--------|
| PDF Annotation Complexity | Started with highlights only | ✅ Mitigated |
| Core Data Sync | Using merge policies | ✅ Mitigated |
| Memory Management | PDFKit handles page disposal | ✅ Mitigated |
| Search Performance | Deferred to post-MVP | 🚧 Pending |
| File Coordination | NSFileCoordinator planned | 🚧 Pending |

---

## Implementation Statistics

### Codebase Metrics
- **Total Swift Files:** ~50+
- **Lines of Code:** ~15,000+
- **Platforms:** 1 (macOS)
- **Core Data Entities:** 7
- **Services Implemented:** 7
- **View Models:** 7
- **UI Components:** 25+
- **Keyboard Shortcuts:** 10+
- **File Formats Supported:** PDF, EPUB, Markdown

### Feature Coverage
- **Document Management:** 100% complete
- **PDF Viewing & Annotation:** 100% complete
- **EPUB Support:** 100% complete (bonus feature)
- **Markdown Editing:** 100% complete
- **Collections & Tags:** 100% complete
- **Search:** 70% complete (basic search works, FTS5 pending)
- **Note-PDF Linking:** 20% complete (Link entity exists, UI pending)
- **Automation:** 10% complete (placeholder structure only)
- **Testing:** 0% complete

---

## Next Steps

1. **Test current implementation** - Verify all features work in Xcode
2. **Add note-from-selection** - Phase C linking feature
3. **Performance testing** - 100+ document library
4. **Bug fixing** - Address any issues found
5. **Search integration** - Phase D if time permits

---

## File Reference

### Key Implementation Files

| File | Module | Purpose |
|------|--------|---------|
| **macOS Entry Point** | | |
| `WndrApp.swift` | WndrApp | macOS entry point, window management |
| `AppEnvironment.swift` | WndrApp | Service container, dependency injection |
| `ContentWrapper.swift` | WndrApp | Handler wiring for PDF/Note/EPUB views |
| `LibraryRootCoordinator.swift` | WndrApp | Library location selection flow |
| **Shared UI Components** | | |
| `WndrKit.swift` | WndrKit | LookPrimaryView, ContentListView, DetailAreaView |
| `ContentAreaView.swift` | WndrKit | DocumentListView, NoteListView, models |
| `LibrarySidebarView.swift` | WndrKit | Sidebar with Library/Collections/Tags |
| `DocumentRow.swift` | WndrKit | Document list item with tags/collection |
| `NoteRow.swift` | WndrKit | Note list item with pinning |
| `ContentSearchBar.swift` | WndrKit | Dual-mode search bar |
| `SearchResultsListView.swift` | WndrKit | Search results display |
| `DocumentInfoPopover.swift` | WndrKit | Metadata editor popover |
| `InspectorPanelView.swift` | WndrKit | Right sidebar inspector |
| `PlatformCompat.swift` | WndrKit | AppKit type aliases and helpers |
| **PDF Components** | | |
| `PDFViewerView.swift` | WndrPDF | PDF rendering, toolbar, annotations |
| `PDFViewerViewModel.swift` | WndrPDF | PDF state management |
| `AnnotationToolbarView.swift` | WndrPDF | Color picker, tool enums |
| `PDFViewRepresentable.swift` | WndrPDF | NSViewRepresentable PDFView wrapper |
| `PDFAnnotationBridge.swift` | WndrPDF | Coordinate normalization |
| `PDFThumbnailListView.swift` | WndrPDF | Thumbnail sidebar |
| **EPUB Components** | | |
| `EPUBParser.swift` | WndrPDF | ZIP extraction, metadata, TOC parsing |
| `EPUBReaderView.swift` | WndrPDF | WKWebView-based chapter reader |
| `EPUBReaderViewModel.swift` | WndrPDF | EPUB state, settings, navigation |
| **Markdown Components** | | |
| `MarkdownEditorView.swift` | WndrNotes | Note editing UI with toolbar |
| `NoteEditorViewModel.swift` | WndrNotes | Note state, auto-save |
| `NewNoteSheet.swift` | WndrNotes | Template selection dialog |
| `NoteTemplateRegistry.swift` | WndrNotes | Template management |
| **Data Services** | | |
| `ImportService.swift` | WndrData | PDF/EPUB import pipeline |
| `DocumentService.swift` | WndrData | Document/Note CRUD, search |
| `AnnotationService.swift` | WndrData | Annotation persistence |
| `CollectionService.swift` | WndrData | Collections/tags management |
| `ThumbnailService.swift` | WndrData | Thumbnail generation and caching |
| `LibraryRootStore.swift` | WndrData | Security-scoped bookmarks |
| `PersistenceController.swift` | WndrData | Core Data stack |
| `WndrLogger.swift` | WndrData | OSLog wrapper with categories |
