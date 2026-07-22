# Page Turn Interactions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add selectable horizontal, vertical, and two-axis page turns with top/bottom tap navigation, smooth high-refresh animation, correct newline page boundaries, and an unobscured bottom text area.

**Architecture:** Persist a `PageTurnDirection` in `ReaderSettings`, replace the horizontal-only `PageView` with a controlled `PageTurnView` that owns only gesture/animation state, and keep document offsets and page indexes in `ReaderView`. Reuse the existing paginator and settings flow, changing only its page-boundary rule and the page-mode content height.

**Tech Stack:** Flutter 3.44, Dart 3.12, `flutter_test`, Android Kotlin platform glue, existing JSON settings and paginator

## Global Constraints

- The three settings are `좌우 넘김`, `상하 넘김`, and `둘 다`.
- Missing saved values and new installs default to horizontal turns.
- Swipe left/up means next; swipe right/down means previous.
- Top-half tap means previous; bottom-half tap means next.
- Long press must remain available to `SelectableText`.
- Page-mode text reserves exactly 40 logical pixels at the bottom; scroll mode is unchanged.
- A boundary newline moves to the previous page, but additional consecutive newlines remain visible.
- Use vsync animation and native Android refresh preference; add no Flutter dependency.
- Search, bookmark, page jump, saved-position restoration, and progressive pagination semantics stay unchanged.

---

### Task 1: Persist the page-turn direction

**Files:**
- Modify: `lib/models.dart:1-132`
- Test: `test/app_store_test.dart:75-86`

**Interfaces:**
- Consumes: existing `ReaderSettings` constructor, `copyWith`, `toJson`, and `fromJson`.
- Produces: `PageTurnDirection` and non-nullable `ReaderSettings.pageTurnDirection`.

- [ ] **Step 1: Write the failing model test**

Add this beside the page-indicator persistence test:

```dart
test('persists page turn direction and defaults to horizontal', () {
  const settings = ReaderSettings(
    pageTurnDirection: PageTurnDirection.both,
  );

  expect(settings.toJson()['pageTurnDirection'], 'both');
  expect(
    ReaderSettings.fromJson(settings.toJson()).pageTurnDirection,
    PageTurnDirection.both,
  );
  expect(
    ReaderSettings.fromJson(const {}).pageTurnDirection,
    PageTurnDirection.horizontal,
  );
  expect(
    settings.copyWith(fontSize: 24).pageTurnDirection,
    PageTurnDirection.both,
  );
});
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
flutter test test/app_store_test.dart --plain-name "persists page turn direction and defaults to horizontal"
```

Expected: compilation fails because `PageTurnDirection` and `pageTurnDirection` do not exist.

- [ ] **Step 3: Add the minimal enum and model mapping**

Add the enum beside `ReadingMode`:

```dart
enum PageTurnDirection { horizontal, vertical, both }
```

Thread this field through the existing `ReaderSettings` constructor and `copyWith`:

```dart
this.pageTurnDirection = PageTurnDirection.horizontal,

final PageTurnDirection pageTurnDirection;

ReaderSettings copyWith({
  ReadingMode? mode,
  RgbColor? background,
  RgbColor? foreground,
  Object? fontFileName = _unchangedFontFileName,
  double? fontSize,
  double? lineHeight,
  double? horizontalPadding,
  bool? keepAwake,
  bool? showTotalPages,
  PageTurnDirection? pageTurnDirection,
}) {
  return ReaderSettings(
    mode: mode ?? this.mode,
    background: background ?? this.background,
    foreground: foreground ?? this.foreground,
    fontFileName: identical(fontFileName, _unchangedFontFileName)
        ? this.fontFileName
        : fontFileName as String?,
    fontSize: fontSize ?? this.fontSize,
    lineHeight: lineHeight ?? this.lineHeight,
    horizontalPadding: horizontalPadding ?? this.horizontalPadding,
    keepAwake: keepAwake ?? this.keepAwake,
    showTotalPages: showTotalPages ?? this.showTotalPages,
    pageTurnDirection: pageTurnDirection ?? this.pageTurnDirection,
  );
}
```

Add the JSON key and tolerant enum restoration:

```dart
'pageTurnDirection': pageTurnDirection.name,
```

```dart
pageTurnDirection: PageTurnDirection.values.firstWhere(
  (direction) => direction.name == json['pageTurnDirection'],
  orElse: () => PageTurnDirection.horizontal,
),
```

- [ ] **Step 4: Format and verify GREEN**

Run:

```bash
dart format lib/models.dart test/app_store_test.dart
flutter test test/app_store_test.dart --plain-name "persists page turn direction and defaults to horizontal"
flutter test test/app_store_test.dart
```

Expected: the focused test and the complete store/model file pass.

- [ ] **Step 5: Commit the persistence slice**

```bash
git add lib/models.dart test/app_store_test.dart
git commit -m "feat: persist page turn direction"
```

---

### Task 2: Build the controlled two-axis page-turn view

**Files:**
- Create: `lib/page_turn_view.dart`
- Create: `test/page_turn_view_test.dart`

**Interfaces:**
- Consumes: `PageTurnDirection` from Task 1 and an `IndexedWidgetBuilder`.
- Produces: `PageTurnView(index, itemCount, direction, onPageChanged, itemBuilder)`.

- [ ] **Step 1: Write failing swipe tests**

Create `test/page_turn_view_test.dart` with these imports and tests:

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geulbom/models.dart';
import 'package:geulbom/page_turn_view.dart';

void main() {
testWidgets('horizontal mode turns only on horizontal drag', (tester) async {
  final page = ValueNotifier(1);
  await _pumpPager(tester, page, PageTurnDirection.horizontal);

  await tester.drag(find.byType(PageTurnView), const Offset(-300, 0));
  await tester.pumpAndSettle();
  expect(page.value, 2);

  await tester.drag(find.byType(PageTurnView), const Offset(0, -300));
  await tester.pumpAndSettle();
  expect(page.value, 2);
});

testWidgets('vertical mode turns on vertical drag', (tester) async {
  final page = ValueNotifier(1);
  await _pumpPager(tester, page, PageTurnDirection.vertical);

  await tester.drag(find.byType(PageTurnView), const Offset(0, -300));
  await tester.pumpAndSettle();

  expect(page.value, 2);
});

testWidgets('both mode follows the dominant drag axis', (tester) async {
  final page = ValueNotifier(1);
  await _pumpPager(tester, page, PageTurnDirection.both);

  await tester.drag(find.byType(PageTurnView), const Offset(300, 20));
  await tester.pumpAndSettle();
  expect(page.value, 0);

  await tester.drag(find.byType(PageTurnView), const Offset(20, -300));
  await tester.pumpAndSettle();
  expect(page.value, 1);
});
}
```

Use this helper at the end of the file:

```dart
Future<void> _pumpPager(
  WidgetTester tester,
  ValueNotifier<int> page,
  PageTurnDirection direction,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ValueListenableBuilder<int>(
        valueListenable: page,
        builder: (context, index, _) => PageTurnView(
          index: index,
          itemCount: 3,
          direction: direction,
          onPageChanged: (value) => page.value = value,
          itemBuilder: (context, itemIndex) => SelectableText(
            'page $itemIndex',
            key: ValueKey(itemIndex),
          ),
        ),
      ),
    ),
  );
}
```

- [ ] **Step 2: Run the swipe tests and verify RED**

Run:

```bash
flutter test test/page_turn_view_test.dart
```

Expected: compilation fails because `page_turn_view.dart` and `PageTurnView` do not exist.

- [ ] **Step 3: Add the minimal two-axis view**

Create `lib/page_turn_view.dart`:

```dart
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'models.dart';

class PageTurnView extends StatefulWidget {
  const PageTurnView({
    super.key,
    required this.index,
    required this.itemCount,
    required this.direction,
    required this.onPageChanged,
    required this.itemBuilder,
  });

  final int index;
  final int itemCount;
  final PageTurnDirection direction;
  final ValueChanged<int> onPageChanged;
  final IndexedWidgetBuilder itemBuilder;

  @override
  State<PageTurnView> createState() => _PageTurnViewState();
}

class _PageTurnViewState extends State<PageTurnView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _offset = AnimationController.unbounded(
    vsync: this,
  );
  int? _pointer;
  Offset _downPosition = Offset.zero;
  Duration _downTime = Duration.zero;
  Axis? _axis;
  VelocityTracker? _velocityTracker;
  bool _cancelled = false;
  Size _size = Size.zero;

  @override
  void didUpdateWidget(PageTurnView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index ||
        oldWidget.itemCount != widget.itemCount ||
        oldWidget.direction != widget.direction) {
      _resetInteraction();
    }
  }

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  void _resetInteraction() {
    _offset.stop();
    _offset.value = 0;
    _pointer = null;
    _axis = null;
    _velocityTracker = null;
    _cancelled = false;
  }

  void _handleDown(PointerDownEvent event) {
    if (_pointer != null) {
      _cancelled = true;
      return;
    }
    if (_offset.isAnimating) return;
    _pointer = event.pointer;
    _downPosition = event.localPosition;
    _downTime = event.timeStamp;
    _axis = null;
    _cancelled = false;
    _velocityTracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.localPosition);
  }

  void _handleMove(PointerMoveEvent event) {
    if (event.pointer != _pointer || _cancelled) return;
    _velocityTracker?.addPosition(event.timeStamp, event.localPosition);
    final delta = event.localPosition - _downPosition;
    if (_axis == null) {
      if (event.timeStamp - _downTime >= kLongPressTimeout) {
        _cancelled = true;
        return;
      }
      if (delta.distance < kTouchSlop) return;
      _axis = _chooseAxis(delta);
      if (_axis == null) {
        _cancelled = true;
        return;
      }
    }
    final value = _axis == Axis.horizontal ? delta.dx : delta.dy;
    final pageDelta = value < 0 ? 1 : -1;
    if (!_canTurn(pageDelta)) {
      _offset.value = 0;
      return;
    }
    final extent = _extent(_axis!);
    _offset.value = value.clamp(-extent, extent).toDouble();
  }

  void _handleUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    _velocityTracker?.addPosition(event.timeStamp, event.localPosition);
    final elapsed = event.timeStamp - _downTime;
    final distance = (event.localPosition - _downPosition).distance;
    final cancelled = _cancelled;
    final axis = _axis;
    final velocity = _velocityTracker?.getVelocity().pixelsPerSecond;
    _pointer = null;
    _velocityTracker = null;
    _cancelled = false;

    if (cancelled) {
      unawaited(_animateBack());
      return;
    }
    if (axis == null) {
      if (elapsed < kLongPressTimeout && distance < kTouchSlop) {
        final pageDelta = event.localPosition.dy < _size.height / 2 ? -1 : 1;
        unawaited(_animateTurn(pageDelta, _tapAxis));
      }
      return;
    }

    final axisVelocity = axis == Axis.horizontal ? velocity?.dx : velocity?.dy;
    final extent = _extent(axis);
    final moved = _offset.value.abs() >= extent * .2;
    final flung = axisVelocity != null &&
        axisVelocity.abs() >= 600 &&
        axisVelocity.sign == _offset.value.sign;
    if (!moved && !flung) {
      unawaited(_animateBack());
      return;
    }
    unawaited(_animateTurn(_offset.value < 0 ? 1 : -1, axis));
  }

  void _handleCancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _pointer = null;
    _velocityTracker = null;
    _cancelled = false;
    unawaited(_animateBack());
  }

  Axis? _chooseAxis(Offset delta) {
    return switch (widget.direction) {
      PageTurnDirection.horizontal =>
        delta.dx.abs() >= delta.dy.abs() ? Axis.horizontal : null,
      PageTurnDirection.vertical =>
        delta.dy.abs() >= delta.dx.abs() ? Axis.vertical : null,
      PageTurnDirection.both =>
        delta.dx.abs() >= delta.dy.abs() ? Axis.horizontal : Axis.vertical,
    };
  }

  Axis get _tapAxis => widget.direction == PageTurnDirection.horizontal
      ? Axis.horizontal
      : Axis.vertical;

  double _extent(Axis axis) =>
      axis == Axis.horizontal ? _size.width : _size.height;

  bool _canTurn(int pageDelta) {
    final target = widget.index + pageDelta;
    return target >= 0 && target < widget.itemCount;
  }

  Future<void> _animateTurn(int pageDelta, Axis axis) async {
    if (_offset.isAnimating) return;
    if (!_canTurn(pageDelta)) {
      await _animateBack();
      return;
    }
    setState(() => _axis = axis);
    final extent = _extent(axis);
    final target = pageDelta > 0 ? -extent : extent;
    final fraction = ((target - _offset.value).abs() / extent).clamp(.25, 1.0);
    await _offset.animateTo(
      target,
      duration: Duration(milliseconds: (180 * fraction).round()),
      curve: Curves.easeOutCubic,
    );
    if (!mounted) return;
    widget.onPageChanged(widget.index + pageDelta);
    if (!mounted) return;
    _offset.value = 0;
    setState(() => _axis = null);
  }

  Future<void> _animateBack() async {
    if (_offset.value != 0) {
      await _offset.animateTo(
        0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
      );
    }
    if (mounted) setState(() => _axis = null);
  }

  Offset _translation(Axis axis, double value) => axis == Axis.horizontal
      ? Offset(value, 0)
      : Offset(0, value);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        final previous = widget.index > 0
            ? KeyedSubtree(
                key: ValueKey(widget.index - 1),
                child: widget.itemBuilder(context, widget.index - 1),
              )
            : null;
        final current = KeyedSubtree(
          key: ValueKey(widget.index),
          child: widget.itemBuilder(context, widget.index),
        );
        final next = widget.index + 1 < widget.itemCount
            ? KeyedSubtree(
                key: ValueKey(widget.index + 1),
                child: widget.itemBuilder(context, widget.index + 1),
              )
            : null;
        return Semantics(
          onIncrease: next == null
              ? null
              : () => unawaited(_animateTurn(1, _tapAxis)),
          onDecrease: previous == null
              ? null
              : () => unawaited(_animateTurn(-1, _tapAxis)),
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _handleDown,
            onPointerMove: _handleMove,
            onPointerUp: _handleUp,
            onPointerCancel: _handleCancel,
            child: ClipRect(
              child: AnimatedBuilder(
                animation: _offset,
                builder: (context, _) {
                  final axis = _axis ?? _tapAxis;
                  final extent = _extent(axis);
                  final value = _offset.value;
                  final adjacent = value < 0 ? next : value > 0 ? previous : null;
                  final adjacentStart = value < 0 ? extent : -extent;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      if (adjacent != null)
                        Transform.translate(
                          offset: _translation(axis, adjacentStart + value),
                          child: adjacent,
                        ),
                      Transform.translate(
                        offset: _translation(axis, value),
                        child: current,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 4: Format and verify the swipe tests GREEN**

Run:

```bash
dart format lib/page_turn_view.dart test/page_turn_view_test.dart
flutter test test/page_turn_view_test.dart
```

Expected: all three swipe tests pass.

- [ ] **Step 5: Add failing tap, boundary, and long-press tests**

Insert these tests inside `main`, before its closing brace in `test/page_turn_view_test.dart`:

```dart
testWidgets('top and bottom taps turn backward and forward', (tester) async {
  final page = ValueNotifier(1);
  await _pumpPager(tester, page, PageTurnDirection.both);
  final rect = tester.getRect(find.byType(PageTurnView));

  await tester.tapAt(Offset(rect.center.dx, rect.top + 20));
  await tester.pumpAndSettle();
  expect(page.value, 0);

  await tester.tapAt(Offset(rect.center.dx, rect.bottom - 20));
  await tester.pumpAndSettle();
  expect(page.value, 1);
});

testWidgets('page boundaries ignore outward taps and drags', (tester) async {
  final page = ValueNotifier(0);
  await _pumpPager(tester, page, PageTurnDirection.both);
  final rect = tester.getRect(find.byType(PageTurnView));

  await tester.tapAt(Offset(rect.center.dx, rect.top + 20));
  await tester.drag(find.byType(PageTurnView), const Offset(300, 0));
  await tester.pumpAndSettle();

  expect(page.value, 0);
});

testWidgets('long press leaves the page unchanged for text selection', (
  tester,
) async {
  final page = ValueNotifier(1);
  await _pumpPager(tester, page, PageTurnDirection.both);
  final center = tester.getCenter(find.byType(SelectableText).first);

  final gesture = await tester.startGesture(center);
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
  await gesture.up();
  await tester.pump();

  expect(page.value, 1);
  expect(find.byType(SelectableText), findsWidgets);
});
```

- [ ] **Step 6: Run the complete component test file**

Run:

```bash
flutter test test/page_turn_view_test.dart
```

Expected: swipe, tap, boundary, and long-press tests all pass.

- [ ] **Step 7: Commit the component slice**

```bash
git add lib/page_turn_view.dart test/page_turn_view_test.dart
git commit -m "feat: add two-axis page turns"
```

---

### Task 3: Integrate the pager and direction settings into the reader

**Files:**
- Modify: `lib/reader_screen.dart:1-910,1090-1150,1430-1449`
- Modify: `test/reader_screen_test.dart:730-1120,1130-1160`

**Interfaces:**
- Consumes: `ReaderSettings.pageTurnDirection` and `PageTurnView` from Tasks 1-2.
- Produces: reader-owned `_pageIndex` and three display-setting choices.

- [ ] **Step 1: Add failing reader integration tests**

Add this import to `test/reader_screen_test.dart`:

```dart
import 'package:geulbom/page_turn_view.dart';
```

Add a test that injects three fixed pages, swipes vertically, and checks the saved offset:

```dart
testWidgets('reader applies vertical page turns to document progress', (
  tester,
) async {
  const text = 'firstsecondthird';
  const pages = [
    TextPage(start: 0, end: 5),
    TextPage(start: 5, end: 11),
    TextPage(start: 11, end: 16),
  ];
  final store = _MemoryStore()
    ..updateSettings(
      const ReaderSettings(
        mode: ReadingMode.page,
        pageTurnDirection: PageTurnDirection.vertical,
      ),
    );
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

  await tester.drag(find.byType(PageTurnView), const Offset(0, -300));
  await tester.pumpAndSettle();

  expect(store.document('/book.txt').offset, 5);
  expect(find.text('second'), findsOneWidget);
});
```

Add a settings test:

```dart
testWidgets('display settings persist all page turn directions', (tester) async {
  final store = _MemoryStore();
  await _pumpReader(tester, store, _longText);
  await tester.pumpAndSettle();

  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.tap(find.text('표시 설정'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('page-turn-vertical')));
  await tester.tap(find.byKey(const Key('page-turn-vertical')));
  await tester.ensureVisible(find.text('적용'));
  await tester.tap(find.text('적용'));
  await tester.pumpAndSettle();

  expect(
    store.data.settings.pageTurnDirection,
    PageTurnDirection.vertical,
  );
});
```

- [ ] **Step 2: Run the two tests and verify RED**

Run:

```bash
flutter test test/reader_screen_test.dart --plain-name "reader applies vertical page turns to document progress"
flutter test test/reader_screen_test.dart --plain-name "display settings persist all page turn directions"
```

Expected: the first cannot find `PageTurnView`, and the second cannot find `page-turn-vertical`.

- [ ] **Step 3: Replace controller ownership with a page index**

Import the component and replace the two controller fields:

```dart
import 'page_turn_view.dart';

int? _pageIndex;
```

Remove all `_pageController.dispose()` and `_pageControllerInitialOffset` code. In `_setPaginationPages`, assign `_pageIndex = initialPage` when a complete list arrives, or when the first progressive list covers `_offset`. For a pending offset, assign the computed page index in the existing post-frame callback instead of calling `jumpToPage`:

```dart
if (complete) {
  _pageWindowGeneration++;
  _pageWindow = null;
  _pageIndex = pages.isEmpty ? null : initialPage;
  _displayPageNumber = initialPage + 1;
} else if (_pageWindow == null &&
    _pageIndex == null &&
    pages.isNotEmpty &&
    pages.last.end > _offset) {
  _pageIndex = initialPage;
}
```

```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  if (!mounted || _pendingPageOffset != pendingOffset) return;
  setState(() {
    _pendingPageOffset = null;
    _pageIndex = page;
    _displayPageNumber = page + 1;
  });
});
```

Replace `_jumpToOffset` with this index-owned version:

```dart
void _jumpToOffset(int offset) {
  _navigationGeneration++;
  _pendingTargetPage = null;
  _pendingPageOffset = null;
  setState(() => _setOffset(offset));
  if (_settings.mode == ReadingMode.scroll) {
    _pendingScrollOffset = _offset;
    if (_itemScrollController.isAttached) {
      _itemScrollController.jumpTo(index: _chunkForOffset(_offset));
    }
    return;
  }
  final window = _pageWindow;
  if (window != null) {
    if (_offset >= window.pages.first.start &&
        _offset < window.pages.last.end) {
      final page = pageForOffset(window.pages, _offset);
      setState(() {
        _pageIndex = page;
        _displayPageNumber = window.firstPage + page;
      });
    } else {
      final total = _displayTotalPages;
      unawaited(
        _jumpToPageNumber(
          estimatedPageForOffset(
            _offset,
            textLength: widget.text.length,
            totalPages: total,
          ),
          sourceOffset: _offset,
        ),
      );
    }
    return;
  }
  final pages = _pages;
  if (pages != null &&
      pages.isNotEmpty &&
      (_paginationComplete || _offset < pages.last.end)) {
    final page = pageForOffset(pages, _offset);
    setState(() {
      _pageIndex = page;
      _displayPageNumber = page + 1;
    });
  } else {
    final totalPages = _displayTotalPages;
    unawaited(
      _jumpToPageNumber(
        estimatedPageForOffset(
          _offset,
          textLength: widget.text.length,
          totalPages: totalPages,
        ),
        sourceOffset: _offset,
      ),
    );
  }
}
```

In `_jumpToPageNumber`'s window result, remove the controller creation and include `_pageIndex = localPage` in its existing `setState`. Set `_pageIndex = null` in `_ensurePages` and `_applySettings`, and remove the controller disposal from `dispose`.

- [ ] **Step 4: Render `PageTurnView` and update progress on completed turns**

After the existing `window` and `pages` declarations in `_buildPageReader`, replace its loading and reader branches with this controlled view:

```dart
final pageIndex = _pageIndex;
if (pages == null || pageIndex == null || pages.isEmpty) {
  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(
          value: _paginationProgress == 0 ? null : _paginationProgress,
        ),
        const SizedBox(height: 12),
        const Text('페이지를 계산하고 있습니다.'),
      ],
    ),
  );
}
final safeIndex = pageIndex.clamp(0, pages.length - 1).toInt();
return Stack(
  children: [
    PageTurnView(
      index: safeIndex,
      itemCount: pages.length,
      direction: _settings.pageTurnDirection,
      onPageChanged: (index) {
        final activePages = _pageWindow?.pages ?? _pages;
        if (!identical(activePages, pages)) return;
        _registerManualNavigation();
        final nextOffset = pages[index].start;
        setState(() {
          _pageIndex = index;
          _displayPageNumber = window == null
              ? index + 1
              : window.firstPage + index;
          _pendingPageOffset = null;
          _pendingScrollOffset = null;
          _setOffset(nextOffset);
        });
      },
      itemBuilder: (context, index) {
        final page = pages[index];
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: _settings.horizontalPadding,
          ),
          child: Align(
            alignment: Alignment.topLeft,
            child: SelectableText(
              widget.text.substring(page.start, page.end),
              style: _textStyle,
            ),
          ),
        );
      },
    ),
    _buildPageIndicator(),
  ],
);
```

- [ ] **Step 5: Add the three display-setting chips**

Insert after the reading-mode choices:

```dart
const SizedBox(height: 12),
const Text('페이지 넘김 방향'),
Wrap(
  spacing: 8,
  children: [
    ChoiceChip(
      key: const Key('page-turn-horizontal'),
      label: const Text('좌우 넘김'),
      selected: draft.pageTurnDirection == PageTurnDirection.horizontal,
      onSelected: (_) => setSheetState(() {
        draft = draft.copyWith(
          pageTurnDirection: PageTurnDirection.horizontal,
        );
      }),
    ),
    ChoiceChip(
      key: const Key('page-turn-vertical'),
      label: const Text('상하 넘김'),
      selected: draft.pageTurnDirection == PageTurnDirection.vertical,
      onSelected: (_) => setSheetState(() {
        draft = draft.copyWith(
          pageTurnDirection: PageTurnDirection.vertical,
        );
      }),
    ),
    ChoiceChip(
      key: const Key('page-turn-both'),
      label: const Text('둘 다'),
      selected: draft.pageTurnDirection == PageTurnDirection.both,
      onSelected: (_) => setSheetState(() {
        draft = draft.copyWith(pageTurnDirection: PageTurnDirection.both);
      }),
    ),
  ],
),
```

- [ ] **Step 6: Update PageView-specific regression assertions**

Replace the three tests that inspect `PageView.childrenDelegate`, `PageView.controller.page`, or `PageController` with `PageTurnView.itemCount` and `PageTurnView.index` assertions:

```dart
final pager = tester.widget<PageTurnView>(find.byType(PageTurnView));
expect(pager.itemCount, pages.length);
expect(pager.index, expectedIndex);
```

Do not loosen their existing offset, visible-text, or progressive-batch assertions.

- [ ] **Step 7: Format and verify reader/component regressions**

Run:

```bash
dart format lib/reader_screen.dart test/reader_screen_test.dart
flutter test test/page_turn_view_test.dart test/reader_screen_test.dart
```

Expected: all page component and reader tests pass.

- [ ] **Step 8: Commit the reader integration**

```bash
git add lib/reader_screen.dart test/reader_screen_test.dart
git commit -m "feat: integrate page turn controls"
```

---

### Task 4: Fix page boundaries and reserve the indicator area

**Files:**
- Modify: `lib/text_paginator.dart:145-176`
- Modify: `lib/reader_screen.dart:340-355,498-510,540-558`
- Test: `test/text_paginator_test.dart:1-55`
- Test: `test/reader_screen_test.dart`

**Interfaces:**
- Consumes: existing `_nextPageEnd`, `ReaderView.paginator`, and page item padding.
- Produces: pages that do not start on an incidental boundary newline and a shared 40px page-mode bottom inset.

- [ ] **Step 1: Write failing newline-boundary tests**

Add to `test/text_paginator_test.dart`:

```dart
test('moves a boundary newline to the previous page', () async {
  const text = '첫 줄\n둘째 줄\n셋째 줄';

  final pages = await paginateText(
    text: text,
    size: const Size(500, 24),
    style: const TextStyle(fontSize: 20, height: 1),
  );

  expect(pages.length, greaterThan(1));
  expect(text.codeUnitAt(pages[1].start), isNot(0x0a));
  expect(pages.map((page) => text.substring(page.start, page.end)).join(), text);
});

test('keeps one intentional newline from a consecutive pair', () async {
  const text = '첫 줄\n\n둘째 줄\n셋째 줄';

  final pages = await paginateText(
    text: text,
    size: const Size(500, 24),
    style: const TextStyle(fontSize: 20, height: 1),
  );

  expect(text.substring(pages.first.end), startsWith('\n둘째 줄'));
});
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
flutter test test/text_paginator_test.dart --plain-name "moves a boundary newline to the previous page"
```

Expected: the second page starts at `\n`.

- [ ] **Step 3: Consume exactly one boundary newline**

After calculating `end` and fixing surrogate pairs in `_nextPageEnd`, add:

```dart
if (end < text.length && text.codeUnitAt(end) == 0x0a) end++;
```

Keep the final clamp unchanged. This consumes one delimiter; if the source has `\n\n`, the second newline remains at the next page start as the intentional blank line.

- [ ] **Step 4: Verify the paginator file GREEN**

Run:

```bash
dart format lib/text_paginator.dart test/text_paginator_test.dart
flutter test test/text_paginator_test.dart
```

Expected: all paginator tests pass and page ranges still cover the source exactly.

- [ ] **Step 5: Write a failing page-height integration test**

Inject a paginator that records its `size` and returns one full page. After pumping the reader in page mode, compare that height with the rendered `PageTurnView`:

```dart
testWidgets('page mode reserves the indicator area from pagination', (
  tester,
) async {
  Size? measuredSize;
  final store = _MemoryStore()
    ..updateSettings(const ReaderSettings(mode: ReadingMode.page));
  await tester.pumpWidget(
    MaterialApp(
      home: ReaderView(
        path: '/book.txt',
        title: 'book.txt',
        text: _longText,
        encoding: TextEncoding.utf8,
        store: store,
        paginator: ({
          required text,
          required size,
          required style,
          onProgress,
          onBatch,
          onLayout,
          isCancelled,
        }) async {
          measuredSize = size;
          final pages = [TextPage(start: 0, end: text.length)];
          onBatch?.call(pages);
          return pages;
        },
      ),
    ),
  );
  await tester.pumpAndSettle();

  final pagerHeight = tester.getSize(find.byType(PageTurnView)).height;
  expect(measuredSize?.height, pagerHeight - 40);
  final padding = tester.widget<Padding>(
    find.byKey(const Key('page-content-0')),
  );
  expect((padding.padding as EdgeInsets).bottom, 40);
});
```

- [ ] **Step 6: Run the integration test and verify RED**

Run:

```bash
flutter test test/reader_screen_test.dart --plain-name "page mode reserves the indicator area from pagination"
```

Expected: paginator height still equals the whole reader body and `page-content-0` does not exist.

- [ ] **Step 7: Use one shared page bottom inset**

Add near the reader constants:

```dart
const _pageIndicatorInset = 40.0;
```

In `LayoutBuilder`, subtract it only in page mode:

```dart
final pageBottomInset = _settings.mode == ReadingMode.page
    ? _pageIndicatorInset
    : 0.0;
final pageSize = Size(
  math.max(1, constraints.maxWidth - _settings.horizontalPadding * 2),
  math.max(1, constraints.maxHeight - pageBottomInset),
);
```

Use the same value in the page item:

```dart
return Padding(
  key: Key('page-content-$index'),
  padding: EdgeInsets.fromLTRB(
    _settings.horizontalPadding,
    0,
    _settings.horizontalPadding,
    _pageIndicatorInset,
  ),
  child: Align(
    alignment: Alignment.topLeft,
    child: SelectableText(
      widget.text.substring(page.start, page.end),
      style: _textStyle,
    ),
  ),
);
```

Bump the pagination cache signature from `'algorithm': 2` to `'algorithm': 3`.

- [ ] **Step 8: Verify layout and pagination regressions**

Run:

```bash
dart format lib/reader_screen.dart lib/text_paginator.dart test/reader_screen_test.dart test/text_paginator_test.dart
flutter test test/text_paginator_test.dart test/reader_screen_test.dart test/qa_large_file_test.dart
```

Expected: the new boundary/inset tests and all affected regressions pass.

- [ ] **Step 9: Commit the layout fix**

```bash
git add lib/text_paginator.dart lib/reader_screen.dart test/text_paginator_test.dart test/reader_screen_test.dart test/qa_large_file_test.dart
git commit -m "fix: align page text boundaries"
```

---

### Task 5: Request the highest compatible Android refresh rate

**Files:**
- Modify: `android/app/src/main/kotlin/com/songs/geulbom/MainActivity.kt`

**Interfaces:**
- Consumes: Android `Display.supportedModes` and `WindowManager.LayoutParams.preferredRefreshRate` available above the app's minSdk 24.
- Produces: a best-effort maximum refresh preference each time the activity resumes.

- [ ] **Step 1: Add the minimal platform request**

Replace `MainActivity.kt` with:

```kotlin
package com.songs.geulbom

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onResume() {
        super.onResume()
        val display = window.decorView.display ?: return
        val currentMode = display.mode
        val maximumRefreshRate = display.supportedModes
            .asSequence()
            .filter {
                it.physicalWidth == currentMode.physicalWidth &&
                    it.physicalHeight == currentMode.physicalHeight
            }
            .maxOfOrNull { it.refreshRate }
            ?: return
        window.attributes = window.attributes.apply {
            preferredRefreshRate = maximumRefreshRate
        }
    }
}
```

This is platform glue without an Android unit-test harness; verify it by Kotlin compilation and the release build rather than adding a dependency that only tests framework field assignment.

- [ ] **Step 2: Compile the Android release artifact**

Run:

```bash
flutter build apk --release --no-pub
```

Expected: Kotlin and Gradle compile successfully and `build/app/outputs/flutter-apk/app-release.apk` is produced.

- [ ] **Step 3: Commit the Android request**

```bash
git add android/app/src/main/kotlin/com/songs/geulbom/MainActivity.kt
git commit -m "perf: request high Android refresh rate"
```

---

### Task 6: Repository-wide verification

**Files:**
- Verify only; modify a file only if a command exposes a regression caused by Tasks 1-5.

**Interfaces:**
- Consumes: all preceding commits.
- Produces: a clean, buildable branch ready for review and integration.

- [ ] **Step 1: Check formatting and static analysis**

Run:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
```

Expected: no formatting changes and no analyzer issues.

- [ ] **Step 2: Run the full test suite**

Run:

```bash
flutter test --reporter expanded --no-pub
```

Expected: all tests pass with zero failures.

- [ ] **Step 3: Build the release APK**

Run:

```bash
flutter build apk --release --no-pub
```

Expected: `build/app/outputs/flutter-apk/app-release.apk` is produced.

- [ ] **Step 4: Inspect the final diff and worktree**

Run:

```bash
git diff --check master...HEAD
git status -sb
git log --oneline master..HEAD
```

Expected: no whitespace errors, no uncommitted files, and only the planned feature commits.

- [ ] **Step 5: Record the device-only acceptance check**

Install the release APK on a 120Hz Android device, select each direction, and confirm that dragging follows the finger without a visible 60Hz cadence. Also confirm that Android power-saving mode may lower the selected refresh rate without breaking navigation.
