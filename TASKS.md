# Wndr Optimisation Tasks

Task tracker for [OPTIMISATION.md](OPTIMISATION.md). Status: `done` | `in progress` | `pending`.

---

## Milestone 0: Instrumentation And Baselines

| Task | Status |
|------|--------|
| Add `PerformanceMetric` enum for tracked measurements | done |
| Add `PerformanceMonitor` with os_signpost intervals and logging | done |
| Add `BenchmarkLibraryProfile` (small / medium / large) | done |
| Add `PerformanceBudget` pass/fail thresholds per profile | done |
| Instrument app launch time | done |
| Instrument library bootstrap time | done |
| Instrument list refresh time (scoped metadata) | done |
| Instrument document open latency | done |
| Instrument content search latency | done |
| Instrument import batch time | done |
| Instrument thumbnail generation time | done |
| Document benchmark library creation guide | done |
| Instrument PDF annotation update time | pending |

---

## Milestone 1: Remove Full Refresh Churn

| Task | Status |
|------|--------|
| Add incremental in-memory update helpers to `DocumentService` | done |
| Refactor document mutations to upsert/remove instead of `fetchAllDocuments()` | done |
| Refactor note mutations to upsert/remove instead of `fetchAllNotes()` | done |
| Add `CollectionMutationResult` for mutation side effects | done |
| Refactor `CollectionService` mutations to update tags/collections incrementally | done |
| Extract `RootViewMapper` shared mapping helpers | done |
| Add `LibraryViewStateSync` targeted view-state sync layer | done |
| Replace `refreshDocumentList()` with targeted sync helpers | done |
| Update document rename/delete/metadata handlers to targeted sync | done |
| Update note rename/delete handlers to targeted sync | done |
| Update tag toggle/rename/delete handlers to targeted sync | done |
| Update collection rename/delete/assignment handlers to targeted sync | done |
| Incremental import sync via `lastImportedDocumentIDs` | done |
| Remove post-import full reload from `ContentWrapper` drop handler | done |
| Remove redundant `fetchAllDocuments()` from content search path | done |
| Keep `fetchAll*` as initial-load and recovery paths only | done |
| Refactor `AnnotationService` to delta updates instead of full refetch | pending |
| Incremental thumbnail regen UI sync (full resync retained as recovery) | done |

---

## Milestone 2: Remove Render-Path I/O

| Task | Status |
|------|--------|
| Move file size lookup out of row rendering | done |
| Cache thumbnail/file metadata in view-model state | done |
| Replace per-render formatter construction with shared static formatters | done |
| Async search-result thumbnail loading | done |
| Remove synchronous `PlatformImage.loadFromURL` from list rows | done |

---

## Milestone 3: Stabilize PDF Detail Lifetime

| Task | Status |
|------|--------|
| Long-lived per-document detail controller | pending |
| Stable `PDFViewerViewModel` across parent redraws | pending |
| Delta-based annotation update path in PDF layer | pending |

---

## Milestone 4: Add Versioned Index Infrastructure

| Task | Status |
|------|--------|
| Search service abstraction | pending |
| Versioned `Index/manifest.json` format | pending |
| Index builder and validator | pending |
| Migration state handling (pending / building / ready / failed) | pending |

---

## Milestone 5: Switch Content Search To Indexed Reads

| Task | Status |
|------|--------|
| Indexed content search | pending |
| Page/snippet search results | pending |
| Incremental index update hooks | pending |
| Background backfill for old libraries | pending |

---

## Milestone 6: Optimize Import And Lookup Paths

| Task | Status |
|------|--------|
| Streamed checksum hashing | pending |
| Optional derived lookup metadata | pending |
| Reduced directory scans | pending |

---

## Milestone 7: Defer Heavy Startup Work

| Task | Status |
|------|--------|
| Deferred maintenance scheduler | pending |
| Non-blocking startup repair jobs | pending |
| User-visible status for long-running background maintenance | pending |
