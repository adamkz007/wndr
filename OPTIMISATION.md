# Wndr Optimisation Plan

## Purpose

This document turns the current performance analysis into a concrete implementation sequence for the next ship.

The primary goals are:

- Improve launch speed, list responsiveness, search latency, and PDF detail performance
- Preserve compatibility with existing libraries
- Keep all migration work additive, resumable, and safe
- Ensure the next shipped version can open current libraries even if migration has not finished

## Guiding Rules

For the next ship:

1. Keep the current library layout as the canonical source of truth:
   - `PDFs/`
   - `Notes/`
   - `Attachments/`
   - `Index/`
   - `Cache/`
2. Treat any new indexing or lookup structure as a rebuildable sidecar under `Index/`, not as a replacement for the current storage model.
3. Do not rename or remove existing Core Data attributes or relationships in this release.
4. Only add optional fields or additive entities if needed so Core Data migration remains lightweight.
5. The app must always be able to open an old library before migration completes.
6. Migration should improve performance progressively, not gate access to documents or notes.

## Current High-Impact Problems

The highest-priority performance problems are:

- Full-store refetches after many single-item mutations
- Rebuilding large document and note arrays repeatedly in the UI layer
- Synchronous filesystem and image work happening during SwiftUI row rendering
- Recreating PDF viewer state and reloading PDFs during parent view redraws
- Brute-force content search that reopens and scans PDFs per query
- Heavy startup work running too early for larger libraries

## Delivery Strategy

The implementation should ship in phases, with the safest and highest-ROI changes first.

### Milestone 0: Instrumentation And Baselines

Add measurement before making behavior changes.

Track:

- App launch time
- Library bootstrap time
- List refresh time
- Document open latency
- PDF annotation update time
- Content search latency
- Import time
- Thumbnail generation time

Create repeatable benchmark libraries:

- Small library
- Medium library
- Large library

This milestone should also define pass/fail performance budgets for the next ship.

### Milestone 1: Remove Full Refresh Churn

This is the first implementation milestone and the highest-ROI code change.

Goals:

- Stop using global refreshes after single-item mutations
- Stop refetching all documents, notes, tags, and collections after small edits
- Update local state incrementally where possible

Implementation direction:

- Refactor service mutation APIs to return changed DTOs or identifiers
- Update the affected in-memory collections directly after:
  - rename
  - delete
  - metadata update
  - tag add/remove
  - collection assignment
  - note save
- Reduce or eliminate "fetch all then map everything again" paths
- Replace broad `refreshDocumentList()`-style refreshes with targeted refresh helpers

Expected win:

- Faster rename, delete, tagging, note save, and collection operations
- Less unnecessary work on the main actor
- Better scalability as the library grows

### Milestone 2: Remove Render-Path I/O

This is the second implementation milestone and should ship with Milestone 1.

Goals:

- Eliminate synchronous file and image work from SwiftUI row `body` evaluation
- Reduce list scroll jank

Implementation direction:

- Move file size lookup out of row rendering
- Cache thumbnail/file metadata in view-model or derived presentation state
- Replace per-render formatter construction with shared static formatters
- Make search-result thumbnail loading asynchronous
- Avoid synchronous `PlatformImage.loadFromURL(...)` in list rows

Expected win:

- Smoother scrolling
- Less repeated disk I/O
- Lower CPU usage while browsing large lists

### Milestone 3: Stabilize PDF Detail Lifetime

This milestone improves perceived responsiveness in document detail.

Goals:

- Prevent repeated PDF reloads when parent views redraw
- Prevent repeated annotation work when unrelated UI changes happen

Implementation direction:

- Introduce a long-lived per-document detail controller or `@StateObject`
- Ensure `PDFViewerViewModel` survives parent redraws while the same document is selected
- Avoid rebuilding `PDFDocument` unless the selected document actually changes
- Move annotation application toward delta-based updates rather than full clear-and-reapply

Expected win:

- Faster document opening after initial load
- Reduced redraw churn
- Better annotation responsiveness

### Milestone 4: Add Versioned Index Infrastructure

This is the first migration-sensitive milestone.

Goals:

- Introduce a search/index subsystem without changing canonical storage
- Make the new index versioned, rebuildable, and safe to roll forward

Implementation direction:

- Add a dedicated search index location under `Index/Search/`
- Add a library manifest file under `Index/manifest.json`
- Record:
  - `librarySchemaVersion`
  - `searchIndexVersion`
  - `migrationState`
  - `lastFullBuildAt`
  - `lastIncrementalUpdateAt`
  - `libraryFingerprint`
- Build the index using stable `Document.id` and `Note.id`
- Keep old search behavior available as fallback until the index is ready

Expected win:

- Creates the foundation for fast search without risking library compatibility

### Milestone 5: Switch Content Search To Indexed Reads

This milestone replaces the current brute-force content search approach.

Goals:

- Stop reopening and scanning every PDF per query
- Make search latency predictable on larger libraries

Implementation direction:

- Index:
  - PDF extracted text
  - page-level snippets
  - document titles
  - note titles
  - note bodies
- Incrementally update the index on:
  - import
  - note save
  - rename
  - metadata edit
  - delete
- Keep search fallback behavior when the index is missing, stale, or rebuilding

Expected win:

- Search latency drops from brute-force scan time to indexed lookup time

### Milestone 6: Optimize Import And Lookup Paths

This milestone improves memory efficiency and lookup performance.

Goals:

- Reduce import memory spikes
- Reduce repeated note/document resolution work

Implementation direction:

- Replace whole-file checksum loading with streamed hashing
- If still needed after profiling, add optional direct path metadata such as:
  - stored relative path
  - stored filename
  - indexed-at timestamp
- Populate new lookup metadata lazily
- Keep existing fallback resolution paths for compatibility

Expected win:

- Lower memory usage during import
- Less repeated directory scanning

### Milestone 7: Defer Heavy Startup Work

This milestone improves first-launch and library-open responsiveness.

Goals:

- Move non-critical maintenance work off the immediate startup path

Implementation direction:

- Defer:
  - thumbnail backfill
  - storage recalculation
  - non-urgent repair jobs
- Run these tasks after first interactive frame or as visible background jobs
- Make migration and maintenance resumable if the app closes mid-run

Expected win:

- Faster time to usable UI
- Less launch-time blocking for large libraries

## What Should Ship First

Recommended ship order:

1. Milestone 1: Remove full refresh churn
2. Milestone 2: Remove render-path I/O
3. Milestone 3: Stabilize PDF detail lifetime
4. Milestone 4: Add versioned index infrastructure
5. Milestone 5: Switch content search to indexed reads
6. Milestone 6: Optimize import and lookup paths
7. Milestone 7: Defer heavy startup work

The safest immediate release package is:

- Milestone 1
- Milestone 2
- Milestone 3

These provide the best user-visible performance gains without introducing storage migration risk.

## Migration Policy For The Next Ship

### Non-Negotiable Constraints

For the next release:

- Do not change where PDFs live on disk
- Do not change where notes live on disk
- Do not make the search index authoritative
- Do not remove legacy file resolution logic
- Do not make migration completion a requirement for opening the library

### Migration Principles

1. Canonical data remains:
   - Core Data metadata
   - stored PDFs
   - stored Markdown notes
2. New indexes and derived metadata must be rebuildable from canonical data.
3. All migration work must be resumable after interruption.
4. Corrupt indexes must be disposable and rebuildable.
5. Reads must fall back to legacy behavior until the new path is verified.

## Migration Design

### Search Index Migration

The next version should support three states:

- `no index yet`
- `index building`
- `index ready`

Behavior by state:

- If there is no index yet:
  - open the library normally
  - start background backfill
  - optionally use current search behavior as fallback
- If the index is building:
  - keep library browsing fully available
  - show search as rebuilding or use fallback search
- If the index is ready:
  - use indexed search by default

Migration flow:

1. Detect an existing library using current folder structure.
2. Create `Index/manifest.json` if it does not exist.
3. Mark manifest migration state as `pending`.
4. Open the library immediately using current code paths.
5. Start a background scan of existing documents and notes.
6. Build the new index into a temporary file:
   - e.g. `search-v1.sqlite.tmp`
7. Validate the index contents.
8. Atomically replace or promote the temporary index into the live location.
9. Mark manifest migration state as `ready`.

Failure behavior:

- If index build fails, keep existing app behavior
- If validation fails, discard the temporary index
- If the live index is corrupt, delete and rebuild it from canonical data

### Optional Core Data Additions

If new Core Data fields are needed for performance, they should be additive and optional.

Examples:

- `searchIndexedAt`
- `textFingerprint`
- `storedRelativePath`
- `storedFilename`
- `lastResolvedAt`

Rules:

- Do not make launch depend on these fields
- Use them when present
- Fall back to legacy resolution when absent
- Populate them lazily during normal operations or background maintenance

### File Lookup Compatibility

If direct file lookup metadata is added:

- Use the new metadata first when available
- If missing or stale, fall back to current resolution logic
- After a successful fallback resolution, write back the derived metadata opportunistically
- Keep old resolution logic for at least one full release after rollout

### Note Storage Compatibility

For the next ship:

- Keep existing note file layout and naming compatible with current libraries
- Do not require renaming all note files as part of migration
- Do not require rewriting Markdown note contents to support performance work

If note lookup metadata is added:

- Derive it from current files
- Populate lazily
- Never block note opening on metadata backfill

## Core Data Migration Approach

The current release should remain within lightweight migration.

That means:

- Add optional attributes only
- Add additive entities only if necessary
- Avoid relationship cardinality changes
- Avoid renaming current fields in the next ship

If a dedicated search bookkeeping entity is needed:

- Add it as a new entity
- Keep it independent from the canonical `Document` and `Note` storage model
- Treat it as derived state

## Validation Gates

The next ship is not ready unless all of these are true:

### Gate A: Existing Library Opens Cleanly

- A library created by the current release opens in the new app without repair prompts
- Documents and notes remain readable before migration completes

### Gate B: Search Works During Migration

- Search remains available during index backfill
- If necessary, it can temporarily fall back to slower behavior

### Gate C: Interrupted Migration Resumes

- Force quit during migration does not break the library
- Next launch resumes or safely restarts index backfill

### Gate D: Corrupt Index Recovery Works

- Deleting or corrupting the search index does not damage the library
- The app can rebuild the index from canonical storage

### Gate E: Incremental Consistency Holds

After rollout, these actions must keep the index and UI consistent:

- import
- rename
- delete
- metadata edit
- note save
- tag edit
- collection change

### Gate F: Large Library Performance Improves

Run smoke tests on larger libraries and compare before/after:

- launch time
- list interaction speed
- scroll smoothness
- document open latency
- content search latency

## Engineering Deliverables By Milestone

### Milestone 1 Deliverables

- Refactored mutation APIs that return changed items or changed IDs
- Removal or reduction of broad refresh helpers
- Stable list snapshots for documents, notes, tags, and collections

### Milestone 2 Deliverables

- Async thumbnail loading for search results
- Cached file metadata
- Shared formatter instances
- No synchronous file attribute access in row bodies

### Milestone 3 Deliverables

- Stable per-document detail controller
- Long-lived PDF viewer state while selection is unchanged
- Delta-based annotation update path

### Milestone 4 Deliverables

- Search service abstraction
- Versioned manifest format
- Index builder
- Index validator
- Migration state handling

### Milestone 5 Deliverables

- Indexed content search
- Page/snippet search results
- Incremental index update hooks
- Background backfill for old libraries

### Milestone 6 Deliverables

- Streamed hashing
- Optional derived lookup metadata
- Reduced directory scans

### Milestone 7 Deliverables

- Deferred maintenance scheduler
- Non-blocking startup repair jobs
- User-visible status for long-running background maintenance

## Recommended Engineering Timeline

Suggested order of execution:

- Week 1:
  - instrumentation
  - benchmark libraries
  - performance budgets
- Week 2:
  - Milestone 1 refresh refactor
- Week 3:
  - Milestone 2 render-path cleanup
- Week 4:
  - Milestone 3 PDF detail stabilization
- Week 5:
  - Milestone 4 index scaffolding and manifest
- Week 6:
  - Milestone 5 indexed search and backfill
- Week 7:
  - Milestone 6 import and lookup optimization
- Week 8:
  - Milestone 7 deferred startup work
  - migration regression testing
  - release hardening

## Release Recommendation

For the next ship:

- Prioritize user-visible responsiveness first
- Keep storage changes additive only
- Ship new index infrastructure only with fallback behavior
- Preserve current library readability at every step

If tradeoffs are required, prefer:

- slower migration with safe fallback

over:

- faster migration that risks old libraries becoming unreadable

That tradeoff is the correct one for the next release.

## File-By-File Implementation Checklist

This section maps each milestone to the current codebase so implementation can proceed in a controlled order.

### 1. App Composition And Refresh Flow

#### `Sources/WndrApp/Sources/WndrApp.swift`

Primary responsibilities to refactor:

- `setupViewModels()`
- `updateViewModelsFromService()`
- `refreshDocumentList()`
- `updateStorageInfo()`
- `handleToggleTag(...)`
- `handleRenameTag(...)`
- `handleRenameCollection(...)`
- `handleDeleteTag(...)`
- `handleDeleteCollection(...)`
- `handleRenameDocument(...)`
- `handleDeleteDocument(...)`
- `handleRenameNote(...)`
- `handleDeleteNote(...)`
- `handleSetDocumentCollection(...)`
- `handleUpdateDocumentMetadata(...)`
- `regenerateAllThumbnails()`
- current inline content-search implementation in `contentViewModel.onContentSearch`

Implementation checklist:

- Introduce a single view-state sync layer that can apply targeted document, note, tag, and collection updates.
- Replace `refreshDocumentList()` with:
  - targeted document update
  - targeted note update
  - targeted tag refresh
  - targeted collection refresh
  - full resync only as an exceptional recovery path
- Stop calling `fetchAllDocuments()`, `fetchAllNotes()`, `fetchAllTags()`, and `fetchAllCollections()` after every mutation.
- Extract DTO-to-view-item mapping into reusable helpers so mapping logic is not duplicated across initial load, refresh, import, and mutation paths.
- Move content search orchestration out of this file into a dedicated search service abstraction before indexed search is introduced.
- Make storage recalculation incremental or deferred so `updateStorageInfo()` is not triggered on every broad UI refresh.
- Keep the current search fallback path callable for one release even after the new index path is introduced.

Acceptance criteria:

- Single-item actions no longer trigger full library reloads.
- Full sync remains available only as a repair/recovery path.
- Search orchestration is no longer hard-coded inside app composition.

### 2. Document And Note Detail Wiring

#### `Sources/WndrApp/Sources/ContentWrapper.swift`

Primary responsibilities to refactor:

- `dropHandler(urls:)`
- `thumbnailURL(for:)`
- `documentHandler(documentID:url:title:)`
- `makePDFViewer(documentID:url:title:)`
- `linkedNotesHandler(documentID:)`
- `NoteEditorContainerView.configureViewModel()`

Implementation checklist:

- Remove post-import full document reload from `dropHandler(urls:)` and replace it with incremental insertion of imported items.
- Replace repeated thumbnail file existence checks with a metadata-driven or cached thumbnail availability model.
- Replace `makePDFViewer(...)` construction of a fresh `PDFViewerViewModel` on every render with a stable per-document controller.
- Remove debug `print` statements from document open and annotation flows.
- Stop fetching all annotations and remapping the entire annotation array after each create/delete action.
- Make note save update the affected note item directly rather than remapping all notes.
- Introduce a small document-detail coordinator responsible for:
  - cached `PDFDocument`
  - cached `PDFViewerViewModel`
  - annotation state
  - lifecycle cleanup when the selected document changes

Acceptance criteria:

- Reopening inspector or causing parent redraws does not recreate the PDF viewer for the same document.
- Note save and import no longer remap entire collections unnecessarily.

### 3. Data Layer: Documents And Notes

#### `Sources/WndrData/Sources/DocumentService.swift`

Primary responsibilities to refactor:

- `fetchAllDocuments()`
- `fetchAllNotes()`
- `fetchDocuments(for:)`
- `fetchDocuments(forTag:)`
- `renameDocument(...)`
- `updateDocumentMetadata(...)`
- `deleteDocument(...)`
- `deleteNote(...)`
- `updateNote(...)`
- `toggleNotePinned(...)`
- `linkedNotes(forDocumentID:)`
- `linkedNotes(forDocumentTitle:)`
- `calculateTotalStorage(libraryURL:)`
- `searchNoteContent(query:)`
- `repairStoredDocumentURLs(...)`

Implementation checklist:

- Change mutation APIs so they return changed DTOs, changed IDs, or small mutation results rather than forcing a subsequent full fetch.
- For:
  - `renameDocument(...)`
  - `updateDocumentMetadata(...)`
  - `deleteDocument(...)`
  - `deleteNote(...)`
  - `updateNote(...)`
  - `toggleNotePinned(...)`
  update the in-memory published arrays directly on success.
- Keep `fetchAllDocuments()` and `fetchAllNotes()` for initial load and recovery only.
- Introduce a derived/cached lookup for linked notes so `linkedNotes(forDocumentTitle:)` does not fetch and regex-scan every note on demand.
- Move storage calculation onto a deferred maintenance path or maintain a cached aggregate that updates on import/delete.
- Keep `repairStoredDocumentURLs(...)` as a compatibility tool and expand it to populate optional future path metadata opportunistically.
- Add a migration-safe abstraction for search indexing hooks:
  - `documentImported`
  - `documentUpdated`
  - `documentDeleted`
  - `noteUpdated`
  - `noteDeleted`

Migration-related checklist:

- If optional fields such as `storedRelativePath`, `storedFilename`, `searchIndexedAt`, or `textFingerprint` are added, populate them lazily.
- Never require these fields to exist for a document or note to open successfully.
- Continue resolving files via existing fallback logic when derived metadata is absent or stale.

Acceptance criteria:

- Document and note mutations update local state without a full refetch.
- Linked-note lookup is no longer an on-demand full note scan.
- Compatibility repair code remains intact for old libraries.

### 4. Data Layer: Collections And Tags

#### `Sources/WndrData/Sources/CollectionService.swift`

Primary responsibilities to refactor:

- `fetchAllCollections()`
- `createCollection(...)`
- `updateCollection(...)`
- `deleteCollection(...)`
- `setDocumentCollection(...)`
- `fetchAllTags()`
- `createTag(...)`
- `updateTag(...)`
- `deleteTag(...)`
- `addTag(...)`
- `removeTag(...)`

Implementation checklist:

- Stop calling full `fetchAllCollections()` or `fetchAllTags()` after every mutation.
- Return changed `CollectionDTO` or `TagDTO` values from mutation APIs.
- Update item counts incrementally when a document changes collection or tags.
- Keep a single explicit full-refresh method for recovery, repair, or startup sync only.
- Ensure tag and collection deletion paths still correctly handle selected sidebar fallback.

Acceptance criteria:

- Tag rename, tag assignment, collection rename, and collection assignment no longer force full tag/collection reloads on every action.

### 5. Data Layer: Annotations

#### `Sources/WndrData/Sources/AnnotationService.swift`

Primary responsibilities to refactor:

- `fetchAnnotations(for:)`
- `createHighlight(...)`
- `createNote(...)`
- `updateAnnotation(...)`
- `deleteAnnotation(...)`
- `deleteAllAnnotations(for:)`

Implementation checklist:

- Replace "save then fetch all annotations again" with direct mutation of the local `annotations` array.
- Add APIs that return the created, updated, or deleted annotation identifiers/DTOs.
- Preserve `fetchAnnotations(for:)` for initial document open and recovery only.
- Keep annotation ordering stable by page index and creation time after local mutations.
- Prepare an annotation diff payload suitable for the PDF layer:
  - inserted annotations
  - deleted annotations
  - updated annotations

Acceptance criteria:

- Creating or deleting one annotation does not cause a full annotation refetch unless recovery is needed.

### 6. Import Pipeline

#### `Sources/WndrData/Sources/ImportService.swift`

Primary responsibilities to refactor:

- `importDocument(from:in:copyFile:)`
- `importMultipleDocuments(from:in:)`
- `calculateChecksum(for:)`
- metadata extraction flow

Implementation checklist:

- Replace `Data(contentsOf:)` checksum hashing with streamed hashing to reduce peak memory usage for large PDFs.
- Add post-import hooks that notify:
  - document state caches
  - thumbnail generation scheduler
  - search index updater
- Keep the imported file location and canonical library layout unchanged for the next ship.
- If indexing is introduced, queue indexing as asynchronous follow-up work rather than blocking import completion.

Migration-related checklist:

- Do not move imported PDFs into a new canonical location for the next release.
- If a search index exists, treat indexing as derived post-processing only.

Acceptance criteria:

- Large PDF import no longer requires loading the entire file into memory for checksuming.
- Import remains compatible with current library structure.

### 7. Library Layout And Resolution

#### `Sources/WndrData/Sources/LibraryRootStore.swift`

Primary responsibilities to refactor:

- `documentURL(for:in:filename:)`
- `resolveNoteFile(for:in:)`
- `renameNoteFile(noteID:to:in:)`
- `findDocumentFile(for:in:)`
- `resolveDocumentFile(for:preferredURL:documentType:in:)`
- `renameDocumentFile(documentID:to:in:)`
- `deleteStoredDocumentAssets(...)`
- `thumbnailURL(for:in:)`

Implementation checklist:

- Keep the existing `PDFs/`, `Notes/`, `Attachments/`, `Index/`, and `Cache/` layout unchanged for the next ship.
- Add helper paths for:
  - `Index/manifest.json`
  - `Index/Search/`
  - temporary index files
- Keep current file resolution as the fallback path for old libraries.
- If optional direct path metadata is introduced elsewhere, keep these resolution helpers authoritative for fallback and repair.
- Add atomic swap helpers for search index promotion:
  - build temp index
  - validate
  - replace live index

Migration-related checklist:

- Existing note files named by legacy ID and current title-based filenames must both remain readable.
- Existing document directories and generic `document.pdf` layouts must remain readable.
- No migration should rename all user files eagerly during first launch.

Acceptance criteria:

- Any new indexing files live under `Index/` only.
- Old libraries still open even if the new index is missing or invalid.

### 8. Content List And Row Rendering

#### `Sources/WndrKit/Sources/ContentAreaView.swift`

Primary responsibilities to refactor:

- `ContentListView`
- `DocumentListView`
- `DocumentRow`
- `NoteListView`
- `SearchResultsListView`
- `ContentListStatusBar`
- `ThumbnailImageView`

Implementation checklist:

- Remove synchronous file size lookup from `DocumentRow.formattedFileSize`.
- Replace per-render `ByteCountFormatter()` construction with shared static formatters.
- Stop resolving collection name via linear lookup during every row render if that becomes measurable; precompute it in presentation state.
- Make all search-result thumbnails use asynchronous/cached loading, matching the behavior of `ThumbnailImageView`.
- Ensure status bar formatting does not recreate expensive formatters every render.
- Keep `List` rendering fed by stable, precomputed arrays rather than repeatedly computed/sorted projections.

Acceptance criteria:

- Row rendering does not perform synchronous disk I/O.
- Scrolling large document lists remains smooth.

### 9. Content View Model

#### `Sources/WndrKit/Sources/ContentAreaViewModel.swift`

Primary responsibilities to refactor:

- `filteredDocuments`
- `filteredNotes`
- `sortDocuments(_:)`
- `sortNotes(_:)`
- `performContentSearch(query:)`
- `updateContent(for:)`

Implementation checklist:

- Replace computed `filteredDocuments` and `filteredNotes` with memoized or explicitly recomputed snapshots.
- Recompute filtered/sorted arrays only when these inputs change:
  - documents
  - notes
  - search text
  - search mode
  - sort option
- Keep cancellation behavior for content search but move actual search work behind a service abstraction.
- If indexed search rollout is feature-flagged, let the view model switch between:
  - legacy search implementation
  - indexed search implementation
- Make `updateContent(for:)` avoid clearing and rebuilding data unnecessarily when only selection changes.

Acceptance criteria:

- Filtering and sorting do not rerun on every unrelated SwiftUI body evaluation.
- Search mode switching remains responsive and cancellable.

### 10. Detail Composition And Inspector

#### `Sources/WndrKit/Sources/WndrKit.swift`

Primary responsibilities to refactor:

- `DetailAreaView.detailContent`
- `currentInspectorMode`
- `currentLinkedNotes`

Implementation checklist:

- Decouple detail rendering from list-backed arrays so the selected document can stay alive even if the list state updates.
- Stop deriving linked notes by scanning all notes synchronously during inspector rendering.
- Use cached or precomputed linked-note data for the current document.
- Ensure document detail can still render if list projections are filtered or temporarily reloading.

Acceptance criteria:

- Inspector toggling and list updates do not destabilize the current document detail session.

### 11. PDF Viewer State And Annotation Application

#### `Sources/WndrPDF/Sources/PDFViewerViewModel.swift`

Primary responsibilities to refactor:

- initializer paths
- `setAnnotations(_:)`
- `applyAnnotationsToDocument()`
- `removeAnnotationAt(pageIndex:bounds:)`
- `loadDocument(from:)`
- `thumbnail(for:)`

Implementation checklist:

- Stop printing debug output on document load and annotation application.
- Split PDF loading from initialization so the same view model can be retained and updated explicitly.
- Replace full annotation clear-and-reapply with delta application:
  - add only inserted highlights
  - remove only deleted highlights
  - update only changed highlights
- Cache generated page thumbnails with an eviction policy if memory pressure becomes measurable.
- Add explicit lifecycle hooks for document open, document close, and annotation resync.

Acceptance criteria:

- Annotation changes no longer require clearing all highlights from every page.
- Reusing the same selected document does not recreate the underlying PDF state.

### 12. PDF View Integration

#### `Sources/WndrPDF/Sources/PDFViewerView.swift`

Primary responsibilities to refactor:

- `PDFThumbnailListView`
- `PDFThumbnailItemView`
- `PDFViewRepresentable`
- `PDFViewCoordinator`

Implementation checklist:

- Make thumbnail sidebar generation lazy and non-blocking where possible.
- Keep `PDFViewRepresentable` updates minimal so the underlying `PDFView` does not churn.
- Ensure selection-created highlights only persist the diff needed for storage.
- Confirm that page-change and selection notifications do not trigger unnecessary feedback loops.

Acceptance criteria:

- Thumbnail navigation remains responsive even for larger PDFs.
- PDF view updates are minimal and scoped to the actual change.

### 13. App Startup And Maintenance Jobs

#### `Sources/WndrApp/Sources/AppEnvironment.swift`

Implementation checklist:

- Move thumbnail backfill, tag maintenance, storage maintenance, and migration work off the immediate app startup path.
- Introduce a maintenance scheduler with explicit job types:
  - thumbnail backfill
  - storage recalc
  - search index backfill
  - migration repair
- Run non-critical jobs after the first interactive UI is available.
- Persist progress for long-running backfills so work resumes safely after interruption.

Acceptance criteria:

- Large libraries become interactive before maintenance work completes.

### 14. Persistence Model And Migration State

#### `Sources/WndrData/Resources/WndrModel.xcdatamodeld/WndrModel.xcdatamodel/contents`

Implementation checklist:

- Keep schema changes additive only for the next ship.
- If needed, add only optional fields or new additive entities.
- Do not rename or remove existing fields in this cycle.
- If search bookkeeping is stored in Core Data, keep it separate from canonical document/note content.

Migration-related checklist:

- Existing persistent stores must open with lightweight migration.
- New optional fields must not be required for existing records to render.

Acceptance criteria:

- Existing libraries open in the next release without manual intervention.

## Search Index Rollout Checklist

The search index rollout should be implemented as infrastructure first, then behavior switch second.

### Phase A: Infrastructure

Files most likely involved:

- `Sources/WndrData/Sources/LibraryRootStore.swift`
- new search service and index builder files under `Sources/WndrData/Sources/`
- `Sources/WndrApp/Sources/AppEnvironment.swift`
- `Sources/WndrApp/Sources/WndrApp.swift`

Checklist:

- Add manifest read/write support.
- Add index path helpers under `Index/Search/`.
- Add temporary build and atomic promotion helpers.
- Add migration state model:
  - pending
  - building
  - ready
  - failed
- Add version checks for index compatibility.

### Phase B: Backfill

Checklist:

- Enumerate current documents and notes from canonical storage.
- Build index in the background.
- Validate sampled results before promoting live.
- Resume gracefully after interruption.

### Phase C: Cutover

Checklist:

- Switch search calls from legacy brute-force scan to indexed search.
- Keep legacy fallback available if:
  - no index exists
  - index is stale
  - index is corrupt
  - backfill is still running

### Phase D: Incremental Maintenance

Checklist:

- Update the index after:
  - import
  - rename
  - metadata edit
  - note save
  - delete
- Log and surface rebuild state if incremental updates fail repeatedly.

## Recommended First PR Sequence

To reduce risk, implementation should begin with these pull requests:

1. PR 1:
   - instrumentation
   - shared mapping helpers
   - removal of duplicated mapping code in app composition
2. PR 2:
   - incremental document/note/tag/collection mutation updates
   - removal of broad refresh calls from common actions
3. PR 3:
   - render-path cleanup in content list rows
   - shared formatter and cached metadata introduction
4. PR 4:
   - stable document detail controller
   - PDF viewer lifetime stabilization
   - annotation delta updates
5. PR 5:
   - index manifest and search service scaffolding
   - no behavior cutover yet
6. PR 6:
   - background index backfill
   - legacy fallback support
7. PR 7:
   - indexed search cutover
   - migration recovery hardening
8. PR 8:
   - import streaming hash
   - deferred startup maintenance
   - large-library regression pass
