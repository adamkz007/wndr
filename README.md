# Wndr

> **Last Updated:** February 7, 2026

Wndr is a native macOS research workspace that combines a high-performance PDF reader with Markdown note-taking and deep linking between the two. All user data is stored locally, giving researchers full control over their library while still offering advanced organization tools inspired by professional research apps such as DEVONthink and Keep It.

## Vision

- Deliver a fast, focused macOS app tailored to researchers who work primarily with academic papers, reports, and technical documentation.
- Blend PDF annotation and Markdown note-taking into a cohesive workflow where highlights, notes, and tags stay in sync.
- Keep the entire library stored locally with optional encryption, no cloud dependencies, and privacy-first defaults.

## Current Status

**MVP development is well underway.** The core research workflow — import, read, annotate, take notes, and organize — is functional. See `STATUS.md` for full details.

### Working Features

| Area | Features |
|------|----------|
| **PDF Import** | File picker (⌘I), drag-and-drop, SHA-256 deduplication, metadata extraction |
| **PDF Viewing** | Thumbnails sidebar, page navigation, zoom with presets, display modes (single/continuous/two-up) |
| **PDF Annotations** | Highlight and underline tools, 6 color presets, auto-highlight on selection, persistence to Core Data |
| **Markdown Notes** | Editor with monospace font, live preview, formatting toolbar (H1/H2/lists/code/quote), auto-save, word count, templates |
| **Organization** | Collections (exclusive assignment), tags with colors, rename/delete via context menus, document context menus |
| **Search** | Filename and content search modes with results view |
| **UI** | Three-pane layout, native macOS toolbar, document thumbnails, info popover, inspector panel, light/dark mode |

### In Progress

- **Note-PDF Linking** — Create notes from PDF selection, backlinks panel, split view
- **Inspector Panel** — Enhanced metadata display, live annotation/backlink lists

### Planned (Post-MVP)

- Full-text search (FTS5), OCR (VisionKit), smart collections, automation (Shortcuts/AppleScript)

## Architecture

The codebase uses a modular architecture with 6 frameworks:

| Module | Purpose | Files |
|--------|---------|-------|
| **WndrApp** | App entry point, window management, coordinators | 5 |
| **WndrKit** | Three-pane UI, sidebar, content area, view models | 9 |
| **WndrData** | Core Data persistence, services, file storage | 9 |
| **WndrPDF** | PDF viewer, annotations, annotation bridge | 5 |
| **WndrNotes** | Markdown editor, templates, note view model | 4 |
| **WndrAutomation** | Shortcuts, AppleScript (scaffolding) | 2 |

**35 Swift source files** across all modules.

### Services Layer

| Service | Capability |
|---------|-----------|
| **ImportService** | PDF validation, SHA-256 deduplication, metadata extraction, OCR detection |
| **DocumentService** | Document/note CRUD, metadata editing, storage calculation, content search |
| **CollectionService** | Collection/tag management, exclusive assignment, document-tag associations |
| **AnnotationService** | Highlight/note creation, coordinate storage, color presets, bulk operations |
| **ThumbnailService** | PDF thumbnail generation (80×100px PNG), validation, caching, bulk regeneration |
| **LibraryRootStore** | Security-scoped bookmarks, directory management |

### Data Model

7 Core Data entities: `Document`, `Note`, `Annotation`, `DocumentCollection`, `Tag`, `Attachment`, `Link`

## Project Structure

```
Sources/
├── WndrApp/       App entry point, coordinators, wiring
├── WndrKit/       Reusable UI components, view models
├── WndrData/      Core Data, services, persistence
├── WndrPDF/       PDF viewing, annotations
├── WndrNotes/     Markdown editing, templates
└── WndrAutomation/ Shortcuts, AppleScript (scaffolding)

docs/              Design specifications
├── product-spec.md
├── architecture.md
├── data-model.md
├── storage-and-security.md
├── testing-and-quality.md
├── ui-ux-guidelines.md
└── implementation-roadmap.md
```

## Getting Started

1. Open `Wndr.xcodeproj` or `Wndr.xcworkspace` in Xcode
2. Build with ⌘B and run with ⌘R
3. On first launch, choose a library location — the directory structure is created automatically
4. Import PDFs via ⌘I or drag-and-drop

**Requires:** Xcode (not just Command Line Tools) on macOS

## Documentation

| Document | Contents |
|----------|----------|
| `STATUS.md` | Detailed implementation progress and session log |
| `CLAUDE.md` | AI assistant guidance for working with the codebase |
| `implementation-plan.md` | Phase breakdown with success criteria |
| `docs/product-spec.md` | Functional requirements, personas, workflows |
| `docs/architecture.md` | System components, services, data flow |
| `docs/data-model.md` | Entity definitions, DTO layer, file layout |
| `docs/storage-and-security.md` | Sandboxing, bookmarks, encryption, privacy |
| `docs/testing-and-quality.md` | Test strategy, QA checklist, known issues |
| `docs/ui-ux-guidelines.md` | Design patterns, component reference, keyboard shortcuts |

## Website

The marketing site is a single static page at `index.html` (with `icon.png` in repo root).

- Deployment: GitHub Pages via GitHub Actions (`.github/workflows/deploy-pages.yml`)
- One-time setup in GitHub: **Settings → Pages → Build and deployment → Source: GitHub Actions**
- Updates: edit `index.html` and push to `main`/`master` to redeploy

## Privacy

- All data stored locally — no cloud dependencies
- No analytics or telemetry without explicit opt-in
- macOS sandbox compliant with security-scoped bookmarks
- No network requests during normal operation
