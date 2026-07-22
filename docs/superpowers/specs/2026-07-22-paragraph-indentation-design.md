# Paragraph Indentation Design

## Goal

Add optional novel-style paragraph indentation to Display Settings without
modifying the source text or breaking saved reading positions, bookmarks,
search results, or pagination.

## Behavior

- Display Settings offers `없음`, `한 글자`, and `두 글자` choices.
- The default and migration value is `없음`.
- The first non-empty line in the file and every non-empty line after a
  newline are paragraph starts.
- A paragraph that already starts with an ASCII space, tab, or ideographic
  space receives no additional indentation.
- Indentation uses one or two ideographic spaces (`U+3000`).
- A page or scroll chunk beginning in the middle of a paragraph does not add
  a new indent.
- The setting follows the existing draft workflow: it is applied, saved, and
  repaginated once when the Display Settings sheet closes.

## Data Model and Persistence

Add an integer `paragraphIndent` field to `ReaderSettings`. Only values from
zero through two are valid. JSON without the field, or with any numeric value
other than the integers zero, one, and two, restores zero. Include the field
in `copyWith`, `toJson`, and `fromJson` so it follows the existing settings
store without a migration.

## Text Formatting and Offset Mapping

Keep the decoded source string unchanged. A shared formatting helper accepts
an absolute source range and an indentation level, then returns the display
text plus enough insertion metadata to convert a display offset back to the
corresponding source offset.

The helper inserts spaces only when the range contains an actual paragraph
start in the source. This lets scroll chunks and individual pages use the
same behavior even when their ranges begin mid-paragraph. Added spaces may
appear in copied selected text, but all application-owned offsets remain
source offsets.

## Rendering and Pagination

- Scroll mode formats each existing chunk immediately before rendering it.
- Page and tap modes format each page's source range before rendering it.
- Pagination measures the same formatted text shown by the reader. When
  `TextPainter` returns a display position for a page boundary, the helper
  maps it back to a source offset before creating `TextPage`.
- Add `paragraphIndent` to the pagination cache signature and increment the
  algorithm version so old page indexes cannot be reused.
- Search, bookmarks, excerpts, and saved progress continue to use the
  unmodified source string.

## Display Settings UI

Place a `문단 들여쓰기` choice row with the existing typography controls.
The three choice chips update only the sheet-local draft. Closing the sheet
uses the existing change comparison and `_applySettings` path; opening and
closing without a change remains a no-op.

## Validation

- Model tests cover the zero default, JSON round-trip, `copyWith`, and
  out-of-range fallback.
- Formatting tests cover one- and two-character indentation, blank lines,
  pre-indented paragraphs, mid-paragraph ranges, and display-to-source offset
  mapping.
- Pagination tests prove that indentation affects measured page boundaries
  while every `TextPage` still contains valid source offsets.
- Reader widget tests cover the three UI choices, draft-only behavior while
  the sheet is open, close-time persistence, rendered indentation, and page
  cache invalidation.
- Existing full application tests remain green.
