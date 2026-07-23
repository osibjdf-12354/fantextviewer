# Page Overlap Handoff Design

## Goal

Keep the previous page's final two visual lines at the top of the next page for
novel-reading continuity, while preventing the outgoing and incoming copies
from appearing together during swipe, tap, or automatic page transitions.

## Chosen approach

Keep the existing logical and display page ranges. The paginator and cache
continue to store a non-overlapping logical `start` plus the earlier
`displayStart` used for the two-line context.

Change only `PageTurnView` animation rendering. During the first half of a
transition it renders the outgoing page alone while translating and fading it
out. At the midpoint, where opacity is zero, it switches to the incoming page.
During the second half it renders the incoming page alone while translating and
fading it in. Therefore the repeated context remains on settled pages, but two
copies never share a frame.

The same handoff uses the selected horizontal or vertical axis. Drag reversal,
cancel-to-current, taps, accessibility actions, and automatic vertical turns
continue through the existing animation controller and page-change callback.

## Alternatives considered

- Mask and move only the shared two-line band between pages. This could preserve
  a continuous seam, but it requires line-height geometry and separate page
  layers in the generic transition component.
- Remove the repeated lines. This eliminates duplication but loses the
  novel-reader continuity requirement.

The single-page midpoint handoff is preferred because it works for both axes
without coupling `PageTurnView` to text layout.

## Boundaries

- First- and last-page outward gestures retain the existing no-op behavior.
- Page-list, direction, or reading-mode changes still cancel an active
  transition.
- Text selection and long-press handling remain unchanged.
- Pagination, page counts, bookmarks, saved offsets, and scroll mode do not
  change.

## Verification

- Component tests prove only one page is rendered before and after the
  transition midpoint for horizontal and vertical movement.
- Existing swipe, tap-only, automatic turn, cancellation, resize, selection,
  and accessibility tests remain green.
- Paginator and reader tests continue to prove that two visual context lines
  repeat without changing logical progress.
- `flutter analyze` and the full Flutter test suite pass.
