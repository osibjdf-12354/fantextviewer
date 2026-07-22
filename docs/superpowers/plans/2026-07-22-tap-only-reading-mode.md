# Tap-only Reading Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an explicit tap-only paginated reading method while making swipe mode ignore taps and preserving scroll behavior.

**Architecture:** Keep the existing `ReadingMode.page` serialized value as swipe mode and add `ReadingMode.tap`. Reuse `PageTurnView` with one required `tapOnly` flag so each paginated reader accepts exactly one pointer navigation method while sharing pagination, restoration, and progress state.

**Tech Stack:** Flutter, Dart, `flutter_test`, existing JSON settings storage.

## Global Constraints

- Display Settings choices are exactly `세로 스크롤`, `스와이프`, and `탭`.
- Existing saved `page` values continue to mean swipe mode; missing values still default to scroll mode.
- Swipe mode ignores taps; tap mode ignores swipes; scroll mode performs no page tap navigation.
- Horizontal tap mode uses left half previous and right half next.
- Vertical and both tap modes use top half previous and bottom half next.
- When `둘 다` is selected, show `둘 다 모드에서는 탭 영역이 위/아래로 나뉩니다.` in small text.
- Long press remains available to `SelectableText`.
- Pagination, progress, search, bookmarks, page jump, saved restoration, and the 40-pixel page indicator inset remain unchanged.
- Add no dependency or unrelated refactor.

---

### Task 1: Persist the tap reading method

**Files:**
- Modify: `lib/models.dart:1`
- Test: `test/app_store_test.dart`

**Interfaces:**
- Produces: `ReadingMode.tap`, serialized as `"tap"` by the existing enum-name JSON path.
- Preserves: `ReadingMode.page`, serialized as `"page"`.

- [ ] **Step 1: Write the failing persistence test**

Add to `test/app_store_test.dart`:

```dart
test('persists tap mode without changing saved page mode', () {
  const tap = ReaderSettings(mode: ReadingMode.tap);

  expect(tap.toJson()['mode'], 'tap');
  expect(ReaderSettings.fromJson(tap.toJson()).mode, ReadingMode.tap);
  expect(
    ReaderSettings.fromJson(const {'mode': 'page'}).mode,
    ReadingMode.page,
  );
  expect(ReaderSettings.fromJson(const {}).mode, ReadingMode.scroll);
});
```

- [ ] **Step 2: Run the test to verify RED**

Run:

```powershell
flutter test test/app_store_test.dart --plain-name "persists tap mode without changing saved page mode"
```

Expected: compilation fails because `ReadingMode.tap` does not exist.

- [ ] **Step 3: Add the minimum enum value**

Change `lib/models.dart` to:

```dart
enum ReadingMode { scroll, page, tap }
```

Do not change the existing JSON implementation; it already stores enum names and defaults unknown/missing values to `scroll`.

- [ ] **Step 4: Run focused tests to verify GREEN**

Run:

```powershell
dart format lib/models.dart test/app_store_test.dart
flutter test test/app_store_test.dart
```

Expected: all `app_store_test.dart` tests pass.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/models.dart test/app_store_test.dart
git commit -m "feat: persist tap reading mode"
```

---

### Task 2: Make page input mutually exclusive

**Files:**
- Modify: `lib/page_turn_view.dart`
- Test: `test/page_turn_view_test.dart`

**Interfaces:**
- Consumes: `PageTurnDirection`.
- Produces: required `PageTurnView.tapOnly`; `false` enables swipe-only input and `true` enables tap-only input.

- [ ] **Step 1: Write failing input and tap-zone tests**

Extend `_pumpPager` in `test/page_turn_view_test.dart` with `bool tapOnly = false` and pass it to `PageTurnView`:

```dart
Future<void> _pumpPager(
  WidgetTester tester,
  ValueNotifier<int> page,
  PageTurnDirection direction, {
  bool tapOnly = false,
  SelectionChangedCallback? onSelectionChanged,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ValueListenableBuilder<int>(
        valueListenable: page,
        builder: (context, index, _) => PageTurnView(
          index: index,
          itemCount: 3,
          direction: direction,
          tapOnly: tapOnly,
          onPageChanged: (value) => page.value = value,
          itemBuilder: (context, itemIndex) => SelectableText(
            'page $itemIndex',
            key: ValueKey(itemIndex),
            onSelectionChanged: onSelectionChanged,
          ),
        ),
      ),
    ),
  );
}
```

Add these tests:

```dart
testWidgets('swipe-only mode ignores taps', (tester) async {
  final page = ValueNotifier(1);
  await _pumpPager(tester, page, PageTurnDirection.horizontal);
  final rect = tester.getRect(find.byType(PageTurnView));

  await tester.tapAt(Offset(rect.right - 20, rect.center.dy));
  await tester.pumpAndSettle();

  expect(page.value, 1);
});

testWidgets('horizontal tap-only mode uses left and right halves', (tester) async {
  final page = ValueNotifier(1);
  await _pumpPager(
    tester,
    page,
    PageTurnDirection.horizontal,
    tapOnly: true,
  );
  final rect = tester.getRect(find.byType(PageTurnView));

  await tester.tapAt(Offset(rect.left + 20, rect.center.dy));
  await tester.pumpAndSettle();
  expect(page.value, 0);

  await tester.tapAt(Offset(rect.right - 20, rect.center.dy));
  await tester.pumpAndSettle();
  expect(page.value, 1);
});

testWidgets('vertical and both tap-only modes use top and bottom halves', (
  tester,
) async {
  for (final direction in [
    PageTurnDirection.vertical,
    PageTurnDirection.both,
  ]) {
    final page = ValueNotifier(1);
    await _pumpPager(tester, page, direction, tapOnly: true);
    final rect = tester.getRect(find.byType(PageTurnView));

    await tester.tapAt(Offset(rect.center.dx, rect.top + 20));
    await tester.pumpAndSettle();
    expect(page.value, 0);

    await tester.tapAt(Offset(rect.center.dx, rect.bottom - 20));
    await tester.pumpAndSettle();
    expect(page.value, 1);
  }
});

testWidgets('tap-only mode ignores swipes', (tester) async {
  final page = ValueNotifier(1);
  await _pumpPager(
    tester,
    page,
    PageTurnDirection.horizontal,
    tapOnly: true,
  );

  await tester.drag(find.byType(PageTurnView), const Offset(-300, 0));
  await tester.pumpAndSettle();

  expect(page.value, 1);
});
```

Update the existing top/bottom tap test to pass `tapOnly: true` or replace it with the vertical/both test above.

- [ ] **Step 2: Run component tests to verify RED**

Run:

```powershell
flutter test test/page_turn_view_test.dart
```

Expected: compilation fails because `tapOnly` is not yet a `PageTurnView` parameter.

- [ ] **Step 3: Implement the minimum input gate and tap split**

Add to the constructor and fields in `lib/page_turn_view.dart`:

```dart
required this.tapOnly,

final bool tapOnly;
```

Include `oldWidget.tapOnly != widget.tapOnly` in `didUpdateWidget` interaction reset conditions.

At the start of `_handleMove`, after confirming the tracked pointer and before recording swipe velocity, return when `widget.tapOnly` is true. The existing up-handler distance check will prevent a drag from becoming a tap:

```dart
if (event.pointer != _pointer || _cancelled || widget.tapOnly) return;
```

Replace the tap branch in `_handleUp` with:

```dart
if (axis == null) {
  if (widget.tapOnly &&
      elapsed < kLongPressTimeout &&
      distance < kTouchSlop) {
    final horizontal = widget.direction == PageTurnDirection.horizontal;
    final pageDelta = horizontal
        ? (event.localPosition.dx < _size.width / 2 ? -1 : 1)
        : (event.localPosition.dy < _size.height / 2 ? -1 : 1);
    unawaited(_animateTurn(pageDelta, _tapAxis));
  }
  return;
}
```

This keeps long press untouched and keeps `both` on the existing vertical `_tapAxis`.

- [ ] **Step 4: Run component tests to verify GREEN**

Run:

```powershell
dart format lib/page_turn_view.dart test/page_turn_view_test.dart
flutter test test/page_turn_view_test.dart
```

Expected: all component tests pass, including selection, multi-touch, resize, bounds, swipe-only, and tap-only cases.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/page_turn_view.dart test/page_turn_view_test.dart
git commit -m "feat: separate swipe and tap page input"
```

---

### Task 3: Integrate the reading choices and helper text

**Files:**
- Modify: `lib/reader_screen.dart`
- Test: `test/reader_screen_test.dart`

**Interfaces:**
- Consumes: `ReadingMode.tap` and `PageTurnView.tapOnly`.
- Preserves: every paginated navigation and progress flow for both non-scroll modes.

- [ ] **Step 1: Write failing Display Settings tests**

Update the settings test to assert all three reading choices, select `탭`, select `둘 다`, and apply:

```dart
expect(find.text('세로 스크롤'), findsOneWidget);
expect(find.text('스와이프'), findsOneWidget);
expect(find.text('탭'), findsOneWidget);
expect(find.text('페이지 넘김'), findsNothing);

await tester.tap(find.text('탭'));
await tester.ensureVisible(find.byKey(const Key('page-turn-both')));
await tester.tap(find.byKey(const Key('page-turn-both')));
await tester.pump();
expect(
  find.text('둘 다 모드에서는 탭 영역이 위/아래로 나뉩니다.'),
  findsOneWidget,
);
await tester.ensureVisible(find.text('적용'));
await tester.tap(find.text('적용'));
await tester.pumpAndSettle();

expect(store.data.settings.mode, ReadingMode.tap);
expect(store.data.settings.pageTurnDirection, PageTurnDirection.both);
```

Also add an integration test that pumps `ReadingMode.tap`, verifies a drag does not update progress, then taps the configured next half and verifies progress advances. Keep the existing vertical swipe integration test as proof that saved `ReadingMode.page` remains swipe mode.

- [ ] **Step 2: Run reader tests to verify RED**

Run:

```powershell
flutter test test/reader_screen_test.dart --plain-name "햄버거 메뉴에서 읽기 모드와 RGB 배경색을 바꾼다"
flutter test test/reader_screen_test.dart --plain-name "display settings persist all page turn directions"
flutter test test/reader_screen_test.dart --plain-name "tap reading mode ignores swipes and advances by tap"
```

Expected: failures because `탭`, helper text, and tap-only integration are absent and `페이지 넘김` is still visible.

- [ ] **Step 3: Treat both non-scroll modes as paginated**

Add inside `_ReaderViewState`:

```dart
bool get _isPaged => _settings.mode != ReadingMode.scroll;
```

Use `_isPaged` for the page indicator inset, eager page calculation, large-file page restoration, and pending page-offset handling currently guarded by `ReadingMode.page`. Keep direct `ReadingMode.scroll` checks unchanged.

Pass the required input mode to `PageTurnView`:

```dart
tapOnly: _settings.mode == ReadingMode.tap,
```

- [ ] **Step 4: Add the third choice and conditional helper copy**

Rename the existing page chip label to `스와이프` and add:

```dart
ChoiceChip(
  key: const Key('reading-mode-tap'),
  label: const Text('탭'),
  selected: draft.mode == ReadingMode.tap,
  onSelected: (_) => setSheetState(() {
    draft = draft.copyWith(mode: ReadingMode.tap);
  }),
),
```

Immediately below the page-direction `Wrap`, conditionally add:

```dart
if (draft.pageTurnDirection == PageTurnDirection.both) ...[
  const SizedBox(height: 4),
  Text(
    '둘 다 모드에서는 탭 영역이 위/아래로 나뉩니다.',
    style: Theme.of(sheetContext).textTheme.bodySmall,
  ),
],
```

- [ ] **Step 5: Run focused and full verification**

Run:

```powershell
dart format lib/reader_screen.dart test/reader_screen_test.dart
flutter test test/app_store_test.dart test/page_turn_view_test.dart test/reader_screen_test.dart
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --release --no-pub
git diff --check
git status --short
```

Expected: formatting changes no files after the first run, analysis reports no issues, all tests pass, the release APK builds, diff check is clean, and status lists only the intended Task 3 files before commit.

- [ ] **Step 6: Commit**

```powershell
git add -- lib/reader_screen.dart test/reader_screen_test.dart
git diff --cached --check
git commit -m "feat: add tap-only reading mode"
```

- [ ] **Step 7: Verify the final branch**

Run:

```powershell
git status --short
git log --oneline -4
```

Expected: clean status and the three implementation commits above the approved design/plan commits.
