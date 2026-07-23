import 'dart:async';

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

  testWidgets('multi-touch stays cancelled until every pointer lifts', (
    tester,
  ) async {
    final page = ValueNotifier(1);
    await _pumpPager(tester, page, PageTurnDirection.horizontal);
    final center = tester.getCenter(find.byType(PageTurnView));

    final first = await tester.startGesture(center, pointer: 1);
    final second = await tester.startGesture(center, pointer: 2);
    await first.up();

    final third = await tester.startGesture(center, pointer: 3);
    await third.moveBy(const Offset(-300, 0));
    await third.up();
    await tester.pumpAndSettle();
    expect(page.value, 1);

    await second.up();
    await tester.drag(find.byType(PageTurnView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(page.value, 2);
  });

  testWidgets('swipe-only mode ignores taps', (tester) async {
    final page = ValueNotifier(1);
    await _pumpPager(tester, page, PageTurnDirection.horizontal);
    final rect = tester.getRect(find.byType(PageTurnView));

    await tester.tapAt(Offset(rect.right - 20, rect.center.dy));
    await tester.pumpAndSettle();

    expect(page.value, 1);
  });

  testWidgets('horizontal tap-only mode uses left and right halves', (
    tester,
  ) async {
    final page = ValueNotifier(1);
    await _pumpPager(tester, page, PageTurnDirection.horizontal, tapOnly: true);
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
    await _pumpPager(tester, page, PageTurnDirection.horizontal, tapOnly: true);

    await tester.drag(find.byType(PageTurnView), const Offset(-300, 0));
    await tester.pumpAndSettle();

    expect(page.value, 1);
  });

  testWidgets('page boundaries ignore outward taps and drags', (tester) async {
    final page = ValueNotifier(0);
    await _pumpPager(tester, page, PageTurnDirection.both);
    final rect = tester.getRect(find.byType(PageTurnView));

    await tester.tapAt(Offset(rect.center.dx, rect.top + 20));
    await tester.pumpAndSettle();
    expect(page.value, 0);

    final partialReversal = await tester.startGesture(rect.center);
    await partialReversal.moveBy(const Offset(300, 0));
    await partialReversal.moveBy(const Offset(-200, 0));
    await tester.pump();
    final partialPosition = tester.getTopLeft(find.text('page 0')).dx;
    await partialReversal.up();
    await tester.pumpAndSettle();

    expect(partialPosition, closeTo(rect.left, 1));
    expect(page.value, 0);

    final netInward = await tester.startGesture(rect.center);
    await netInward.moveBy(const Offset(300, 0));
    await netInward.moveBy(const Offset(-600, 0));
    await netInward.up();
    await tester.pumpAndSettle();

    expect(page.value, 1);
  });

  testWidgets('keeps fractional drag progress through resize and movement', (
    tester,
  ) async {
    final page = ValueNotifier(1);
    final width = ValueNotifier(600.0);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: ValueListenableBuilder<double>(
            valueListenable: width,
            builder: (context, pageWidth, _) => SizedBox(
              width: pageWidth,
              height: 400,
              child: ValueListenableBuilder<int>(
                valueListenable: page,
                builder: (context, index, _) => PageTurnView(
                  index: index,
                  itemCount: 3,
                  direction: PageTurnDirection.horizontal,
                  tapOnly: false,
                  onPageChanged: (value) => page.value = value,
                  itemBuilder: (context, itemIndex) => ColoredBox(
                    key: ValueKey('page $itemIndex'),
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final initialRect = tester.getRect(find.byType(PageTurnView));
    final gesture = await tester.startGesture(initialRect.center);
    await gesture.moveBy(const Offset(-150, 0));
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('page 1'))).dx,
      closeTo(initialRect.left - 150, 1),
    );

    width.value = 300;
    await tester.pump();
    final resizedRect = tester.getRect(find.byType(PageTurnView));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('page 1'))).dx,
      closeTo(resizedRect.left - 75, 1),
    );

    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('page 1'))).dx,
      closeTo(resizedRect.left - 105, 1),
    );

    await gesture.cancel();
    await tester.pumpAndSettle();
  });

  testWidgets('long press leaves the page unchanged for text selection', (
    tester,
  ) async {
    final page = ValueNotifier(1);
    final selections = <TextSelection>[];
    await _pumpPager(
      tester,
      page,
      PageTurnDirection.both,
      onSelectionChanged: (selection, _) => selections.add(selection),
    );
    final rect = tester.getRect(find.byType(SelectableText).first);

    final gesture = await tester.startGesture(
      Offset(rect.left + 15, rect.top + 10),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pump();

    expect(page.value, 1);
    expect(selections.any((selection) => !selection.isCollapsed), isTrue);
  });

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
    final current = find.widgetWithText(SelectableText, 'page 1');
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

  testWidgets('system reduced motion makes programmatic turns immediate', (
    tester,
  ) async {
    final key = GlobalKey<PageTurnViewState>();
    final page = ValueNotifier(0);
    addTearDown(page.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: ValueListenableBuilder<int>(
            valueListenable: page,
            builder: (context, index, _) => PageTurnView(
              key: key,
              index: index,
              itemCount: 3,
              direction: PageTurnDirection.vertical,
              onPageChanged: (value) => page.value = value,
              itemBuilder: (_, itemIndex) => Text('page $itemIndex'),
            ),
          ),
        ),
      ),
    );

    final turn = key.currentState!.animateNext(Axis.vertical);
    await tester.pump();

    expect(await turn, isTrue);
    expect(page.value, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
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
}

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
