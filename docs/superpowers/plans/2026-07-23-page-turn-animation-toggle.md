# Page Turn Animation Toggle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a saved display setting, enabled by default, that makes swipe, tap, auto, and accessibility page turns immediate when disabled.

**Architecture:** Keep the existing `PageTurnView` and add one boolean input. The disabled path still recognizes the existing gestures but never updates the visual drag progress; it calls the existing page-change callback immediately when a turn is accepted.

**Tech Stack:** Flutter, Dart, `flutter_test`

## Global Constraints

- The setting label is `페이지 넘김 애니메이션`.
- The default value is enabled.
- Display-setting changes apply when the settings sheet closes.
- Disabled mode must not visually follow a drag.
- Existing gesture rejection, text selection, page overlap, and enabled animation behavior must remain unchanged.
- Add no dependencies or alternate pager implementation.

---

### Task 1: Immediate page turns in `PageTurnView`

**Files:**
- Modify: `lib/page_turn_view.dart`
- Test: `test/page_turn_view_test.dart`

**Interfaces:**
- Consumes: existing `index`, `itemCount`, `direction`, `tapOnly`, `onPageChanged`, and `animateNext(Axis)`
- Produces: `PageTurnView.animationEnabled` with a default value of `true`

- [ ] **Step 1: Write failing widget tests**

Add an `animationEnabled` argument to `_pumpPager`, pass it to `PageTurnView`, and add:

```dart
testWidgets('animation disabled keeps the page still and turns on release', (
  tester,
) async {
  final page = ValueNotifier(1);
  await _pumpPager(
    tester,
    page,
    PageTurnDirection.horizontal,
    animationEnabled: false,
  );
  final pager = find.byType(PageTurnView);
  final current = find.byKey(const ValueKey(1));
  final initialLeft = tester.getTopLeft(current).dx;

  final gesture = await tester.startGesture(tester.getCenter(pager));
  await gesture.moveBy(const Offset(-300, 0));
  await tester.pump();

  expect(tester.getTopLeft(current).dx, initialLeft);
  expect(page.value, 1);

  await gesture.up();
  await tester.pump();

  expect(page.value, 2);
});

testWidgets('animation disabled makes programmatic turns immediate', (
  tester,
) async {
  final key = GlobalKey<PageTurnViewState>();
  final page = ValueNotifier(0);
  addTearDown(page.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: ValueListenableBuilder<int>(
        valueListenable: page,
        builder: (context, index, _) => PageTurnView(
          key: key,
          index: index,
          itemCount: 3,
          direction: PageTurnDirection.vertical,
          animationEnabled: false,
          onPageChanged: (value) => page.value = value,
          itemBuilder: (_, itemIndex) => Text('page $itemIndex'),
        ),
      ),
    ),
  );

  final turn = key.currentState!.animateNext(Axis.vertical);
  await tester.pump();

  expect(await turn, isTrue);
  expect(page.value, 1);
});
```

Update the helper signature and constructor call:

```dart
Future<void> _pumpPager(
  WidgetTester tester,
  ValueNotifier<int> page,
  PageTurnDirection direction, {
  bool tapOnly = false,
  bool animationEnabled = true,
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
          animationEnabled: animationEnabled,
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

- [ ] **Step 2: Run the tests and verify RED**

Run:

```powershell
flutter test test/page_turn_view_test.dart --plain-name "animation disabled"
```

Expected: compilation fails because `PageTurnView` has no `animationEnabled` parameter.

- [ ] **Step 3: Implement the minimum disabled path**

In `PageTurnView`, add:

```dart
this.animationEnabled = true,
```

and:

```dart
final bool animationEnabled;
```

Include `oldWidget.animationEnabled != widget.animationEnabled` in `didUpdateWidget`.

In `_handleMove`, continue calculating `_dragProgress`, but before assigning `_progress.value` add:

```dart
if (!widget.animationEnabled) return;
```

In `_handleUp`, retain the drag value before resetting it:

```dart
final progress = widget.animationEnabled
    ? _progress.value
    : _dragProgress.clamp(-1, 1).toDouble();
```

Use `progress` for the moved check, fling direction check, and page delta:

```dart
final moved = progress.abs() >= .2;
final flung =
    axisVelocity != null &&
    axisVelocity.abs() >= 600 &&
    axisVelocity.sign == progress.sign;
if (!moved && !flung) {
  unawaited(_animateBack());
  return;
}
unawaited(_animateTurn(progress < 0 ? 1 : -1, axis));
```

At the start of `_animateTurn`, after `_canTurn` succeeds, add:

```dart
if (!widget.animationEnabled) {
  widget.onPageChanged(widget.index + pageDelta);
  return;
}
```

This shared path covers tap, swipe, auto mode, and accessibility actions.

- [ ] **Step 4: Run the component tests and verify GREEN**

Run:

```powershell
flutter test test/page_turn_view_test.dart
```

Expected: all `PageTurnView` tests pass.

- [ ] **Step 5: Commit**

```powershell
git add -- lib/page_turn_view.dart test/page_turn_view_test.dart
git commit -m "feat: support immediate page turns"
```

---

### Task 2: Persist and expose the display setting

**Files:**
- Modify: `lib/models.dart`
- Modify: `lib/reader_screen.dart`
- Test: `test/app_store_test.dart`
- Test: `test/reader_screen_test.dart`

**Interfaces:**
- Consumes: `PageTurnView.animationEnabled`
- Produces: `ReaderSettings.pageTurnAnimationEnabled`, JSON key `pageTurnAnimationEnabled`, and widget key `page-turn-animation-switch`

- [ ] **Step 1: Write the failing persistence test**

Add to `test/app_store_test.dart`:

```dart
test('persists page turn animation and defaults to enabled', () {
  const disabled = ReaderSettings(pageTurnAnimationEnabled: false);

  expect(disabled.toJson()['pageTurnAnimationEnabled'], isFalse);
  expect(
    ReaderSettings.fromJson(disabled.toJson()).pageTurnAnimationEnabled,
    isFalse,
  );
  expect(
    ReaderSettings.fromJson(const {}).pageTurnAnimationEnabled,
    isTrue,
  );
  expect(
    disabled.copyWith(fontSize: 24).pageTurnAnimationEnabled,
    isFalse,
  );
});
```

- [ ] **Step 2: Write the failing settings UI test**

Add to `test/reader_screen_test.dart`:

```dart
testWidgets('display settings save page turn animation', (tester) async {
  final store = _MemoryStore()
    ..updateSettings(const ReaderSettings(mode: ReadingMode.page));
  await _pumpReader(tester, store, _longText);
  await tester.pumpAndSettle();

  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.tap(find.text('표시 설정'));
  await tester.pumpAndSettle();

  final toggle = find.byKey(const Key('page-turn-animation-switch'));
  await tester.ensureVisible(toggle);
  expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
  await tester.tap(toggle);
  await _dismissSettings(tester);

  expect(store.data.settings.pageTurnAnimationEnabled, isFalse);
  expect(
    tester.widget<PageTurnView>(find.byType(PageTurnView)).animationEnabled,
    isFalse,
  );
});
```

- [ ] **Step 3: Run the tests and verify RED**

Run:

```powershell
flutter test test/app_store_test.dart --plain-name "persists page turn animation"
flutter test test/reader_screen_test.dart --plain-name "display settings save page turn animation"
```

Expected: compilation fails because the setting and widget property do not exist.

- [ ] **Step 4: Implement model persistence**

In `ReaderSettings`, add the constructor default and field:

```dart
this.pageTurnAnimationEnabled = true,
```

```dart
final bool pageTurnAnimationEnabled;
```

Add the optional parameter to `copyWith` and forward it:

```dart
bool? pageTurnAnimationEnabled,
```

```dart
pageTurnAnimationEnabled:
    pageTurnAnimationEnabled ?? this.pageTurnAnimationEnabled,
```

Add JSON output and input:

```dart
'pageTurnAnimationEnabled': pageTurnAnimationEnabled,
```

```dart
pageTurnAnimationEnabled:
    json['pageTurnAnimationEnabled'] as bool? ?? true,
```

- [ ] **Step 5: Wire the setting to the reader and settings sheet**

Pass the value in `_buildPageReader`:

```dart
animationEnabled: _settings.pageTurnAnimationEnabled,
```

Place this tile below the page-turn direction controls:

```dart
SwitchListTile(
  key: const Key('page-turn-animation-switch'),
  contentPadding: EdgeInsets.zero,
  title: const Text('페이지 넘김 애니메이션'),
  value: draft.pageTurnAnimationEnabled,
  onChanged: (value) => setSheetState(() {
    draft = draft.copyWith(pageTurnAnimationEnabled: value);
  }),
),
```

The existing sheet-close comparison and `_applySettings` call persist and apply the value; add no new save path.

- [ ] **Step 6: Run focused tests and verify GREEN**

Run:

```powershell
flutter test test/app_store_test.dart
flutter test test/reader_screen_test.dart --plain-name "display settings save page turn animation"
flutter test test/page_turn_view_test.dart
```

Expected: all focused tests pass.

- [ ] **Step 7: Run full verification**

Run:

```powershell
flutter test
flutter analyze
git diff --check
```

Expected: all tests pass, analysis reports no issues, and the diff check is empty.

- [ ] **Step 8: Commit**

```powershell
git add -- lib/models.dart lib/reader_screen.dart test/app_store_test.dart test/reader_screen_test.dart
git commit -m "feat: add page turn animation setting"
```
