# Page Turn Line Overlap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repeat the previous page's final two visually wrapped lines at the top of the next page for swipe, tap, and automatic page turns.

**Architecture:** `TextPage` keeps non-overlapping logical `start`/`end` offsets and gains a `displayStart` used only for rendering. Both paginators calculate the next display start from `TextPainter` line boundaries, while the cache persists the extra offsets and the reader renders from them.

**Tech Stack:** Dart 3.12, Flutter 3.44, `TextPainter`, `flutter_test`

## Global Constraints

- Repeat two visually wrapped lines, not newline-delimited source lines.
- Apply the overlap to swipe, tap, and automatic page modes; scrolling remains unchanged.
- Logical page ranges remain continuous for page numbers, bookmarks, search, and saved progress.
- Repeated lines consume normal page height and must not clip the bottom.
- Small viewports reduce overlap as needed so every page advances.
- Add no dependency or user setting.

---

### Task 1: Calculate logical and display page ranges

**Files:**
- Modify: `lib/text_paginator.dart`
- Test: `test/text_paginator_test.dart`

**Interfaces:**
- Produces: `TextPage.displayStart`
- Produces: complete and window page lists whose logical ranges remain continuous

- [ ] **Step 1: Write failing paginator tests**

```dart
test('next page repeats two visually wrapped lines', () async {
  final text = List.filled(200, 'abcdefghij ').join();
  const size = Size(120, 120);
  const style = TextStyle(fontSize: 20, height: 1);
  final pages = await paginateText(text: text, size: size, style: style);

  expect(pages.length, greaterThan(2));
  for (var index = 1; index < pages.length; index++) {
    expect(pages[index - 1].end, pages[index].start);
  }
  final overlap = text.substring(pages[1].displayStart, pages[1].start);
  final painter = TextPainter(
    text: TextSpan(text: overlap, style: style),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: size.width);
  expect(painter.computeLineMetrics(), hasLength(2));
  painter.dispose();
});

test('window pages use the same two-line overlap', () async {
  final text = List.filled(200, 'abcdefghij ').join();
  const size = Size(120, 120);
  const style = TextStyle(fontSize: 20, height: 1);
  final pages = await paginateTextWindow(
    text: text,
    startOffset: 0,
    size: size,
    style: style,
  );

  final overlap = text.substring(pages[1].displayStart, pages[1].start);
  final painter = TextPainter(
    text: TextSpan(text: overlap, style: style),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: size.width);
  expect(painter.computeLineMetrics(), hasLength(2));
  painter.dispose();
});

test('small pages always advance', () async {
  final pages = await paginateText(
    text: List.filled(100, 'small page text ').join(),
    size: const Size(120, 40),
    style: const TextStyle(fontSize: 20, height: 1),
  );

  expect(pages, isNotEmpty);
  expect(pages.every((page) => page.end > page.start), isTrue);
});
```

- [ ] **Step 2: Verify RED**

Run:

```powershell
flutter test --no-pub test/text_paginator_test.dart
```

Expected: compile failure because `TextPage.displayStart` does not exist.

- [ ] **Step 3: Add display offsets to `TextPage`**

```dart
class TextPage {
  const TextPage({
    required this.start,
    required this.end,
    int? displayStart,
  }) : displayStart = displayStart ?? start;

  final int start;
  final int end;
  final int displayStart;
}
```

- [ ] **Step 4: Calculate the next page's display start**

Replace `_nextPageEnd` with a boundary result that accepts separate logical and
display starts:

```dart
typedef _PageBoundary = ({int end, int nextDisplayStart});

_PageBoundary? _nextPageBoundary(
  String text,
  int logicalStart,
  int displayStart,
  Size size,
  TextStyle style,
  int paragraphIndent,
  int probeLength,
  TextLayoutCallback? onLayout,
  bool Function()? isCancelled,
) {
  var candidateEnd = math.min(
    math.max(logicalStart + 1, displayStart + probeLength),
    text.length,
  );
  late TextPainter painter;
  late IndentedText formatted;
  while (true) {
    formatted = formatParagraphIndentation(
      text,
      start: displayStart,
      end: candidateEnd,
      paragraphIndent: paragraphIndent,
    );
    onLayout?.call(candidateEnd - displayStart);
    painter = _layout(formatted.text, size.width, style);
    if (isCancelled?.call() == true) {
      painter.dispose();
      return null;
    }
    if (painter.height > size.height || candidateEnd == text.length) break;
    painter.dispose();
    candidateEnd = math.min(
      displayStart + (candidateEnd - displayStart) * 2,
      text.length,
    );
  }

  if (painter.height <= size.height) {
    painter.dispose();
    return (end: candidateEnd, nextDisplayStart: candidateEnd);
  }

  final displayEnd = painter
      .getPositionForOffset(Offset(size.width, math.max(0, size.height - .1)))
      .offset
      .clamp(1, formatted.text.length)
      .toInt();
  var end = formatted.sourceOffsetAt(displayEnd);
  if (_splitsSurrogatePair(text, end)) {
    end = end - logicalStart > 1 ? end - 1 : end + 1;
  }
  if (end < text.length && text.codeUnitAt(end) == 0x0a) end++;
  end = end.clamp(logicalStart + 1, text.length);
  final nextDisplayStart = _overlapSourceStart(
    formatted,
    painter,
    displayEnd,
    logicalStart,
    end,
  );
  painter.dispose();
  return (end: end, nextDisplayStart: nextDisplayStart);
}

int _overlapSourceStart(
  IndentedText formatted,
  TextPainter painter,
  int displayEnd,
  int logicalStart,
  int end,
) {
  var position = displayEnd;
  for (var line = 0; line < 2; line++) {
    final boundary = painter.getLineBoundary(
      TextPosition(offset: position - 1),
    );
    if (boundary.start == 0) break;
    position = boundary.start;
  }
  return formatted
      .sourceOffsetAt(position)
      .clamp(logicalStart, end)
      .toInt();
}
```

Each pagination loop then records and advances both offsets:

```dart
pages.add(TextPage(
  start: logicalStart,
  end: boundary.end,
  displayStart: displayStart,
));
probeLength = ((boundary.end - displayStart) * 1.25).ceil();
logicalStart = boundary.end;
displayStart = boundary.nextDisplayStart;
```

- [ ] **Step 5: Verify GREEN and commit**

```powershell
flutter test --no-pub test/text_paginator_test.dart
git add lib/text_paginator.dart test/text_paginator_test.dart
git commit -m "feat: overlap page turn lines"
```

Expected: paginator tests pass.

---

### Task 2: Persist display starts in the page cache

**Files:**
- Modify: `lib/page_index_cache.dart`
- Test: `test/page_index_cache_test.dart`

**Interfaces:**
- Consumes: `TextPage.displayStart`
- Persists: JSON `displayStarts` alongside logical `starts`

- [ ] **Step 1: Write the failing cache test**

Save pages with explicit display starts and require the loaded pages to preserve
them:

```dart
const pages = [
  TextPage(start: 0, end: 100),
  TextPage(start: 100, end: 180, displayStart: 80),
];
expect(restored!.map((page) => page.displayStart), [0, 80]);
```

Add malformed records with a missing list, wrong length, a display start after
its logical start, and a display start before the previous logical page.

- [ ] **Step 2: Verify RED**

```powershell
flutter test --no-pub test/page_index_cache_test.dart
```

Expected: the restored second page has `displayStart == 100`.

- [ ] **Step 3: Save, load, and validate display starts**

Write `displayStarts: pages.map((page) => page.displayStart).toList()` in
`save`. In `load`, require the list and validate it with:

```dart
List<int>? _validatedDisplayStarts(Object? value, List<int> starts) {
  if (value is! List || value.length != starts.length) return null;
  final result = <int>[];
  for (var index = 0; index < starts.length; index++) {
    final displayStart = value[index];
    final minimum = index == 0 ? starts[index] : starts[index - 1];
    if (displayStart is! int ||
        displayStart < minimum ||
        displayStart > starts[index]) {
      return null;
    }
    result.add(displayStart);
  }
  return result;
}
```

Construct cached pages with:

```dart
TextPage(
  start: starts[index],
  end: index + 1 < starts.length ? starts[index + 1] : textLength,
  displayStart: displayStarts[index],
)
```

- [ ] **Step 4: Verify GREEN and commit**

```powershell
flutter test --no-pub test/page_index_cache_test.dart
git add lib/page_index_cache.dart test/page_index_cache_test.dart
git commit -m "feat: cache page display starts"
```

Expected: cache tests pass.

---

### Task 3: Render repeated lines without moving logical progress

**Files:**
- Modify: `lib/reader_screen.dart`
- Test: `test/reader_screen_test.dart`

**Interfaces:**
- Consumes: `TextPage.displayStart`
- Keeps: page changes saved at `TextPage.start`

- [ ] **Step 1: Write the failing reader test**

Inject a second page whose logical start is `5` and display start is `0`, turn
to it, and assert that rendering contains the repeated prefix while saved
progress remains `5`.

```dart
const pages = [
  TextPage(start: 0, end: 5),
  TextPage(start: 5, end: 11, displayStart: 0),
];
expect(store.document('/book.txt').offset, 5);
expect(find.text('firstsecond'), findsOneWidget);
```

- [ ] **Step 2: Verify RED**

```powershell
flutter test --no-pub test/reader_screen_test.dart --plain-name "page rendering repeats overlap without moving progress"
```

Expected: `firstsecond` is not found because rendering starts at logical
`page.start`.

- [ ] **Step 3: Render from the display start and invalidate old caches**

Change only the page text formatting range:

```dart
formatParagraphIndentation(
  widget.text,
  start: page.displayStart,
  end: page.end,
  paragraphIndent: _settings.paragraphIndent,
)
```

Change the pagination cache signature algorithm from `4` to `5`. Keep
`onPageChanged` and all navigation logic on `page.start`.

- [ ] **Step 4: Verify GREEN and commit**

```powershell
flutter test --no-pub test/reader_screen_test.dart --plain-name "page rendering repeats overlap without moving progress"
git add lib/reader_screen.dart test/reader_screen_test.dart
git commit -m "feat: render page turn overlap"
```

Expected: repeated text is visible and progress remains at the logical start.

---

### Task 4: Full verification

**Files:**
- Verify only

**Interfaces:**
- Confirms: pagination, cache, reader, formatting, and analysis remain valid

- [ ] **Step 1: Run focused suites**

```powershell
flutter test --no-pub test/text_paginator_test.dart test/page_index_cache_test.dart test/reader_screen_test.dart
```

Expected: all focused tests pass.

- [ ] **Step 2: Run repository verification**

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub
git diff --check
```

Expected: formatting unchanged, no analysis issues, all tests pass, and no
whitespace errors.
