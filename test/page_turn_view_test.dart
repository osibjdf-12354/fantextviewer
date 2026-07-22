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
}

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
          itemBuilder: (context, itemIndex) =>
              SelectableText('page $itemIndex', key: ValueKey(itemIndex)),
        ),
      ),
    ),
  );
}
