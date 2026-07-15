# Immediate Page Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make page-number jumps usable before full pagination completes and replace both reader percentage labels with the current `N페이지` value.

**Architecture:** Keep the existing progressive exact index and cache. Add three small provisional page-mapping functions and a bounded `TextPainter` window paginator; `ReaderView` holds an optional provisional window separately from the exact prefix, then adopts the exact index at the same source offset when it completes.

**Tech Stack:** Dart, Flutter `TextPainter`, Flutter widget tests, existing `PageIndexCache`.

## Global Constraints

- Drawer subtitle is `현재 N페이지`.
- Bottom-right indicator is `N페이지`.
- Neither location contains `%`.
- Page-number jump remains integer-only and works while exact pagination is pending.
- No new dependency or file-streaming rewrite.

---

### Task 1: Provisional page mapping and bounded window pagination

**Files:**
- Modify: `lib/text_paginator.dart`
- Test: `test/text_paginator_test.dart`

**Interfaces:**
- Produces: `estimatedPageCount`, `estimatedPageForOffset`, `estimatedOffsetForPage`, and `paginateTextWindow`.
- Consumes: existing `TextPage`, `pageForOffset`, and `_nextPageEnd`.

- [ ] **Step 1: Write failing mapping tests**

Add tests proving the mapping is generic rather than tied to an example value:

```dart
test('estimates page totals and maps arbitrary pages to offsets', () {
  final pages = List.generate(
    8,
    (index) => TextPage(start: index * 250, end: (index + 1) * 250),
  );

  expect(estimatedPageCount(250000, pages, fallbackCharactersPerPage: 300), 1000);
  expect(estimatedPageForOffset(125000, textLength: 250000, totalPages: 1000), 500);
  expect(estimatedOffsetForPage(500, textLength: 250000, totalPages: 1000), inInclusiveRange(124000, 126000));
});

test('estimated page mapping clamps edges', () {
  expect(estimatedPageForOffset(-1, textLength: 1000, totalPages: 10), 1);
  expect(estimatedPageForOffset(5000, textLength: 1000, totalPages: 10), 10);
  expect(estimatedOffsetForPage(0, textLength: 1000, totalPages: 10), 0);
  expect(estimatedOffsetForPage(99, textLength: 1000, totalPages: 10), 999);
});
```

- [ ] **Step 2: Run mapping tests and verify RED**

Run: `flutter test test/text_paginator_test.dart --reporter expanded`

Expected: compile failure because the three provisional functions do not exist.

- [ ] **Step 3: Implement the minimum mapping functions**

Add public top-level functions that use measured average characters per page, fall back to a caller-supplied positive value, and map page/offset by document ratio:

```dart
int estimatedPageCount(
  int textLength,
  List<TextPage> measuredPages, {
  required int fallbackCharactersPerPage,
}) {
  if (textLength <= 0) return 0;
  final measured = measuredPages.isEmpty
      ? fallbackCharactersPerPage
      : (measuredPages.last.end / measuredPages.length).round();
  return math.max(1, (textLength / math.max(1, measured)).ceil());
}

int estimatedPageForOffset(
  int offset, {
  required int textLength,
  required int totalPages,
}) {
  if (textLength <= 1 || totalPages <= 1) return 1;
  return 1 + ((offset.clamp(0, textLength - 1) / (textLength - 1)) * (totalPages - 1)).round();
}

int estimatedOffsetForPage(
  int page, {
  required int textLength,
  required int totalPages,
}) {
  if (textLength <= 1 || totalPages <= 1) return 0;
  return (((page.clamp(1, totalPages) - 1) / (totalPages - 1)) * (textLength - 1)).round();
}
```

- [ ] **Step 4: Add a failing bounded-window test**

```dart
test('paginates a bounded window around a source offset', () async {
  final text = List.generate(300, (index) => '줄 $index 가나다라\n').join();
  final pages = await paginateTextWindow(
    text: text,
    startOffset: text.length ~/ 2,
    size: const Size(240, 180),
    style: const TextStyle(fontSize: 18),
    maxPages: 12,
  );

  expect(pages, isNotEmpty);
  expect(pages.length, lessThanOrEqualTo(12));
  expect(pages.first.start, greaterThan(0));
  expect(pages.last.end, lessThanOrEqualTo(text.length));
});
```

- [ ] **Step 5: Run the window test and verify RED**

Run: `flutter test test/text_paginator_test.dart --reporter expanded`

Expected: compile failure because `paginateTextWindow` does not exist.

- [ ] **Step 6: Implement bounded window pagination**

Add `paginateTextWindow` beside `paginateText`. Clamp `startOffset`, avoid a split surrogate pair, align to a newline only when one exists within 4,096 characters, call `_nextPageEnd` for at most `maxPages`, and yield once after each eight pages. Reuse the existing layout and cancellation functions; do not duplicate page-boundary logic.

- [ ] **Step 7: Verify and commit Task 1**

Run: `dart format lib/text_paginator.dart test/text_paginator_test.dart && flutter test test/text_paginator_test.dart --reporter expanded`

Expected: all paginator tests pass.

Commit: `git commit -am "feat: add provisional page windows"`

---

### Task 2: Immediate reader jump and page-number-only UI

**Files:**
- Modify: `lib/reader_screen.dart`
- Test: `test/reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 1 mapping functions and `paginateTextWindow`.
- Produces: a generation-guarded provisional page window used only until `_paginationComplete`.

- [ ] **Step 1: Write the failing pending-pagination jump test**

Build a page-mode `ReaderView` with a paginator whose future remains pending and which emits a small exact prefix. Open the drawer, tap `위치 이동`, enter a page beyond the prefix, and tap `이동`. Assert before completing the paginator that:

```dart
expect(completion.isCompleted, isFalse);
expect(store.document('/book.txt').offset, greaterThan(0));
expect(find.text(RegExp(r'^\d+페이지$')), findsWidgets);
expect(find.textContaining('%'), findsNothing);
```

- [ ] **Step 2: Run the widget test and verify RED**

Run: `flutter test test/reader_screen_test.dart --plain-name "계산 중에도 페이지 번호로 즉시 이동한다" --reporter expanded`

Expected: the dialog never opens and the test finds the existing `페이지를 계산하고 있습니다.` message.

- [ ] **Step 3: Add provisional window state and jump flow**

Keep the change inside `reader_screen.dart`:

```dart
class _PageWindow {
  const _PageWindow({required this.pages, required this.firstDisplayPage});
  final List<TextPage> pages;
  final int firstDisplayPage;
}
```

Store `_pageSize`, `_provisionalWindow`, and a window generation integer. The visible page list is `_provisionalWindow?.pages ?? _pages`. When the jump page is outside the available exact prefix, calculate a target source offset, paginate a bounded window beginning several estimated pages before it, locate the target inside that window, set `firstDisplayPage = requestedPage - localTargetIndex`, recreate the `PageController` at `localTargetIndex`, and persist the selected source offset. Ignore stale completions using both pagination and window generations.

When exact pagination completes, clear the window, recreate the controller at `pageForOffset(exactPages, _offset)`, and preserve `_offset`. Progressive prefix batches update `_pages` without replacing an active provisional window.

- [ ] **Step 4: Replace percentage labels with current page helpers**

Add getters that return exact page numbers when complete and provisional page numbers otherwise. Replace:

```dart
subtitle: Text('${(_progress * 100).toStringAsFixed(1)}% 읽음')
```

with:

```dart
subtitle: Text('현재 ${_currentPageNumber}페이지')
```

Replace the bottom-right percentage text with:

```dart
Text('${_currentPageNumber}페이지', ...)
```

The page jump dialog must use the exact or estimated total and must no longer gate on `_completePages`. In scroll mode, map the requested provisional page directly to a source offset and use the existing chunk jump. Make `_pageNumberForOffset` use the same exact-or-provisional helper so bookmarks are not blocked by background calculation.

- [ ] **Step 5: Add UI regression tests**

Add one scroll-mode test that opens the drawer and asserts `현재 \d+페이지`, and asserts the bottom overlay has `\d+페이지`. Both states must satisfy:

```dart
expect(find.textContaining('%'), findsNothing);
```

Complete the pending paginator in the immediate-jump test and assert the source offset remains at the selected location after exact adoption.

- [ ] **Step 6: Run focused tests and fix only observed failures**

Run: `dart format lib/reader_screen.dart test/reader_screen_test.dart && flutter test test/text_paginator_test.dart test/reader_screen_test.dart --reporter expanded`

Expected: all focused tests pass.

- [ ] **Step 7: Commit Task 2**

Commit: `git commit -am "fix: enable immediate page navigation"`

---

### Task 3: QA and release-build verification

**Files:**
- Modify only if a verification failure proves a defect.

**Interfaces:**
- Consumes: completed Tasks 1 and 2.
- Produces: verified Android release artifact; publishing is outside this request.

- [ ] **Step 1: Run formatting and static analysis**

Run: `dart format --output=none --set-exit-if-changed lib test && flutter analyze`

Expected: zero formatting changes and `No issues found!`.

- [ ] **Step 2: Run the full test suite once**

Run: `flutter test --reporter expanded`

Expected: all tests pass, including the existing 20 MB Korean UTF-8 QA test.

- [ ] **Step 3: Build and hash the release APK**

Run: `flutter build apk --release` and `Get-FileHash build/app/outputs/flutter-apk/app-release.apk -Algorithm SHA256`.

Expected: release APK exists and has a non-empty SHA-256 digest.

- [ ] **Step 4: Inspect final diff and worktree**

Run: `git diff --check && git status --short && git log --oneline -5`.

Expected: no whitespace errors and no uncommitted source changes.
