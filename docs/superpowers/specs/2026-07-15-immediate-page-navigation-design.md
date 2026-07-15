# Immediate Page Navigation and Page Number Display

## Goal

Large TXT files must accept a page-number jump before the full exact page index finishes. The drawer subtitle and the bottom-right reader indicator must show the current page as `N페이지`; neither location may show a percentage.

## Current Defect

`ReaderView` exposes page navigation only through `_completePages`. Progressive page batches make the document readable, but the jump dialog, bookmarks, and page labels remain blocked until every page from the beginning of the file has been laid out. On a large file this makes page navigation appear broken.

## Chosen Design

Use two page models:

1. The existing exact page index continues to build progressively and remains the authoritative model when complete. Its cache remains unchanged.
2. Until that index is complete, a provisional model estimates page count and the source offset for a requested page from measured characters per rendered page. A request for page `N` immediately lays out a small source window around the estimated offset and displays it. The requested page number is retained as the window's display-page anchor.

The provisional window is independent of the progressive exact-prefix list, so later background batches cannot snap the reader back to the beginning. When the exact index becomes ready, the reader replaces the provisional window with the exact page containing the same source offset.

The provisional model must preserve all source text. A window may begin at an estimated source position, but it aligns to a nearby line boundary and uses the existing `TextPainter` boundary calculation inside the window. Exact completion is the final correction mechanism.

## Page Number Rules

- Drawer subtitle: `현재 N페이지`.
- Bottom-right indicator: `N페이지`.
- No percentage appears in either location.
- With a complete index, `N` is `pageForOffset(exactPages, offset) + 1`.
- While incomplete, `N` is the active provisional window page or the page estimated from the current source offset.
- Jumping to a requested page displays that requested number immediately; it is not a hard-coded example value.
- The jump dialog accepts only integer page numbers and validates against the currently displayed estimated or exact total.

## Navigation Flow

1. Open a TXT file and start exact pagination as today.
2. Derive a provisional characters-per-page value from available exact prefix pages; use the existing initial probe as a fallback before the first batch.
3. Open the page dialog even while exact pagination is incomplete.
4. Convert the requested page to a clamped source offset and build a small rendered window there.
5. Show the window and `N페이지` immediately while exact pagination continues.
6. On exact completion, keep the source offset and switch to the authoritative exact page.

Scroll mode uses the same provisional page-number conversion for its label and can jump directly through the existing chunk index. Page mode uses the rendered provisional window.

## Error and State Handling

- Empty text has no jump target.
- Stale window and pagination callbacks are ignored with the existing generation guard.
- Display-setting changes invalidate both exact and provisional layouts.
- Cache failures remain non-fatal.
- Page input is clamped only after validation; malformed or out-of-range input receives the existing page-range message.

## Tests

- A pending paginator must not block opening the page-jump dialog.
- A far page request must change the stored source offset and visible page label before exact pagination completes.
- Drawer and bottom-right indicators must contain `페이지` and no `%`.
- Provisional page/offset conversion must cover the first page, a middle page, the final page, and clamping.
- Exact completion must preserve the source position and replace the provisional window.
- Existing encoding-cache, search, bookmark, settings, large-file, and UI tests must continue to pass.

## Scope

No new dependency, database, isolate protocol, or full file-streaming rewrite is added. This change fixes immediate navigation and page-number presentation while retaining the current exact index and cache.
