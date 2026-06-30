# Wndr Implementation Status

**Last Updated:** July 1, 2026 (macOS-only: iPadOS port removed)

## Overview

Wndr is a native macOS research workspace for managing PDFs, EPUBs, notes, and annotations with deep linking capabilities. This document tracks the implementation progress.

## Current Phase: MVP Development

**Target:** Shippable MVP with core research workflows on macOS

---

## Recent Updates (Session Log)

### EPUB Support (Feb 7, 2026)
- **EPUB Import & Storage:**
  - Added `documentType` attribute to Core Data `Document` entity (supports "pdf" and "epub")
  - `ImportService` now accepts both PDF and EPUB files with type-specific metadata extraction
  - `LibraryRootStore` added `EPUBs/` directory and `Cache/EPUB/` for extracted content
  - Import panel and drag-and-drop updated to accept `.epub` alongside `.pdf`
  - SHA-256 deduplication works for EPUBs just like PDFs
- **EPUB Parser (WndrData):**
  - Pure Swift ZIP reader using Apple's Compression framework (cross-platform, no third-party dependencies)
  - Parses EPUB structure: `container.xml` → OPF → manifest + spine
  - Extracts metadata (title, authors, language, publisher, description, cover image)
  - Reads NCX/XHTML Table of Contents for chapter titles
  - Cover image extraction for thumbnail generation
- **EPUB Reader UI (WndrKit):**
  - WKWebView-based reader with chapter-by-chapter navigation
  - **Customizable Reader Settings:**
    - Font size slider (12pt–32pt)
    - Font family picker (System, Serif, Sans Serif, Monospace)
    - Left/right margin slider (16px–100px)
  - CSS injection for reader settings; dark mode support via `prefers-color-scheme`
  - Chapter list popover (Table of Contents)
  - Previous/Next chapter navigation with chapter counter
  - WKWebView via NSViewRepresentable (macOS)
- **EPUB Highlighting:**
  - JavaScript bridge for text selection handling (mouseup/touchend events)
  - 6 highlight color presets (same as PDF: yellow, green, blue, pink, orange, purple)
  - Highlight toolbar appears on text selection with color chooser
  - Highlights persisted via existing `Annotation` entity (chapter index as pageIndex, text offsets in rects)
  - Highlights restored on chapter load via JavaScript DOM manipulation
- **Thumbnail Generation:**
  - EPUB cover images extracted and resized for library thumbnails
  - Fallback book icon for EPUBs without cover images
- **UI Updates:**
  - Document list shows book icon for EPUBs vs document icon for PDFs
  - Document info popover shows document type (PDF/EPUB)
  - Empty state text updated: "Drop PDF or EPUB files here"
  - Search result labels distinguish between PDF and EPUB documents

### iPadOS Port Removed (Jul 1, 2026)
- Removed the `WndrApp_iPad` Xcode target and all iPad-only sources.
- Stripped UIKit / `#if canImport(UIKit)` / `#if os(iOS)` branches from the shared frameworks; they are now AppKit/macOS-only.
- `PlatformCompat.swift` retains the `PlatformImage` / `PlatformColor` aliases (mapped to `NSImage` / `NSColor`) for source stability, but no longer carries UIKit code paths.
- The project is now macOS-only.

### Content Search (Feb 7, 2026)
- **Search Bar in Content Area:**
  - Two search modes: Filename and Content
  - Mode picker to switch between search types
  - Debounced search input with clear button
  - Progress indicator during search
  - Search results view with thumbnails, snippets, and page numbers
  - DocumentService.searchNoteContent() for content searching

### Markdown Formatting Toolbar (Feb 7, 2026)
- **Editor Toolbar:** Formatting buttons added to note editor
  - H1 heading, H2 heading
  - Bullet list, numbered list
  - Code block, blockquote
  - Buttons with hover effects (FormatIconButton)

### Wikilink Support (Feb 7, 2026)
- **Note Linking Syntax:** NoteEditorViewModel supports `[[noteTitle]]` wikilinks
  - `insertLink(to:)` method for inserting links to other notes

### Note Pinning (Feb 7, 2026)
- **Pin Notes:** Notes can be pinned to the top of the list
  - DocumentService.toggleNotePinned() for toggling pin status
  - Pinned indicator shown in note rows

### Drag-and-Drop to Collections (Feb 7, 2026)
- **Sidebar Drop Targets:** Collections in sidebar accept document drops
  - Visual drop feedback on hover
  - Documents assigned to collection on drop
  - Supports drag-and-drop reordering

### Status Bar (Feb 7, 2026)
- **Content List Status Bar:**
  - Shows item count for current view
  - Displays formatted library storage size
  - DocumentService.calculateTotalStorage() for size calculation

### Collection Badges (Feb 7, 2026)
- **Document Row Enhancement:** Collection name badge shown on document rows
  - Displays which collection a document belongs to
  - File size shown below filename

### Document Thumbnails (Feb 7, 2026)
- **Thumbnail Generation:** PDF thumbnails now appear in document list
  - ThumbnailService generates 80x100px PNG thumbnails from first page
  - Thumbnails cached in `Library/Index/Thumbnails/<documentID>.png`
  - Automatic generation on PDF import
  - Fallback blue icon shown if no thumbnail available
  - Uses PDFKit and AppKit for rendering

### Document Info Popover (Feb 7, 2026)
- **Info Button:** Added info circle icon in top-right toolbar
  - Shows popover with document metadata when clicked
  - Editable fields: Title, Subtitle, Authors (comma-separated)
  - Read-only fields: Pages, Filename, Added date, Modified date, Tags
  - "Done" button saves changes
  - Button disabled when no document selected

### Tags Feature (Feb 7, 2026)
- **Full Tags Implementation:**
  - Tags renamable via right-click context menu in sidebar
  - Documents taggable via right-click → "Tags" submenu
  - Multiple tags per document supported
  - Tag badges displayed on document rows (up to 3 shown, "+N" for more)
  - Tags shown with color coding

### Document Context Menu (Feb 7, 2026)
- **Right-Click Menu for Documents:**
  - Rename: Inline text field editing
  - Delete: Confirmation dialog before deletion
  - Tags: Submenu to toggle tags on/off
  - Add to Collection: Exclusive assignment (one collection per document)
    - Checkmark shows current collection
    - "None" option to remove from all collections

### Collection & Tag Rename (Feb 7, 2026)
- **Sidebar Rename:** Both Collections and Tags can be renamed via right-click
  - Inline TextField appears for editing
  - Press Enter to save changes

### Sidebar Counts Fix (Feb 7, 2026)
- **Fixed Total Counts:** "All Documents" and "Notes" counts now always show totals
  - Previously, counts changed when filtering by Collection or Tag
  - Now counts remain stable regardless of sidebar selection

### Smart Groups Removed (Feb 7, 2026)
- **Removed Feature:** Smart Groups section removed from sidebar
  - Removed SmartRule entity from Core Data
  - Simplified sidebar to: Library, Collections, Tags

### Document List Enhancements (Feb 7, 2026)
- **Improved Document Row Display:**
  - Shows relative date modified ("Today", "Yesterday", "2 days ago")
  - Displays file type (PDF) below filename
  - Tag badges aligned to the right

### PDF Highlighting Fix
- **Auto-Highlight on Selection:** Fixed PDF highlighting to work automatically
  - Added Coordinator to PDFViewRepresentable for handling selection changes
  - When Highlight tool is active, selecting text auto-creates highlight
  - 0.3 second debounce waits for selection to stabilize
  - Annotations save immediately to Core Data (no manual save needed)
  - Selection clears after highlight is applied

### Documentation Update
- Updated all docs to reflect current implementation status:
  - `docs/architecture.md` - Component status, view architecture, services
  - `docs/product-spec.md` - Feature implementation status tables
  - `docs/data-model.md` - Entity details, DTO layer, file layout
  - `docs/ui-ux-guidelines.md` - UI component reference, keyboard shortcuts
  - `docs/storage-and-security.md` - Security implementation status
  - `docs/testing-and-quality.md` - Test strategy, manual QA checklist
  - `implementation-plan.md` - Phase completion status, file reference

### PDF Viewer UI Improvements
- **Native macOS Toolbar:** Redesigned PDF viewer controls to follow macOS conventions
  - Removed in-view toolbars to eliminate whitespace
  - Page navigation moved to window toolbar
  - Annotation tools now use segmented picker (Select, Highlight, Underline, Note)
  - Color picker uses popover with grid layout
  - Zoom controls include menu with preset percentages
  - Display mode options in menu (Single, Continuous, Two-Up, Thumbnails)
- **Removed Duplicate Sidebar Toggles:**
  - Removed custom sidebar toggle (NavigationSplitView provides built-in toggle)
  - Inspector toggle uses `.primaryAction` placement
- **Cleaned Up Legacy Code:** Removed unused `ContentAreaView` struct

### UI/UX Fixes (Previous Session)
- **Three-Pane Layout Restructure:** Fixed PDF viewer appearing in wrong pane
  - Content pane (middle): Now shows only document/note lists
  - Detail pane (right): Now shows PDF viewer or note editor
  - Restructured `LookPrimaryView` with `ContentListView` and `DetailAreaView`
- **Selection Highlighting:** Document and note lists now properly highlight selected items
  - Added `selectedID` parameter to `DocumentListView` and `NoteListView`
  - Added `isSelected` parameter to `DocumentRow` and `NoteRow`
  - Lists use proper SwiftUI selection binding
- **Icon Fix:** Fixed pin icon to use SF Symbol (`systemName: "pin.fill"`)

### Build & Configuration Fixes
- **Core Data Model:** Renamed `Collection` entity to `DocumentCollection` to avoid Swift standard library conflict
- **Core Data Relationships:** Added missing inverse relationship for `Collection.notes` → `Note.collections`
- **Core Data Attributes:** Changed `Annotation.rects` from Transformable to Binary type for JSON serialization
- **Build Phases:** Moved `.xcdatamodeld` from Resources to Sources build phase
- **Type Fixes:** Updated JSON serialization to use `Double` instead of `CGFloat` for compatibility
- **Alert API:** Fixed `Alert.Button` initializer to use proper SwiftUI `.default()`, `.cancel()`, `.destructive()` methods
- **Property Access:** Changed `libraryRootCoordinator` and `importCoordinator` from `let` to `var` for SwiftUI bindings
- **State Propagation:** Added `@Published var libraryURL` to `AppEnvironment` with Combine subscription to fix UI reactivity after library selection

### New Features
- **Drag & Drop Import:** PDF files can now be dragged directly into the content area to import
- **Drop Visual Feedback:** Blue highlight overlay appears when files are dragged over the drop zone
- **Improved Empty State:** Shows "Drop PDF files here" message with Import and New Note buttons
- **Import Completion Refresh:** Document list automatically refreshes when import completes

---

## Completed Features

### Core Data & Persistence ✅
- Complete Core Data Model with 7 entities:
  - Document (metadata, OCR status, file management)
  - Note (Markdown, frontmatter, pinned status)
  - Annotation (highlights with coordinates, text snippets)
  - DocumentCollection (manual and bundle types; renamed from Collection)
  - Tag (hierarchical with colors)
  - Attachment (file management)
  - Link (bidirectional note-to-note/note-to-annotation)
- SmartRule entity removed (simplified sidebar)
- PersistenceController with proper merge policies
- Security-scoped bookmarks for sandboxed file access
- File storage layout (PDFs/, Notes/, Attachments/, Index/, Cache/)

### UI Architecture ✅
- Three-pane layout (sidebar, content area, inspector panel)
- Sidebar with sections for:
  - Library (All Documents with count, Notes with count)
  - Collections (with document counts, renamable via right-click, drag-and-drop targets)
  - Tags (with colors, counts, renamable via right-click)
- Content area with:
  - Search bar (filename and content modes) with debounced input
  - Search results view with thumbnails, snippets, page numbers
  - Document list view with thumbnails, collection badges, file size, tag badges
  - Note list view with pin indicators
  - Empty states with import prompts
  - Compact date formatting ("Today", "2d", "3mo", "1y")
  - Status bar (item count + library storage size)
- Detail area with:
  - PDF viewer with native macOS toolbar
  - Markdown editor with formatting toolbar and live preview
  - Info popover for editable document metadata
- Keyboard shortcuts (⌘I for import, ⌘N for new note, ⌘S for save, ⌥⌘I for inspector toggle)

### Document Import ✅
- ImportService with:
  - PDF validation
  - SHA-256 checksum deduplication
  - Metadata extraction (title, authors, page count)
  - OCR detection (checks if text layer exists)
  - File copying to library structure
- ImportCoordinator with:
  - NSOpenPanel integration
  - Multi-file batch import
  - Progress tracking UI
  - Success/failure reporting
- Import UI with progress overlay
- **Drag & Drop import** - Drop PDFs directly into content area
- Auto-refresh document list after import

### PDF Viewing ✅
- PDFViewerView with:
  - Thumbnail sidebar (collapsible)
  - Page navigation (prev/next, goto)
  - Zoom controls (in/out, actual size)
  - Display modes (single page, continuous, two-up)
  - Current page indicator
- PDFViewerViewModel with:
  - Document loading
  - Thumbnail caching
  - Page navigation logic
  - Zoom management

### Content Search ✅
- Content search bar with two modes (filename, content)
- Debounced input with progress indicator
- Search results view with thumbnails, snippets, page numbers
- DocumentService.searchNoteContent() for note content search

### Services Layer ✅
- DocumentService for fetching/managing documents and notes
  - Rename, delete, update metadata operations
  - Storage calculation (recursive directory enumeration)
  - Content search (case-insensitive CONTAINS predicate)
- CollectionService for managing collections and tags
  - Exclusive collection assignment (one collection per document)
  - Tag add/remove operations (documents and notes)
- AnnotationService for PDF annotation persistence
  - Highlight/note creation with color presets
  - Normalized coordinate storage (JSON)
  - Bulk delete operations
- ThumbnailService for PDF thumbnail generation and caching
  - 80×100px PNG thumbnails from first page
  - Validation, regeneration, bulk operations
- LibraryRootStore with directory management helpers
- WndrLogger for structured OSLog-based logging

### Application Wiring ✅
- AppEnvironment orchestrating all services
- Bootstrap flow with library restoration
- View models connected to Core Data
- Import workflow fully integrated
- PDF viewing integrated with document selection

---

## In Progress / MVP Critical

### Markdown Editor ✅
- [x] TextEditor-based component with monospace font (SF Mono)
- [x] Live preview pane with toggle (AttributedString rendering)
- [x] Formatting toolbar (H1, H2, bullet list, numbered list, code block, blockquote)
- [x] Auto-save functionality (2 second delay with debounce)
- [x] Note CRUD from UI (create, edit, delete)
- [x] Template insertion (Literature Review, Meeting Notes)
- [x] Word/character count in status bar
- [x] Save indicator and keyboard shortcut (⌘S)
- [x] Wikilink syntax support (`[[noteTitle]]`)
- [x] Note pinning (toggle to top of list)

### PDF Annotations ✅
- [x] Annotation toolbar (highlight, underline, note tools)
- [x] Color presets (yellow, green, blue, pink, orange, purple)
- [x] Annotation persistence to Core Data via AnnotationService
- [x] Annotation display on PDF pages
- [x] Clear all annotations button

### Note-PDF Linking 🚧
- [ ] Create note from PDF selection
- [ ] Link storage in Core Data
- [ ] Backlinks panel in inspector
- [ ] Split view (PDF + Note side by side)

---

## Planned Features (Post-MVP)

### Search
- [x] Basic content search (filename and content modes)
- [x] Search results with thumbnails and snippets
- [ ] SQLite FTS5 integration (full-text indexing)
- [ ] Full-text search across PDFs
- [ ] Search filters (tags, dates, metadata)
- [ ] Saved searches

### OCR Service
- [ ] VisionKit integration
- [ ] Background OCR queue
- [ ] Progress UI
- [ ] OCR results caching

### Smart Collections
- [ ] Rule builder UI
- [ ] NSPredicate-based queries
- [ ] Dynamic collection updates

### Drag & Drop
- [x] Drag files onto window to import
- [ ] Drag documents to collections
- [ ] Drag to apply tags

### Automation
- [ ] Shortcuts integration
- [ ] AppleScript dictionary
- [ ] Quick Capture (⌃⌥Space)

### Testing
- [ ] Unit tests for services
- [ ] Integration tests for import/search
- [ ] UI tests for critical flows

---

## Architecture Summary

### Module Structure
```
WndrApp/          - Main app, coordinators, wiring
WndrKit/          - Reusable UI components, view models
WndrData/         - Core Data, services, persistence
WndrPDF/          - PDF viewing, annotations
WndrNotes/        - Markdown editing, backlinks
WndrAutomation/   - Shortcuts, AppleScript
```

### Key Files

| File | Purpose |
|------|---------|
| `WndrApp.swift` | App entry point, window management |
| `AppEnvironment.swift` | Service container, dependency injection |
| `PersistenceController.swift` | Core Data stack management |
| `ImportService.swift` | PDF import pipeline |
| `ImportCoordinator.swift` | Import UI coordination, thumbnail generation |
| `DocumentService.swift` | Document/Note CRUD operations |
| `CollectionService.swift` | Collection/Tag management |
| `AnnotationService.swift` | PDF annotation persistence |
| `ThumbnailService.swift` | PDF thumbnail generation and caching |
| `LibraryRootStore.swift` | File system, security bookmarks |
| `PDFViewerView.swift` | PDF rendering UI |
| `PDFViewerViewModel.swift` | PDF viewer state management |
| `AnnotationToolbarView.swift` | Annotation tools and colors |
| `MarkdownEditorView.swift` | Note editing UI |
| `NoteEditorViewModel.swift` | Note editor state management |
| `ContentAreaView.swift` | Document/Note lists, context menus, info popover |
| `LibrarySidebarView.swift` | Navigation sidebar with rename support |
| `WndrKit.swift` | Main three-pane layout, toolbar |

### Data Flow
```
UI (SwiftUI Views)
  ↓
View Models (Observable)
  ↓
Services (Document, Collection, Import)
  ↓
Core Data / File System
```

---

## File Statistics

- **Swift files:** 35
- **Core Data entities:** 7 (Document, Note, Annotation, DocumentCollection, Tag, Attachment, Link)
- **Services:** 6 implemented (Import, Document, Collection, Annotation, Thumbnail, LibraryRoot)
- **View Models:** 6 (Sidebar, Content, Inspector, PDFViewer, ContentArea, NoteEditor)
- **UI Views:** 20+ (includes search bar, search results, formatting toolbar, status bar, info popover)

---

## MVP Success Criteria

- [x] Import PDFs via file picker
- [x] Import PDFs via drag & drop
- [x] Browse and open PDFs
- [x] Navigate PDF pages with zoom
- [x] Create new Markdown notes
- [x] Edit and save notes
- [x] Highlight text in PDFs
- [ ] Create note from PDF selection (pending)
- [x] Organize with collections and tags
- [ ] Handle 100+ documents performantly (needs testing)
- [ ] No crashes in normal workflows (needs testing)
- [x] Light/dark mode support (SwiftUI native)

---

## Implementation Priority

See `implementation-plan.md` for detailed phase breakdown:

1. **Phase A:** Note Editor (critical for core workflow)
2. **Phase B:** PDF Annotations (enables research workflow)
3. **Phase C:** Note-PDF Linking (connects the pieces)
4. **Phase E:** Polish & Ship (production quality)
5. **Phase D:** Search (can defer post-MVP)

---

## Notes

- All user data stored locally with security-scoped bookmarks
- Privacy-first design (no cloud dependencies)
- Designed for 10k+ document libraries
- SwiftUI-first with AppKit where necessary
- macOS-only
