# Tap-only Reading Mode Design

## Goal

Separate page navigation input into explicit reading methods: vertical scrolling,
swiping, and tapping. Swipe mode must ignore taps, while tap mode must ignore
swipes.

## Behavior

- Rename the existing `페이지 넘김` choice to `스와이프` without changing the
  saved meaning of existing `ReadingMode.page` values.
- Add `ReadingMode.tap` and a `탭` choice.
- `ReadingMode.scroll` keeps the current vertical scroll behavior and performs
  no tap-based page navigation.
- `ReadingMode.page` keeps paginated rendering and accepts swipes only.
- `ReadingMode.tap` uses the same pagination, progress, restoration, search,
  bookmark, and page-jump flows, but accepts taps only.
- Tap zones follow the saved page-turn direction:
  - horizontal: left half is previous, right half is next;
  - vertical or both: top half is previous, bottom half is next.
- When `둘 다` is selected, Display Settings shows the small helper text
  `둘 다 모드에서는 탭 영역이 위/아래로 나뉩니다.`
- Long press remains available to `SelectableText` in both paginated methods.

## Implementation

Reuse `PageTurnView` and gate its existing pointer handling with two input
flags. `ReaderView` supplies swipe-only flags for `ReadingMode.page` and
tap-only flags for `ReadingMode.tap`. Both modes share all existing pagination
and page-index state; scroll mode remains on its existing reader path.

Persist `ReadingMode.tap` through the existing enum-name JSON format. Missing
or older saved values retain their current defaults, and saved `page` values
continue to mean swipe mode.

## Verification

- Component tests prove horizontal left/right taps and vertical/both top/bottom
  taps.
- Component tests prove taps are ignored in swipe-only mode and swipes are
  ignored in tap-only mode.
- Reader tests prove all three choices render and persist, the helper text is
  conditional on `둘 다`, and existing `page` settings display as `스와이프`.
- Full analysis, tests, and release APK build remain green.
