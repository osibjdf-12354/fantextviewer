# Settings Auto-apply on Close Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the Display Settings apply button, apply changed settings once when the sheet closes, and compact the three numeric setting rows.

**Architecture:** Keep all controls bound to the existing local `draft`. After `showModalBottomSheet` returns, compare the draft and current settings through their stable JSON representation and call the existing `_applySettings` once only when they differ.

**Tech Stack:** Flutter, Dart, `flutter_test`, existing `ReaderSettings` JSON and `AppStore` persistence.

## Global Constraints

- Remove the `적용` button from Display Settings.
- While the sheet is open, all controls update only its draft and preview.
- Drag, back, and outside-tap dismissal apply the final draft once.
- Closing without changes performs no settings update, save, or pagination reset.
- Font size, font, line height, horizontal padding, colors, reading mode, page-turn direction, page display, and keep-awake follow the same close-to-apply rule.
- Deleting a saved font remains an immediate reset because its backing file is removed.
- Invalid RGB input keeps the last valid draft and existing validation feedback.
- Both `_SettingStepper` icon buttons use `VisualDensity.compact`; do not force a fixed row height.
- Add no dependency or unrelated refactor.

---

### Task 1: Apply the settings draft on sheet dismissal

**Files:**
- Modify: `lib/reader_screen.dart:1050-1472,1561-1613`
- Test: `test/reader_screen_test.dart`

**Interfaces:**
- Consumes: existing immutable `ReaderSettings`, `ReaderSettings.toJson()`, and `_applySettings(ReaderSettings)`.
- Produces: one settings application after modal dismissal when the final draft differs.

- [ ] **Step 1: Write failing dismissal and compact-density tests**

In the existing `표시 설정은 단계 버튼으로 값과 과거 소수값을 조절한다` test, assert values remain unchanged while the sheet is open, assert compact density, assert the apply button is absent, then dismiss through the back route:

```dart
await tester.tap(find.byKey(const Key('font-size-increase')));
await tester.tap(find.byKey(const Key('line-height-decrease')));
await tester.tap(find.byKey(const Key('horizontal-padding-increase')));

expect(store.data.settings.fontSize, 20.4);
expect(store.data.settings.lineHeight, 1.66);
expect(store.data.settings.horizontalPadding, 20.4);
expect(find.text('적용'), findsNothing);
for (final key in [
  'font-size-increase',
  'line-height-decrease',
  'horizontal-padding-increase',
]) {
  expect(
    tester.widget<IconButton>(find.byKey(Key(key))).visualDensity,
    VisualDensity.compact,
  );
}

await tester.binding.handlePopRoute();
await tester.pumpAndSettle();

expect(store.data.settings.fontSize, 21);
expect(store.data.settings.lineHeight, 1.6);
expect(store.data.settings.horizontalPadding, 21);
```

Add a no-change regression test. It counts both store notifications and paginator calls before and after opening and dismissing Display Settings:

```dart
testWidgets('closing unchanged display settings is a no-op', (tester) async {
  final store = _MemoryStore();
  var notifications = 0;
  var paginationCalls = 0;
  store.addListener(() => notifications++);
  await tester.pumpWidget(
    MaterialApp(
      home: ReaderView(
        path: '/book.txt',
        title: 'book.txt',
        text: '본문',
        encoding: TextEncoding.utf8,
        store: store,
        paginator:
            ({
              required text,
              required size,
              required style,
              onProgress,
              onBatch,
              onLayout,
              isCancelled,
            }) async {
              paginationCalls++;
              final pages = [TextPage(start: 0, end: text.length)];
              onBatch?.call(pages);
              return pages;
            },
      ),
    ),
  );
  await tester.pumpAndSettle();
  final callsBefore = paginationCalls;

  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.tap(find.text('표시 설정'));
  await tester.pumpAndSettle();
  expect(find.text('적용'), findsNothing);
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();

  expect(notifications, 0);
  expect(paginationCalls, callsBefore);
});
```

Update every existing Display Settings success path that taps `적용` to call this test helper instead:

```dart
Future<void> _dismissSettings(WidgetTester tester) async {
  expect(find.text('적용'), findsNothing);
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}
```

Use `_dismissSettings(tester)` after changing page display, reading mode/colors, tap mode/direction, steppers, and imported font. Dialog buttons named `삭제` are unrelated and remain unchanged.

- [ ] **Step 2: Run focused tests to verify RED**

Run:

```powershell
flutter test test/reader_screen_test.dart --no-pub --name "(표시 설정은 단계 버튼으로 값과 과거 소수값을 조절한다|closing unchanged display settings is a no-op|표시 설정에서 현재와 전체 페이지 표시를 선택하고 저장한다|표시 설정에서 로컬 글꼴을 가져와 미리보기와 본문에 적용한다)"
```

Expected failures:

- the apply button still exists;
- stepper changes are not committed by route dismissal;
- icon-button visual density is not compact.

- [ ] **Step 3: Keep the exact current settings as the initial draft**

In `_showSettings`, replace the rounded/clamped copy with the exact immutable settings object:

```dart
var draft = _settings;
```

This makes opening and closing an untouched sheet compare equal even when an older saved value has extra decimal precision. `_SettingStepper._next` already rounds and clamps the first actual button change.

- [ ] **Step 4: Apply once after the modal closes**

Leave every existing control callback draft-only. Immediately after the awaited `showModalBottomSheet<void>(...)` call, add:

```dart
if (!mounted ||
    jsonEncode(draft.toJson()) == jsonEncode(_settings.toJson())) {
  return;
}
_applySettings(draft);
```

`reader_screen.dart` already imports `dart:convert` for pagination cache keys, so no import or helper type is needed. A selected-font deletion that calls `_applySettings` inside the sheet updates `_settings`; the final comparison therefore avoids an unnecessary second application when the draft matches that reset.

- [ ] **Step 5: Remove the apply button and compact the steppers**

Delete this widget from the settings sheet:

```dart
SizedBox(
  width: double.infinity,
  child: FilledButton(
    onPressed: () {
      Navigator.pop(sheetContext);
      _applySettings(draft);
    },
    child: const Text('적용'),
  ),
),
```

Add the same native density to both `IconButton`s in `_SettingStepper`:

```dart
visualDensity: VisualDensity.compact,
```

Keep their keys, tooltips, disabled bounds, and `_next` math unchanged.

- [ ] **Step 6: Run focused tests to verify GREEN**

Run:

```powershell
dart format lib/reader_screen.dart test/reader_screen_test.dart
flutter test test/reader_screen_test.dart --no-pub --name "(표시 설정은 단계 버튼으로 값과 과거 소수값을 조절한다|closing unchanged display settings is a no-op|표시 설정에서 현재와 전체 페이지 표시를 선택하고 저장한다|햄버거 메뉴에서 읽기 모드와 RGB 배경색을 바꾼다|display settings persist tap mode and both direction helper|표시 설정에서 로컬 글꼴을 가져와 미리보기와 본문에 적용한다)"
```

Expected: all selected tests pass, draft values stay unchanged while open, dismissal applies them once, unchanged dismissal is a no-op, and the apply button is absent.

- [ ] **Step 7: Run full verification**

Run:

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --release --no-pub
git diff --check
git status --short
```

Expected: analysis has no issues, all tests pass, the release APK builds, diff check is clean, and only `lib/reader_screen.dart` plus `test/reader_screen_test.dart` are modified.

- [ ] **Step 8: Commit**

```powershell
git add -- lib/reader_screen.dart test/reader_screen_test.dart
git diff --cached --check
git commit -m "feat: apply display settings on close"
```

- [ ] **Step 9: Verify branch state**

Run:

```powershell
git status --short
git log --oneline -3
```

Expected: clean status with the implementation commit above the approved design and plan commits.
