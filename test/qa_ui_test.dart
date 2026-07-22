import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geulbom/app_store.dart';
import 'package:geulbom/reader_screen.dart';
import 'package:geulbom/text_document.dart';

void main() {
  testWidgets('320x568 화면에서 RGB 오류를 표시하고 잘못된 값을 저장하지 않는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _MemoryStore();

    await _pumpReader(tester, store: store, text: '가나다라마바사');

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, const Color.fromARGB(255, 196, 236, 187));

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('표시 설정'));
    await tester.pumpAndSettle();

    for (final name in ['기본 연두', '종이', '밤', '세피아']) {
      expect(find.byKey(Key('color-template-$name')), findsOneWidget);
      expect(find.byTooltip(name), findsOneWidget);
      expect(find.text(name), findsNothing);
    }
    final templateButton = tester.widget<IconButton>(
      find.byKey(const Key('color-template-기본 연두')),
    );
    final swatch = templateButton.icon as Container;
    expect(
      (swatch.decoration! as BoxDecoration).color,
      const Color(0xffc4ecbb),
    );

    final red = find.byKey(const Key('background-red'));
    await tester.ensureVisible(red);
    await tester.enterText(red, '999');
    await tester.pump();

    expect(find.text('0~255'), findsOneWidget);

    expect(find.text('적용'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(store.data.settings.background.red, 196);
    expect(tester.takeException(), isNull);
  });

  testWidgets('800x360 가로 화면의 햄버거 메뉴에 필수 기능이 유지된다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpReader(tester, store: _MemoryStore(), text: '본문\n' * 100);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    for (final label in ['위치 이동', '본문 검색', '북마크', '표시 설정', '파일 정보']) {
      expect(find.text(label, skipOffstage: false), findsOneWidget);
    }
    await tester.drag(find.byType(ListView).last, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(find.text('파일 정보'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('빈 파일은 안내를 표시하고 북마크 추가를 막는다', (tester) async {
    await _pumpReader(tester, store: _MemoryStore(), text: '');

    expect(find.text('빈 파일입니다.'), findsOneWidget);
    final bookmark = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.bookmark_add_outlined),
    );
    expect(bookmark.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpReader(
  WidgetTester tester, {
  required _MemoryStore store,
  required String text,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ReaderView(
        path: '/qa.txt',
        title: 'qa.txt',
        text: text,
        encoding: TextEncoding.utf8,
        store: store,
      ),
    ),
  );
  await tester.pump();
}

class _MemoryStore extends AppStore {
  _MemoryStore() : super(File('unused'));

  @override
  Future<void> save() async {}
}
