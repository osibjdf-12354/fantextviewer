# Page Turn Line Overlap Design

## Goal

Repeat the previous page's final two visually wrapped lines at the top of the
next page so novel text remains easy to follow after swipe, tap, or automatic
page turns.

## Chosen approach

Keep each page's logical source range non-overlapping and add a separate
display start offset. The paginator measures the last two visible lines of the
current page and uses their source offset as the next page's display start.
The next page is laid out from that display start, so the repeated lines consume
normal page space and no text is clipped at the bottom.

Logical `start` and `end` offsets continue to drive page numbers, bookmarks,
search, saved progress, and `pageForOffset`. Only rendering uses the display
start. The first page has no overlap. If the viewport cannot fit two repeated
lines plus new content, the overlap shrinks so every page advances.

## Pagination and cache

Both complete and window pagination produce the same display offsets. Completed
page-index cache records store logical starts and display starts. The pagination
algorithm version changes so older cache records are ignored and rebuilt
without affecting document data.

## Reader behavior

Swipe, tap, and automatic page modes all render the shared page list, so the
overlap applies consistently without mode-specific code. Scrolling remains
unchanged.

## Verification

- Paginator tests verify two visual lines repeat while logical ranges remain
  continuous and every page advances.
- Window pagination follows the same rule.
- Cache tests round-trip display starts and reject malformed records.
- Reader tests verify rendering begins at the display start.
- Formatting, analysis, and the full Flutter test suite remain clean.
