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
}

Future<void> _pumpPager(
  WidgetTester tester,
  ValueNotifier<int> page,
  PageTurnDirection direction, {
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
