# Settings Auto-apply on Close Design

## Goal

Remove the Display Settings apply button and commit changed settings once when
the sheet closes, avoiding repeated reader rebuilds and pagination while the
sheet is open.

## Behavior

- All controls update only the sheet-local draft and preview while the sheet
  remains open.
- Dismissing by drag, back, or tapping outside applies the final draft once.
- Opening and closing the sheet without changes performs no settings update,
  save, or pagination reset.
- The apply button is removed.
- Font size, font, line height, padding, colors, reading mode, page-turn
  direction, page display, and keep-awake settings all follow the same
  close-to-apply rule.
- Deleting a font that is referenced by saved settings remains an immediate
  reset to the system font because the backing file no longer exists.
- Invalid RGB input keeps the last valid draft values and existing validation
  feedback.

## Implementation

Keep the existing `draft` inside `_showSettings`. After
`showModalBottomSheet` completes, compare the draft with the current settings
using their existing JSON representation. Call `_applySettings(draft)` only
when they differ. The existing save debounce and pagination invalidation then
run once.

Remove the bottom `FilledButton`. Make the three `_SettingStepper` rows denser
by applying Flutter's native `VisualDensity.compact` to their decrement and
increment icon buttons; add no new layout component or fixed row height.

## Verification

- Widget tests prove changes are not applied while the sheet is open.
- Dismissal by back and drag/tap-outside applies and persists the final draft.
- Closing without changes does not notify the store or restart pagination.
- The apply button is absent.
- Stepper icon buttons use compact visual density.
- Existing font import, deletion, RGB validation, navigation, pagination, and
  full application tests remain green.
