# Paragraph Indentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add persisted `없음 / 한 글자 / 두 글자` novel paragraph indentation that renders and paginates accurately while preserving every source-text offset.

**Architecture:** Keep the decoded document unchanged. A shared range formatter in `text_document.dart` inserts ideographic spaces for display and records their display offsets so pagination can map `TextPainter` positions back to source offsets. `ReaderSettings` stores an integer level, and both reader modes plus the paginator consume the same formatter.

**Tech Stack:** Dart 3.12, Flutter Material, `TextPainter`, existing JSON `AppStore`, Flutter unit and widget tests.

## Global Constraints

- Valid indentation values are exactly `0`, `1`, and `2`; missing or invalid persisted values restore `0`.
- A paragraph starts at source offset zero or immediately after `\n` when the next source character is not `\n`.
- Lines already starting with ASCII space, tab, or ideographic space receive no added indentation.
- Added indentation uses ideographic space `U+3000`.
- Source text, search results, bookmarks, excerpts, progress, and `TextPage` offsets remain unchanged.
- Display Settings remains draft-only until the sheet closes.
- Add no dependency and perform no unrelated refactor.

---

### Task 1: Persist the indentation level

**Files:**
- Modify: `lib/models.dart:48-146`
- Test: `test/app_store_test.dart:65-112`

**Interfaces:**
- Consumes: existing `ReaderSettings` JSON and `copyWith` conventions.
- Produces: `ReaderSettings.paragraphIndent` as an `int` whose valid values are `0`, `1`, and `2`.

- [ ] **Step 1: Write the failing model test**

Add this test to `test/app_store_test.dart`:

```dart
test('persists paragraph indentation and defaults invalid values to none', () {
  const settings = ReaderSettings(paragraphIndent: 2);

  expect(settings.toJson()['paragraphIndent'], 2);
  expect(
    ReaderSettings.fromJson(settings.toJson()).paragraphIndent,
    2,
  );
  expect(ReaderSettings.fromJson(const {}).paragraphIndent, 0);
  for (final invalid in [-1, 1.5, 3]) {
    expect(
      ReaderSettings.fromJson({'paragraphIndent': invalid}).paragraphIndent,
      0,
    );
  }
  expect(settings.copyWith(fontSize: 24).paragraphIndent, 2);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```powershell
flutter test test/app_store_test.dart --no-pub --name "persists paragraph indentation and defaults invalid values to none"
```

Expected: compilation fails because `paragraphIndent` does not exist.

- [ ] **Step 3: Add the minimal settings field and JSON validation**

Add `this.paragraphIndent = 0` after `horizontalPadding` in the constructor,
change the constructor terminator from `});` to the assertion below, and add
the field beside the other typography fields:

```dart
this.paragraphIndent = 0,
}) : assert(paragraphIndent >= 0 && paragraphIndent <= 2);

final int paragraphIndent;
```

Add the named parameter and forwarded value to `copyWith`:

```dart
int? paragraphIndent,

paragraphIndent: paragraphIndent ?? this.paragraphIndent,
```

Add the serialized entry to `toJson`:

```dart
'paragraphIndent': paragraphIndent,
```

Add this private parser above `ReaderSettings`, then use it in `fromJson`:

```dart
int _paragraphIndentFromJson(Object? value) =>
    value is int && value >= 0 && value <= 2 ? value : 0;

paragraphIndent: _paragraphIndentFromJson(json['paragraphIndent']),
```

- [ ] **Step 4: Run the model tests**

Run:

```powershell
flutter test test/app_store_test.dart --no-pub
```

Expected: all `app_store_test.dart` tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/models.dart test/app_store_test.dart
git commit -m "feat: persist paragraph indentation"
```

---

### Task 2: Format source ranges without losing offsets

**Files:**
- Modify: `lib/text_document.dart:18-36,120-151`
- Test: `test/text_document_test.dart`

**Interfaces:**
- Consumes: normalized LF source strings and absolute `[start, end)` ranges.
- Produces: `IndentedText formatParagraphIndentation(String source, {required int start, required int end, required int paragraphIndent})` and `IndentedText.sourceOffsetAt(int displayOffset)`.

- [ ] **Step 1: Write failing formatting and mapping tests**

Add these tests to `test/text_document_test.dart`:

```dart
test('formats novel paragraphs without doubling existing indentation', () {
  const source = '첫 문단\n\n 둘째\n\t셋째\n　넷째\n마지막';

  final one = formatParagraphIndentation(
    source,
    start: 0,
    end: source.length,
    paragraphIndent: 1,
  );
  final two = formatParagraphIndentation(
    source,
    start: 0,
    end: source.length,
    paragraphIndent: 2,
  );

  expect(one.text, '　첫 문단\n\n 둘째\n\t셋째\n　넷째\n　마지막');
  expect(two.text, '　　첫 문단\n\n 둘째\n\t셋째\n　넷째\n　　마지막');
  final displayOffset = two.text.indexOf('마지막');
  expect(two.sourceOffsetAt(displayOffset), source.indexOf('마지막'));
  expect(two.sourceOffsetAt(displayOffset + 3), source.length);
});

test('does not indent a range that begins mid-paragraph', () {
  const source = '앞문장 계속\n새 문단';
  final start = source.indexOf('문장');

  final formatted = formatParagraphIndentation(
    source,
    start: start,
    end: source.length,
    paragraphIndent: 1,
  );

  expect(formatted.text, '문장 계속\n　새 문단');
  expect(formatted.sourceOffsetAt(0), start);
  expect(formatted.sourceOffsetAt(formatted.text.length), source.length);
});

test('zero indentation returns the unmodified source range', () {
  const source = '앞\n뒤';
  final formatted = formatParagraphIndentation(
    source,
    start: 2,
    end: source.length,
    paragraphIndent: 0,
  );

  expect(formatted.text, '뒤');
  expect(formatted.sourceOffsetAt(1), source.length);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```powershell
flutter test test/text_document_test.dart --no-pub --name "(formats novel paragraphs|does not indent a range|zero indentation)"
```

Expected: compilation fails because `formatParagraphIndentation` is undefined.

- [ ] **Step 3: Add the shared formatter**

Add this code to `lib/text_document.dart` after `TextChunk`:

```dart
class IndentedText {
  const IndentedText({
    required this.text,
    required this.sourceStart,
    required this.sourceEnd,
    required List<int> insertedOffsets,
  }) : _insertedOffsets = insertedOffsets;

  final String text;
  final int sourceStart;
  final int sourceEnd;
  final List<int> _insertedOffsets;

  int sourceOffsetAt(int displayOffset) {
    final safeOffset = displayOffset.clamp(0, text.length).toInt();
    var insertedBefore = 0;
    for (final offset in _insertedOffsets) {
      if (offset >= safeOffset) break;
      insertedBefore++;
    }
    return (sourceStart + safeOffset - insertedBefore)
        .clamp(sourceStart, sourceEnd)
        .toInt();
  }
}

IndentedText formatParagraphIndentation(
  String source, {
  required int start,
  required int end,
  required int paragraphIndent,
}) {
  RangeError.checkValidRange(start, end, source.length);
  assert(paragraphIndent >= 0 && paragraphIndent <= 2);
  if (paragraphIndent == 0) {
    return IndentedText(
      text: source.substring(start, end),
      sourceStart: start,
      sourceEnd: end,
      insertedOffsets: const [],
    );
  }

  final buffer = StringBuffer();
  final insertedOffsets = <int>[];
  for (var index = start; index < end; index++) {
    final codeUnit = source.codeUnitAt(index);
    final paragraphStart =
        index == 0 || source.codeUnitAt(index - 1) == 0x0a;
    final alreadyIndented =
        codeUnit == 0x20 || codeUnit == 0x09 || codeUnit == 0x3000;
    if (paragraphStart && codeUnit != 0x0a && !alreadyIndented) {
      for (var count = 0; count < paragraphIndent; count++) {
        insertedOffsets.add(buffer.length);
        buffer.writeCharCode(0x3000);
      }
    }
    buffer.writeCharCode(codeUnit);
  }
  return IndentedText(
    text: buffer.toString(),
    sourceStart: start,
    sourceEnd: end,
    insertedOffsets: insertedOffsets,
  );
}
```

- [ ] **Step 4: Run all text document tests**

Run:

```powershell
flutter test test/text_document_test.dart --no-pub
```

Expected: all `text_document_test.dart` tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/text_document.dart test/text_document_test.dart
git commit -m "feat: format paragraph indentation"
```

---

### Task 3: Measure indented text while returning source page offsets

**Files:**
- Modify: `lib/text_paginator.dart:1-210`
- Test: `test/text_paginator_test.dart`

**Interfaces:**
- Consumes: `formatParagraphIndentation` and `IndentedText.sourceOffsetAt` from Task 2.
- Produces: optional `int paragraphIndent = 0` parameters on `paginateText` and `paginateTextWindow`; all `TextPage` values remain source ranges.

- [ ] **Step 1: Write a failing pagination regression test**

Add this test to `test/text_paginator_test.dart`:

```dart
test('paragraph indentation changes layout but preserves source ranges', () async {
  final text = List.filled(20, '가나다라\n').join();
  const size = Size(80, 40);
  const style = TextStyle(fontSize: 20, height: 1);

  final plain = await paginateText(text: text, size: size, style: style);
  final indented = await paginateText(
    text: text,
    size: size,
    style: style,
    paragraphIndent: 2,
  );

  expect(indented.length, greaterThan(plain.length));
  expect(indented.first.start, 0);
  expect(indented.last.end, text.length);
  for (var index = 1; index < indented.length; index++) {
    expect(indented[index - 1].end, indented[index].start);
  }
  expect(
    indented.map((page) => text.substring(page.start, page.end)).join(),
    text,
  );
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```powershell
flutter test test/text_paginator_test.dart --no-pub --name "paragraph indentation changes layout but preserves source ranges"
```

Expected: compilation fails because `paragraphIndent` is not a paginator parameter.

- [ ] **Step 3: Thread indentation through both paginator entry points**

Import the formatter:

```dart
import 'text_document.dart';
```

Add this optional parameter immediately after `required TextStyle style` in
both `paginateText` and `paginateTextWindow`:

```dart
int paragraphIndent = 0,
```

Add this argument after `style` in both `_nextPageEnd` calls:

```dart
paragraphIndent,
```

Replace `_nextPageEnd` with the complete implementation below:

```dart
int? _nextPageEnd(
  String text,
  int start,
  Size size,
  TextStyle style,
  int paragraphIndent,
  int probeLength,
  TextLayoutCallback? onLayout,
  bool Function()? isCancelled,
) {
  var candidateEnd = math.min(start + probeLength, text.length);
  late TextPainter painter;
  late IndentedText formatted;
  while (true) {
    formatted = formatParagraphIndentation(
      text,
      start: start,
      end: candidateEnd,
      paragraphIndent: paragraphIndent,
    );
    onLayout?.call(candidateEnd - start);
    painter = _layout(formatted.text, size.width, style);
    if (isCancelled?.call() == true) {
      painter.dispose();
      return null;
    }
    if (painter.height > size.height || candidateEnd == text.length) break;
    painter.dispose();
    candidateEnd = math.min(start + (candidateEnd - start) * 2, text.length);
  }

  if (painter.height <= size.height) {
    painter.dispose();
    return candidateEnd;
  }

  final displayOffset = painter
      .getPositionForOffset(Offset(size.width, math.max(0, size.height - .1)))
      .offset
      .clamp(1, formatted.text.length)
      .toInt();
  painter.dispose();

  var end = formatted.sourceOffsetAt(displayOffset);
  if (_splitsSurrogatePair(text, end)) {
    end = end - start > 1 ? end - 1 : end + 1;
  }
  if (end < text.length && text.codeUnitAt(end) == 0x0a) end++;
  return end.clamp(start + 1, text.length);
}
```

Reduce `_layout` to layout an already formatted string without invoking
`onLayout`:

```dart
TextPainter _layout(String text, double width, TextStyle style) {
  return TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: width);
}
```

- [ ] **Step 4: Run all paginator tests**

Run:

```powershell
flutter test test/text_paginator_test.dart --no-pub
```

Expected: all paginator tests pass, including existing probe-count and
cancellation tests.

- [ ] **Step 5: Commit**

```powershell
git add lib/text_paginator.dart test/text_paginator_test.dart
git commit -m "feat: paginate indented paragraphs"
```

---

### Task 4: Add Display Settings controls and render both reader modes

**Files:**
- Modify: `lib/reader_screen.dart:21-40,289-294,430-506,540-600,844-869,1050-1457`
- Test: `test/reader_screen_test.dart`

**Interfaces:**
- Consumes: `ReaderSettings.paragraphIndent`, `formatParagraphIndentation`, and paginator parameters from Tasks 1-3.
- Produces: choice-chip keys `paragraph-indent-none`, `paragraph-indent-one`, and `paragraph-indent-two`; reader and cache behavior keyed by the saved level.

- [ ] **Step 1: Write failing cache, rendering, and settings tests**

Add these tests near the existing settings tests in
`test/reader_screen_test.dart`:

```dart
testWidgets('문단 들여쓰기별 페이지 캐시와 페이지 본문을 분리한다', (tester) async {
  const text = '첫 문단\n둘째 문단';
  final cache = _MemoryPageIndexCache();

  Future<void> pumpIndent(int paragraphIndent) async {
    final store = _MemoryStore()
      ..updateSettings(
        ReaderSettings(
          mode: ReadingMode.page,
          paragraphIndent: paragraphIndent,
        ),
      );
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderView(
          key: ValueKey(paragraphIndent),
          path: '/book.txt',
          title: 'book.txt',
          text: text,
          encoding: TextEncoding.utf8,
          store: store,
          pageIndexCache: cache,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  await pumpIndent(0);
  await pumpIndent(2);

  expect(cache.loadSignatures.toSet(), hasLength(2));
  expect(
    tester.widget<SelectableText>(find.byType(SelectableText)).data,
    '　　첫 문단\n　　둘째 문단',
  );
});

testWidgets('표시 설정에서 문단 들여쓰기를 닫을 때 적용한다', (tester) async {
  final store = _MemoryStore();
  await _pumpReader(tester, store, '첫 문단\n둘째 문단');
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.tap(find.text('표시 설정'));
  await tester.pumpAndSettle();

  await tester.ensureVisible(find.byKey(const Key('paragraph-indent-two')));
  expect(
    tester
        .widget<ChoiceChip>(
          find.byKey(const Key('paragraph-indent-none')),
        )
        .selected,
    isTrue,
  );
  await tester.tap(find.byKey(const Key('paragraph-indent-two')));
  expect(store.data.settings.paragraphIndent, 0);

  await _dismissSettings(tester);

  expect(store.data.settings.paragraphIndent, 2);
  expect(
    tester.widget<SelectableText>(find.byType(SelectableText)).data,
    '　　첫 문단\n　　둘째 문단',
  );
});
```

- [ ] **Step 2: Update injected paginator callbacks, then run the tests RED**

The reader paginator typedefs will gain a required named parameter. In every
custom `paginator:` and `windowPaginator:` closure in
`test/reader_screen_test.dart`, insert this line immediately after
`required style,`:

```dart
required paragraphIndent,
```

For window callbacks, retain `required startOffset` and add
`required paragraphIndent` after `required style`.

Run:

```powershell
flutter test test/reader_screen_test.dart --no-pub --name "(문단 들여쓰기별 페이지 캐시|표시 설정에서 문단 들여쓰기)"
```

Expected: the new tests fail because the setting controls and reader
formatting are absent.

- [ ] **Step 3: Pass indentation to pagination and cache signatures**

Add this parameter after `required TextStyle style` in both `ReaderPaginator`
function type parameter lists:

```dart
required int paragraphIndent,
```

Insert this named argument immediately after `style: _textStyle` in the main
paginator call and both window paginator calls:

```dart
paragraphIndent: _settings.paragraphIndent,
```

Change the pagination cache algorithm value and add the setting entry:

```dart
'algorithm': 4,
'paragraphIndent': _settings.paragraphIndent,
```

- [ ] **Step 4: Render formatted source ranges in both modes**

Replace the scroll chunk text expression with:

```dart
final chunk = _chunks[index];
return SelectableText(
  formatParagraphIndentation(
    widget.text,
    start: chunk.start,
    end: chunk.end,
    paragraphIndent: _settings.paragraphIndent,
  ).text,
  style: _textStyle,
);
```

Replace the page `SelectableText` data expression with:

```dart
formatParagraphIndentation(
  widget.text,
  start: page.start,
  end: page.end,
  paragraphIndent: _settings.paragraphIndent,
).text
```

- [ ] **Step 5: Add the three draft-only choice chips**

Place this block after the horizontal-padding stepper and before color
templates in `_showSettings`:

```dart
const SizedBox(height: 8),
const Text('문단 들여쓰기'),
Wrap(
  spacing: 8,
  children: [
    ChoiceChip(
      key: const Key('paragraph-indent-none'),
      label: const Text('없음'),
      selected: draft.paragraphIndent == 0,
      onSelected: (_) => setSheetState(() {
        draft = draft.copyWith(paragraphIndent: 0);
      }),
    ),
    ChoiceChip(
      key: const Key('paragraph-indent-one'),
      label: const Text('한 글자'),
      selected: draft.paragraphIndent == 1,
      onSelected: (_) => setSheetState(() {
        draft = draft.copyWith(paragraphIndent: 1);
      }),
    ),
    ChoiceChip(
      key: const Key('paragraph-indent-two'),
      label: const Text('두 글자'),
      selected: draft.paragraphIndent == 2,
      onSelected: (_) => setSheetState(() {
        draft = draft.copyWith(paragraphIndent: 2);
      }),
    ),
  ],
),
```

- [ ] **Step 6: Run all reader tests**

Run:

```powershell
flutter test test/reader_screen_test.dart --no-pub
```

Expected: all reader tests pass, including the callback injection tests.

- [ ] **Step 7: Commit**

```powershell
git add lib/reader_screen.dart test/reader_screen_test.dart
git commit -m "feat: add paragraph indentation setting"
```

---

### Task 5: Verify the complete application

**Files:**
- No source changes expected.

**Interfaces:**
- Consumes: the complete feature from Tasks 1-4.
- Produces: verification evidence and a release-buildable Android APK.

- [ ] **Step 1: Check formatting and static analysis**

Run:

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
```

Expected: zero formatting changes and `No issues found!`.

- [ ] **Step 2: Run the full suite**

Run:

```powershell
flutter test --no-pub
```

Expected: all tests pass with zero failures.

- [ ] **Step 3: Build the release APK and inspect the diff**

Run:

```powershell
flutter build apk --release --no-pub
git diff --check
git status --short --branch
```

Expected: `app-release.apk` builds, `git diff --check` is silent, and the
working tree contains no uncommitted source or test changes.
