# Shared Pagination and System Gesture Indicator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every reading mode use one pagination result, preserve the visible position when auto mode starts, and place the page indicator at the bottom-right of the real system gesture area.

**Architecture:** `ReaderView` will start the existing paginator in every reading mode and keep estimates internal while exposing only indexed page numbers. The reader body and page indicator will become sibling layout regions, with the indicator region constrained by `MediaQuery.viewPadding.bottom` instead of a fixed inset.

**Tech Stack:** Flutter, Dart, `flutter_test`, existing `paginateText`/`PageIndexCache`/`PageTurnView`

## Global Constraints

- Keep vertical scrolling continuous.
- Reuse the existing paginator, page cache, and page-overlap algorithm.
- Do not add dependencies or fixed system-bar heights.
- Place the indicator at the bottom-right, not the center, of the system gesture area.
- Preserve the current document offset during every mode transition.

---

### Task 1: Share exact pagination across reading modes

**Files:**
- Modify: `lib/reader_screen.dart`
- Test: `test/reader_screen_test.dart`

**Interfaces:**
- Consumes: existing `_ensurePages(Size)`, `_pages`, `_paginationComplete`, `_offset`, and `pageForOffset`
- Produces: `_hasIndexedCurrentPage` and `_pageIndicatorLabel` getters used by the common indicator

- [ ] **Step 1: Update the long-scroll pagination test to require immediate background pagination**

Rename `large scroll mode paginates only on demand and after resize` to `large scroll mode shares pagination and recalculates after resize`. Change the initial expectation from zero calls to one call, remove the go-to dialog interaction, resize, and expect two calls.

- [ ] **Step 2: Add a failing test for shared exact page numbers**

Create a document longer than `256 * 1024`, save a chunk-aligned distant offset, and inject exact 100-character pages:

```dart
final chunks = splitText(text, maxChars: 700);
final targetOffset = chunks[200].start;
final pages = [
  for (var start = 0; start < text.length; start += 100)
    TextPage(start: start, end: math.min(start + 100, text.length)),
];
```

After the initial scroll render, assert the indicator is `${pageForOffset(pages, targetOffset) + 1}`. Enable auto mode and assert the indicator and stored offset are unchanged.

- [ ] **Step 3: Add a failing test that hides unindexed estimates**

Use a long document, a distant saved offset, and an unresolved paginator. After the first frame, assert:

```dart
expect(
  tester.widget<Text>(find.byKey(const Key('page-indicator'))).data,
  '계산 중',
);
```

- [ ] **Step 4: Run the focused tests and verify RED**

Run:

```powershell
flutter test --no-pub test/reader_screen_test.dart --plain-name "large scroll mode shares pagination and recalculates after resize"
flutter test --no-pub test/reader_screen_test.dart --plain-name "scroll and auto modes share exact page numbers"
flutter test --no-pub test/reader_screen_test.dart --plain-name "unindexed scroll position hides the estimated page number"
```

Expected: the initial pagination-call test and both new behavior tests fail against the current mode-specific estimation.

- [ ] **Step 5: Start the existing paginator in every non-empty reading mode**

In the reader `LayoutBuilder`, replace the mode and length condition with one call:

```dart
_ensurePages(pageSize);
```

Keep the long-document window paginator for immediate paged rendering; it does not replace the shared full index.

- [ ] **Step 6: Expose only indexed page numbers**

Add getters that return `계산 중` when the current offset is not covered by the shared prefix or when total pages were requested before full indexing:

```dart
bool get _hasIndexedCurrentPage {
  final pages = _pages;
  return _pageWindow == null &&
      pages != null &&
      pages.isNotEmpty &&
      (_paginationComplete || _offset < pages.last.end);
}

String get _pageIndicatorLabel {
  if (!_hasIndexedCurrentPage ||
      (_settings.showTotalPages && !_paginationComplete)) {
    return '계산 중';
  }
  return _settings.showTotalPages
      ? '$_currentPageNumber/${_completePages!.length}'
      : '$_currentPageNumber';
}
```

Use `_pageIndicatorLabel` in the indicator text. Keep existing estimates private for window pagination and go-to navigation.

- [ ] **Step 7: Run the focused tests and verify GREEN**

Run the three commands from Step 4.

Expected: all three tests pass.

- [ ] **Step 8: Commit**

```powershell
git add -- lib/reader_screen.dart test/reader_screen_test.dart
git commit -m "fix: share pagination across reader modes"
```

### Task 2: Hide stale pages while resolving an auto-mode position

**Files:**
- Modify: `lib/reader_screen.dart`
- Test: `test/reader_screen_test.dart`

**Interfaces:**
- Consumes: existing `_jumpToOffset`, `_pageWindow`, `_pageIndex`, and `windowPaginator`
- Produces: a loading state whenever the requested offset lies outside the currently visible page window

- [ ] **Step 1: Add a failing stale-window regression test**

Start in scroll mode at a distant saved offset. Enable auto mode so the first window paginator returns distant pages, disable auto mode, scroll to the beginning, then enable auto mode while a second window paginator remains unresolved.

Assert that the previous distant marker is absent and `페이지를 계산하고 있습니다.` is visible until the second window completes. Complete the second window with pages covering offset zero and assert the beginning marker is rendered.

- [ ] **Step 2: Run the regression test and verify RED**

Run:

```powershell
flutter test --no-pub test/reader_screen_test.dart --plain-name "auto mode hides a stale page window while resolving the scroll position"
```

Expected: FAIL because the old page window remains visible.

- [ ] **Step 3: Clear the visible page index before asynchronous remapping**

In both `_jumpToOffset` branches that call `_jumpToPageNumber` because the target is outside available pages, clear `_pageIndex` before starting the asynchronous window lookup:

```dart
setState(() => _pageIndex = null);
unawaited(_jumpToPageNumber(...));
```

Do not clear stored `_offset`; the new window must still resolve from the exact scroll position.

- [ ] **Step 4: Run the regression test and verify GREEN**

Run the command from Step 2.

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/reader_screen.dart test/reader_screen_test.dart
git commit -m "fix: hide stale pages during auto transition"
```

### Task 3: Move the indicator into the system gesture area

**Files:**
- Modify: `lib/reader_screen.dart`
- Test: `test/reader_screen_test.dart`

**Interfaces:**
- Consumes: `MediaQuery.viewPaddingOf(context).bottom`, `_settings.horizontalPadding`, and `_pageIndicatorLabel`
- Produces: `_buildSystemPageIndicator(BuildContext)` as a sibling below the reader viewport

- [ ] **Step 1: Replace fixed-inset layout expectations with dynamic system-inset expectations**

Set `tester.view.padding = const FakeViewPadding(bottom: 32)` and assert:

```dart
expect(measuredSize?.height, tester.getSize(find.byType(PageTurnView)).height);
expect((padding.padding as EdgeInsets).bottom, 0);
```

Also assert the reader has no `SafeArea` ancestor.

- [ ] **Step 2: Add a failing bottom-right gesture-area placement test**

For scroll and page modes, calculate:

```dart
final screenHeight =
    tester.view.physicalSize.height / tester.view.devicePixelRatio;
final gestureTop = screenHeight -
    tester.view.padding.bottom / tester.view.devicePixelRatio;
final indicatorRect = tester.getRect(find.byKey(const Key('page-indicator')));
```

Assert the reader ends at `gestureTop`, the indicator lies at or below `gestureTop`, and its right edge is to the right of the screen midpoint.

- [ ] **Step 3: Run the layout tests and verify RED**

Run:

```powershell
flutter test --no-pub test/reader_screen_test.dart --plain-name "page mode uses the full reader viewport for pagination"
flutter test --no-pub test/reader_screen_test.dart --plain-name "page indicator occupies the bottom-right system gesture area"
```

Expected: FAIL because the body still uses `SafeArea`, fixed 40-pixel pagination subtraction, and an overlay indicator.

- [ ] **Step 4: Replace the overlay with sibling layout regions**

Remove `_pageIndicatorInset` and the body `SafeArea`. Build the non-empty body as a `Column`:

```dart
Column(
  children: [
    Expanded(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pageSize = Size(
            math.max(1, constraints.maxWidth - _settings.horizontalPadding * 2),
            math.max(1, constraints.maxHeight),
          );
          _pageSize = pageSize;
          _ensurePages(pageSize);
          return _activeMode == ReadingMode.scroll
              ? _buildScrollReader()
              : _buildPageReader();
        },
      ),
    ),
    _buildSystemPageIndicator(context),
  ],
)
```

- [ ] **Step 5: Size the bottom-right indicator from real layout values**

Return a constrained intrinsic row whose minimum height is the system bottom inset:

```dart
Widget _buildSystemPageIndicator(BuildContext context) {
  return ConstrainedBox(
    constraints: BoxConstraints(
      minHeight: MediaQuery.viewPaddingOf(context).bottom,
    ),
    child: Align(
      alignment: Alignment.bottomRight,
      heightFactor: 1,
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          end: _settings.horizontalPadding,
        ),
        child: _buildPageIndicator(),
      ),
    ),
  );
}
```

Change `_buildPageIndicator` from `Positioned` to its decorated content widget. Remove the indicator from `_buildScrollReader` and `_buildPageReader`, remove their fixed bottom padding, and let the sibling layout prevent overlap.

- [ ] **Step 6: Run the layout tests and verify GREEN**

Run the commands from Step 3.

Expected: both tests pass.

- [ ] **Step 7: Commit**

```powershell
git add -- lib/reader_screen.dart test/reader_screen_test.dart
git commit -m "fix: place page count in system gesture area"
```

### Task 4: Full verification

**Files:**
- Verify: `lib/reader_screen.dart`
- Verify: `test/reader_screen_test.dart`

- [ ] **Step 1: Format changed Dart files**

```powershell
dart format lib/reader_screen.dart test/reader_screen_test.dart
```

- [ ] **Step 2: Run static analysis**

```powershell
flutter analyze --no-pub
```

Expected: `No issues found!`

- [ ] **Step 3: Run the complete test suite**

```powershell
flutter test --no-pub
```

Expected: all tests pass.

- [ ] **Step 4: Check the final diff**

```powershell
git diff --check
git status --short
```

Expected: no whitespace errors and no uncommitted source changes.
