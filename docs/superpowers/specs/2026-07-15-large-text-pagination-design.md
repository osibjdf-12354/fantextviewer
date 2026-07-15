# Large TXT Pagination Performance Design

## Goal

Keep screen-sized page numbers exact while allowing a large TXT file to become readable before its complete page index is ready. Reopening an unchanged file with unchanged display settings should reuse the previous index.

## Approaches considered

1. Fixed character-count pages: fastest, but page numbers would no longer match visible screen pages. Rejected.
2. Android `StaticLayout` worker: can run off the Flutter UI isolate, but Android and Flutter can wrap the same text differently. Rejected because navigation and rendering could disagree.
3. Adaptive Flutter pagination with progressive batches and a persistent exact-index cache: preserves the existing `TextPainter` page model, removes most repeated shaping work, shows early pages while indexing, and makes subsequent opens immediate. Chosen.

## Design

- The paginator will use the previous page length as the next layout probe instead of reshaping a fixed 4,096-character window for every page.
- It will emit newly calculated pages in small batches and yield between batches. The page reader can display a batch as soon as it covers the saved reading offset; scroll mode continues using its existing lightweight chunks until the exact map completes.
- Progress UI updates happen per batch, not per page. Cancellation remains checked per page.
- A completed page map is stored under the application support directory. The cache signature includes file path, size, modification time, text length, viewport width and height, font size, line height, horizontal padding, and a pagination algorithm version.
- Cache records store only page start offsets. Loading validates the signature, text length, first offset, ordering, and bounds before rebuilding `TextPage` ranges.
- At most eight cache records are retained. Cache read/write failure is non-fatal and falls back to calculation.
- Changing the viewport or display settings invalidates the active map through the existing generation mechanism and selects a different cache signature.

## Navigation behavior

- Exact page movement and page-labelled bookmarks continue to use only the complete exact map.
- During first-time indexing, the user can begin reading from already calculated pages instead of waiting at a full-screen spinner.
- Once calculation completes, the exact map replaces the progressive map without changing saved character offsets.

## Verification

- Paginator tests cover progressive batches, cancellation, complete non-overlapping coverage, and adaptive probe sizing.
- Cache tests cover round-trip, stale-signature rejection, malformed/out-of-range rejection, and retention limits.
- Reader widget tests verify that page mode becomes readable from a progressive batch.
- Existing large Korean UTF-8, navigation, bookmark, UI, analysis, and release-build checks remain green.

