# Auto Page Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a runtime-only auto mode that advances pages vertically at a saved 1–60 second interval and pauses whenever the reader is not the active interaction surface.

**Architecture:** Persist only `autoPageIntervalSeconds` in `ReaderSettings`. Keep auto ON/OFF, pause state, and a single one-shot timer in `ReaderView`; while ON, derive an effective page mode and vertical direction without mutating saved reading settings. Reuse `PageTurnView`'s existing animation through its state and report pointer interaction so the reader can cancel and restart the timer.

**Tech Stack:** Dart, Flutter Material, `Timer`, Flutter widget tests, existing `AppStore`, `ReaderView`, and `PageTurnView`

## Global Constraints

- Auto mode defaults to OFF and is never persisted.
- The saved interval defaults to 5 seconds, allows 1–60 seconds, and changes in 1-second steps.
- Enabling auto mode temporarily uses swipe reading with vertical page turns; disabling it restores the latest saved reading mode and direction.
- Manual page turns keep auto mode ON and restart the full interval.
- Drawer, dialogs, bottom sheets, page interaction, and inactive app lifecycle states pause auto mode; resuming starts a full new interval.
- Reaching the real last page turns auto mode OFF and shows an explanation.
- Do not add a global service, dependency, countdown UI, repeat mode, or persisted auto ON/OFF state.

---

### Task 1: Persist the Auto Page Interval

**Files:**
- Modify: `lib/models.dart:52-157`
- Test: `test/app_store_test.dart:76-140`

**Interfaces:**
- Produces: `ReaderSettings.autoPageIntervalSeconds` as an `int` in the inclusive range 1–60, defaulting to 5.
- Produces: `ReaderSettings.copyWith({int? autoPageIntervalSeconds})`, JSON key `autoPageIntervalSeconds`.

- [ ] **Step 1: Write the failing persistence test**

Add this test beside the other `ReaderSettings` persistence tests:

```dart
test('persists auto page interval and defaults invalid values to five', () {
  const settings = ReaderSettings(autoPageIntervalSeconds: 12);

  expect(
    ReaderSettings.fromJson(settings.toJson()).autoPageIntervalSeconds,
    12,
  );
  expect(ReaderSettings.fromJson(const {}).autoPageIntervalSeconds, 5);
  for (final invalid in [0, 61, -1, '5']) {
    expect(
      ReaderSettings.fromJson({
        'autoPageIntervalSeconds': invalid,
      }).autoPageIntervalSeconds,
      5,
    );
  }
  expect(
    settings.copyWith(autoPageIntervalSeconds: 30).autoPageIntervalSeconds,
    30,
  );
});
```

- [ ] **Step 2: Run the test to verify RED**

Run:

```powershell
flutter test test/app_store_test.dart --plain-name "persists auto page interval and defaults invalid values to five" --no-pub
```

Expected: compile failure because `autoPageIntervalSeconds` does not exist.

- [ ] **Step 3: Add the minimal settings field and JSON validation**

In `lib/models.dart`, add:

```dart
int _autoPageIntervalFromJson(Object? value) =>
    value is int && value >= 1 && value <= 60 ? value : 5;
```

Add `this.autoPageIntervalSeconds = 5` after
`this.pageTurnDirection = PageTurnDirection.horizontal`, append the second
assert below, and add the field:

```dart
assert(autoPageIntervalSeconds >= 1 && autoPageIntervalSeconds <= 60)

final int autoPageIntervalSeconds;
```

Add `int? autoPageIntervalSeconds` to `copyWith`, then pass:

```dart
autoPageIntervalSeconds:
    autoPageIntervalSeconds ?? this.autoPageIntervalSeconds,
```

Add the JSON entry:

```dart
'autoPageIntervalSeconds': autoPageIntervalSeconds,
```

Restore it with:

```dart
autoPageIntervalSeconds: _autoPageIntervalFromJson(
  json['autoPageIntervalSeconds'],
),
```

- [ ] **Step 4: Run the focused model tests**

Run:

```powershell
dart format lib/models.dart test/app_store_test.dart
flutter test test/app_store_test.dart --no-pub
```

Expected: all `app_store_test.dart` tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/models.dart test/app_store_test.dart
git commit -m "feat: persist auto page interval"
```

---

### Task 2: Reuse PageTurnView for Programmatic Vertical Turns

**Files:**
- Modify: `lib/page_turn_view.dart:8-222`
- Test: `test/page_turn_view_test.dart:1-265`

**Interfaces:**
- Produces: public `PageTurnViewState`.
- Produces: `Future<bool> PageTurnViewState.animateNext(Axis axis)`.
- Produces: `void PageTurnViewState.cancelTurn()`.
- Produces: optional `PageTurnView.onInteractionStart` and `PageTurnView.onInteractionEnd` callbacks.

- [ ] **Step 1: Write failing animation and interaction tests**

Add:

```dart
import 'dart:async';

testWidgets('programmatic next page uses the requested vertical axis', (
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
          direction: PageTurnDirection.horizontal,
          onPageChanged: (value) => page.value = value,
          itemBuilder: (_, itemIndex) => Text('page $itemIndex'),
        ),
      ),
    ),
  );

  unawaited(key.currentState!.animateNext(Axis.vertical));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 90));
  final translations = tester
      .widgetList<Transform>(find.byType(Transform))
      .map((widget) => widget.transform.getTranslation());
  expect(
    translations.any(
      (translation) => translation.x == 0 && translation.y.abs() > 0,
    ),
    isTrue,
  );
  await tester.pump(const Duration(milliseconds: 100));
  expect(page.value, 1);
});

testWidgets('reports pointer interaction boundaries once', (tester) async {
  var starts = 0;
  var ends = 0;
  await tester.pumpWidget(
    MaterialApp(
      home: PageTurnView(
        index: 0,
        itemCount: 2,
        direction: PageTurnDirection.vertical,
        onInteractionStart: () => starts++,
        onInteractionEnd: () => ends++,
        onPageChanged: (_) {},
        itemBuilder: (_, index) => Text('page $index'),
      ),
    ),
  );

  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(PageTurnView)),
  );
  expect(starts, 1);
  await gesture.up();
  await tester.pump();
  expect(ends, 1);
});
```

- [ ] **Step 2: Run the tests to verify RED**

Run:

```powershell
flutter test test/page_turn_view_test.dart --plain-name "programmatic next page uses the requested vertical axis" --no-pub
```

Expected: compile failure because `PageTurnViewState` and `animateNext` do not exist.

- [ ] **Step 3: Expose the existing animation with no second animation path**

Add optional callbacks to `PageTurnView`:

```dart
this.onInteractionStart,
this.onInteractionEnd,

final VoidCallback? onInteractionStart;
final VoidCallback? onInteractionEnd;
```

Rename `_PageTurnViewState` to `PageTurnViewState` and return it from `createState`. Add:

```dart
Future<bool> animateNext(Axis axis) async {
  if (_progress.isAnimating || !_canTurn(1)) return false;
  await _animateTurn(1, axis);
  return mounted && widget.index < widget.itemCount;
}

void cancelTurn() => _resetInteraction();
```

At the start of `_handleDown`, notify before adding the pointer:

```dart
void _handleDown(PointerDownEvent event) {
  if (_activePointers.isEmpty) widget.onInteractionStart?.call();
  _activePointers.add(event.pointer);
}
```

Define:

```dart
void _notifyInteractionEnd() {
  if (_activePointers.isEmpty) widget.onInteractionEnd?.call();
}
```

Call `_notifyInteractionEnd()` immediately after
`_activePointers.remove(event.pointer)` in both `_handleUp` and
`_handleCancel`. Each handler removes a pointer once, so the callback fires
once when the final pointer leaves.

Keep `_animateTurn` as the only implementation of the 180ms transition.

- [ ] **Step 4: Run all page-turn tests**

Run:

```powershell
dart format lib/page_turn_view.dart test/page_turn_view_test.dart
flutter test test/page_turn_view_test.dart --no-pub
```

Expected: all page-turn tests pass.

- [ ] **Step 5: Commit**

```powershell
git add lib/page_turn_view.dart test/page_turn_view_test.dart
git commit -m "feat: expose automatic page turn"
```

---

### Task 3: Add Runtime Auto Mode and Drawer Control

**Files:**
- Modify: `lib/reader_screen.dart:225-920`
- Test: `test/reader_screen_test.dart`

**Interfaces:**
- Consumes: `ReaderSettings.autoPageIntervalSeconds`.
- Consumes: `PageTurnViewState.animateNext(Axis.vertical)`, `cancelTurn()`, and interaction callbacks.
- Produces: runtime-only `_autoMode`, effective reading mode/direction, a single one-shot timer, and drawer key `auto-mode-switch`.

- [ ] **Step 1: Write the failing core behavior test**

Add a three-page widget test using explicit page boundaries:

```dart
testWidgets('auto mode temporarily uses vertical pages and restores settings', (
  tester,
) async {
  const text = 'firstsecondthird';
  const pages = [
    TextPage(start: 0, end: 5),
    TextPage(start: 5, end: 11),
    TextPage(start: 11, end: 16),
  ];
  final store = _MemoryStore();

  await tester.pumpWidget(
    MaterialApp(
      home: ReaderView(
        path: '/book.txt',
        title: 'book.txt',
        text: text,
        encoding: TextEncoding.utf8,
        store: store,
        paginator: ({
          required text,
          required size,
          required style,
          required paragraphIndent,
          onProgress,
          onBatch,
          onLayout,
          isCancelled,
        }) async {
          onBatch?.call(pages);
          return pages;
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(ScrollablePositionedList), findsOneWidget);

  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  expect(
    tester.widget<SwitchListTile>(
      find.byKey(const Key('auto-mode-switch')),
    ).value,
    isFalse,
  );
  await tester.tap(find.byKey(const Key('auto-mode-switch')));
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();

  final pager = tester.widget<PageTurnView>(find.byType(PageTurnView));
  expect(pager.direction, PageTurnDirection.vertical);
  expect(pager.tapOnly, isFalse);
  expect(store.data.settings.mode, ReadingMode.scroll);

  await tester.pump(const Duration(seconds: 4));
  expect(store.document('/book.txt').offset, 0);
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(milliseconds: 180));
  expect(store.document('/book.txt').offset, 5);

  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('auto-mode-switch')));
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  expect(find.byType(ScrollablePositionedList), findsOneWidget);
});

Future<void> _pumpAutoReader(
  WidgetTester tester,
  _MemoryStore store, {
  int pageCount = 3,
}) async {
  const allText = 'firstsecondthird';
  const allPages = [
    TextPage(start: 0, end: 5),
    TextPage(start: 5, end: 11),
    TextPage(start: 11, end: 16),
  ];
  final pages = allPages.take(pageCount).toList();
  final text = allText.substring(0, pages.last.end);
  await tester.pumpWidget(
    MaterialApp(
      home: ReaderView(
        path: '/book.txt',
        title: 'book.txt',
        text: text,
        encoding: TextEncoding.utf8,
        store: store,
        paginator: ({
          required text,
          required size,
          required style,
          required paragraphIndent,
          onProgress,
          onBatch,
          onLayout,
          isCancelled,
        }) async {
          onBatch?.call(pages);
          return pages;
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _enableAutoMode(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('auto-mode-switch')));
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

testWidgets('manual page turn restarts the full auto interval', (tester) async {
  final store = _MemoryStore()
    ..updateSettings(const ReaderSettings(autoPageIntervalSeconds: 5));
  await _pumpAutoReader(tester, store);
  await _enableAutoMode(tester);

  await tester.pump(const Duration(seconds: 4));
  await tester.drag(find.byType(PageTurnView), const Offset(0, -300));
  await tester.pumpAndSettle();
  expect(store.document('/book.txt').offset, 5);

  await tester.pump(const Duration(seconds: 4));
  expect(store.document('/book.txt').offset, 5);
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(milliseconds: 180));
  expect(store.document('/book.txt').offset, 11);
});

testWidgets('auto mode waits until the next calculated page is available', (
  tester,
) async {
  const text = 'firstsecondthird';
  const pages = [
    TextPage(start: 0, end: 5),
    TextPage(start: 5, end: 11),
    TextPage(start: 11, end: 16),
  ];
  final store = _MemoryStore()
    ..updateSettings(const ReaderSettings(autoPageIntervalSeconds: 1));
  final completion = Completer<List<TextPage>>();
  PaginationBatchCallback? emitBatch;

  await tester.pumpWidget(
    MaterialApp(
      home: ReaderView(
        path: '/book.txt',
        title: 'book.txt',
        text: text,
        encoding: TextEncoding.utf8,
        store: store,
        paginator: ({
          required text,
          required size,
          required style,
          required paragraphIndent,
          onProgress,
          onBatch,
          onLayout,
          isCancelled,
        }) {
          emitBatch = onBatch;
          onBatch?.call([pages.first]);
          return completion.future;
        },
      ),
    ),
  );
  await tester.pump();
  await _enableAutoMode(tester);
  await tester.pump(const Duration(seconds: 2));
  expect(store.document('/book.txt').offset, 0);

  emitBatch?.call(pages.sublist(1));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(milliseconds: 180));
  expect(store.document('/book.txt').offset, 5);
  completion.complete(pages);
});
```

- [ ] **Step 2: Run the test to verify RED**

Run:

```powershell
flutter test test/reader_screen_test.dart --plain-name "auto mode temporarily uses vertical pages and restores settings" --no-pub
```

Expected: failure because `auto-mode-switch` is absent.

- [ ] **Step 3: Add effective settings and the one-shot timer**

Add state:

```dart
final _pageTurnKey = GlobalKey<PageTurnViewState>();
Timer? _autoTimer;
bool _autoMode = false;
int _autoPauseDepth = 0;
bool _appActive = true;

ReadingMode get _activeMode =>
    _autoMode ? ReadingMode.page : _settings.mode;
PageTurnDirection get _activePageTurnDirection => _autoMode
    ? PageTurnDirection.vertical
    : _settings.pageTurnDirection;
bool get _isPaged => _activeMode != ReadingMode.scroll;
```

Cancel `_autoTimer` in `dispose`. Replace reader-flow checks of `_settings.mode` with `_activeMode`, and pass `_activePageTurnDirection` plus `_activeMode == ReadingMode.tap` to `PageTurnView`.

Add the timer methods:

```dart
void _setAutoMode(bool enabled) {
  _autoTimer?.cancel();
  setState(() => _autoMode = enabled);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _restartAutoTimer();
  });
}

void _restartAutoTimer() {
  _autoTimer?.cancel();
  if (!_autoMode || _autoPauseDepth > 0 || !_appActive) return;
  final pages = _pageWindow?.pages ?? _pages;
  final index = _pageIndex;
  if (pages == null || index == null || index >= pages.length) return;
  if (pages[index].end == widget.text.length) {
    setState(() => _autoMode = false);
    _showMessage('마지막 페이지입니다. 오토모드를 종료했습니다.');
    return;
  }
  if (index + 1 >= pages.length) return;
  _autoTimer = Timer(
    Duration(seconds: _settings.autoPageIntervalSeconds),
    () => unawaited(_advanceAutoPage()),
  );
}

Future<void> _advanceAutoPage() async {
  if (!_autoMode || _autoPauseDepth > 0 || !_appActive) return;
  final moved =
      await _pageTurnKey.currentState?.animateNext(Axis.vertical) ?? false;
  if (!moved && mounted) _restartAutoTimer();
}

void _pauseAuto({bool cancelTurn = false}) {
  _autoPauseDepth++;
  _autoTimer?.cancel();
  if (cancelTurn) _pageTurnKey.currentState?.cancelTurn();
}

void _resumeAuto() {
  if (_autoPauseDepth > 0) _autoPauseDepth--;
  if (mounted && _autoPauseDepth == 0) _restartAutoTimer();
}
```

Give `PageTurnView` the key and callbacks:

```dart
key: _pageTurnKey,
onInteractionStart: _pauseAuto,
onInteractionEnd: _resumeAuto,
```

After every successful `onPageChanged`, call `_restartAutoTimer()`. At the end of `_setPaginationPages`, schedule `_restartAutoTimer` with `addPostFrameCallback` so delayed page calculation starts auto mode when the next page becomes available.

- [ ] **Step 4: Add the drawer switch and drawer pause**

Add to `Scaffold`:

```dart
onDrawerChanged: (open) {
  if (open) {
    _pauseAuto(cancelTurn: true);
  } else {
    _resumeAuto();
  }
},
```

Add after the drawer title and before navigation actions:

```dart
SwitchListTile(
  key: const Key('auto-mode-switch'),
  secondary: const Icon(Icons.play_circle_outline),
  title: const Text('오토모드'),
  value: _autoMode,
  onChanged: widget.text.isEmpty ? null : _setAutoMode,
),
```

- [ ] **Step 5: Run focused reader tests**

Run:

```powershell
dart format lib/reader_screen.dart test/reader_screen_test.dart
flutter test test/reader_screen_test.dart --plain-name "auto mode temporarily uses vertical pages and restores settings" --no-pub
flutter test test/reader_screen_test.dart --no-pub
```

Expected: focused test and all reader tests pass.

- [ ] **Step 6: Commit**

```powershell
git add lib/reader_screen.dart test/reader_screen_test.dart
git commit -m "feat: add automatic page mode"
```

---

### Task 4: Add Interval UI and Complete Pause Boundaries

**Files:**
- Modify: `lib/reader_screen.dart:300-400,943-1570`
- Test: `test/reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 3 `_pauseAuto`, `_resumeAuto`, `_restartAutoTimer`.
- Consumes: Task 3 test helpers `_pumpAutoReader` and `_enableAutoMode`.
- Produces: setting keys `auto-page-interval-decrease` and `auto-page-interval-increase`.
- Produces: help copy `세로 스크롤에서도 오토모드를 켜면 스와이프·상하 넘김으로 자동 전환됩니다.`

- [ ] **Step 1: Write failing settings and pause tests**

Add:

```dart
testWidgets('display settings save the auto interval and show its help', (
  tester,
) async {
  final store = _MemoryStore();
  await _pumpReader(tester, store, '본문');
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.tap(find.text('표시 설정'));
  await tester.pumpAndSettle();

  final increase = find.byKey(const Key('auto-page-interval-increase'));
  await tester.ensureVisible(increase);
  expect(
    find.text(
      '세로 스크롤에서도 오토모드를 켜면 스와이프·상하 넘김으로 자동 전환됩니다.',
    ),
    findsOneWidget,
  );
  await tester.tap(increase);
  await _dismissSettings(tester);
  expect(store.data.settings.autoPageIntervalSeconds, 6);
});

testWidgets('drawer pauses auto mode and closing restarts the full interval', (
  tester,
) async {
  final store = _MemoryStore()
    ..updateSettings(const ReaderSettings(autoPageIntervalSeconds: 1));
  await _pumpAutoReader(tester, store);
  await _enableAutoMode(tester);

  await tester.pump(const Duration(milliseconds: 700));
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 2));
  expect(store.document('/book.txt').offset, 0);

  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 700));
  expect(store.document('/book.txt').offset, 0);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 180));
  expect(store.document('/book.txt').offset, 5);
});
```

- [ ] **Step 2: Run the new tests to verify RED**

Run:

```powershell
flutter test test/reader_screen_test.dart --plain-name "display settings save the auto interval and show its help" --no-pub
```

Expected: failure because the interval controls do not exist.

- [ ] **Step 3: Add the interval stepper and help**

In the display settings column, after page-turn options, add:

```dart
const SizedBox(height: 12),
_SettingStepper(
  settingKey: 'auto-page-interval',
  label: '오토 페이지 간격 (초)',
  value: draft.autoPageIntervalSeconds.toDouble(),
  min: 1,
  max: 60,
  step: 1,
  fractionDigits: 0,
  onChanged: (value) => setSheetState(() {
    draft = draft.copyWith(autoPageIntervalSeconds: value.round());
  }),
),
Text(
  '세로 스크롤에서도 오토모드를 켜면 스와이프·상하 넘김으로 자동 전환됩니다.',
  style: Theme.of(sheetContext).textTheme.bodySmall,
),
```

The existing `_applySettings` pagination reset remains unchanged. Its delayed pagination result restarts auto mode with the newly saved interval.

- [ ] **Step 4: Pause all owned overlays and app lifecycle**

Change the state declaration:

```dart
class _ReaderViewState extends State<ReaderView>
    with WidgetsBindingObserver {
```

Call `WidgetsBinding.instance.addObserver(this);` immediately after
`super.initState()` and `WidgetsBinding.instance.removeObserver(this);`
before `super.dispose()`. Add:

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  final active = state == AppLifecycleState.resumed;
  if (_appActive == active) return;
  _appActive = active;
  if (active) {
    _restartAutoTimer();
  } else {
    _autoTimer?.cancel();
    _pageTurnKey.currentState?.cancelTurn();
  }
}
```

Change `_drawerItem` to accept `Future<void> Function()?`. Pass the async
methods directly, wrap the nullable synchronous file callback, and use an
async wrapper for app exit:

```dart
_drawerItem(
  Icons.folder_open,
  '파일 열기',
  widget.onOpenFile == null ? null : () async => widget.onOpenFile!(),
),
_drawerItem(Icons.pin_drop_outlined, '위치 이동', _showGoToDialog),
_drawerItem(Icons.search, '본문 검색', _showSearchDialog),
_drawerItem(Icons.bookmarks_outlined, '북마크', _showBookmarks),
_drawerItem(Icons.tune, '표시 설정', _showSettings),
_drawerItem(Icons.info_outline, '파일 정보', _showFileInfo),
_drawerItem(
  Icons.exit_to_app,
  '앱 종료',
  () async => SystemNavigator.pop(),
),
```

In `_drawerItem`, keep closing the drawer first, then replace the post-frame
action call with:

```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  if (mounted) unawaited(_runDrawerAction(action));
});
```

Add the shared pause boundary used by every drawer action:

```dart
Future<void> _runDrawerAction(Future<void> Function() action) async {
  _pauseAuto(cancelTurn: true);
  try {
    await action();
  } finally {
    _resumeAuto();
  }
}
```

This holds the pause through every awaited dialog or bottom sheet and also
covers file opening and app exit.

In `_addBookmark`, call `_restartAutoTimer()` after saving so the instant app-bar action also restarts the interval.

- [ ] **Step 5: Add lifecycle and last-page regression tests**

Add:

```dart
testWidgets('inactive lifecycle pauses auto mode until a full interval resumes', (
  tester,
) async {
  final store = _MemoryStore()
    ..updateSettings(const ReaderSettings(autoPageIntervalSeconds: 1));
  await _pumpAutoReader(tester, store);
  await _enableAutoMode(tester);

  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await tester.pump(const Duration(seconds: 2));
  expect(store.document('/book.txt').offset, 0);

  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pump(const Duration(milliseconds: 999));
  expect(store.document('/book.txt').offset, 0);
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump(const Duration(milliseconds: 180));
  expect(store.document('/book.txt').offset, 5);
});

testWidgets('reaching the last page turns auto mode off', (tester) async {
  final store = _MemoryStore()
    ..updateSettings(const ReaderSettings(autoPageIntervalSeconds: 1));
  await _pumpAutoReader(tester, store, pageCount: 2);
  await _enableAutoMode(tester);

  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(milliseconds: 180));
  expect(find.text('마지막 페이지입니다. 오토모드를 종료했습니다.'), findsOneWidget);

  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  expect(
    tester.widget<SwitchListTile>(
      find.byKey(const Key('auto-mode-switch')),
    ).value,
    isFalse,
  );
});
```

Add:

```dart
testWidgets('all drawer actions keep auto mode paused while open', (
  tester,
) async {
  final store = _MemoryStore()
    ..updateSettings(const ReaderSettings(autoPageIntervalSeconds: 1));
  await _pumpAutoReader(tester, store);
  await _enableAutoMode(tester);

  for (final label in [
    '위치 이동',
    '본문 검색',
    '북마크',
    '표시 설정',
    '파일 정보',
  ]) {
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    expect(store.document('/book.txt').offset, 0, reason: label);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }
});
```

- [ ] **Step 6: Run all focused tests**

Run:

```powershell
dart format lib/reader_screen.dart test/reader_screen_test.dart
flutter test test/app_store_test.dart test/page_turn_view_test.dart test/reader_screen_test.dart --no-pub
```

Expected: all focused tests pass.

- [ ] **Step 7: Commit**

```powershell
git add lib/reader_screen.dart test/reader_screen_test.dart
git commit -m "feat: pause auto mode during reader actions"
```

---

### Task 5: Full Verification

**Files:**
- Verify only; no source changes expected.

**Interfaces:**
- Verifies all earlier task outputs together.

- [ ] **Step 1: Check formatting, analysis, tests, and whitespace**

Run:

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub
git diff --check
```

Expected: no formatting changes, no analyzer issues, all tests pass, and `git diff --check` reports nothing.

- [ ] **Step 2: Build the release APK**

Run:

```powershell
flutter build apk --release --no-pub
```

Expected: `build/app/outputs/flutter-apk/app-release.apk` is created successfully. A Kotlin built-in migration warning from existing plugins is allowed; compilation errors are not.

- [ ] **Step 3: Confirm the branch is clean**

Run:

```powershell
git status --short --branch
git log --oneline -6
```

Expected: no uncommitted source changes and the four feature commits appear above the design and plan commits.
