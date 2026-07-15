import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geulbom/app_store.dart';
import 'package:geulbom/models.dart';
import 'package:geulbom/reader_screen.dart';
import 'package:geulbom/text_document.dart';

void main() {
  testWidgets('햄버거 메뉴에서 읽기 모드와 RGB 배경색을 바꾼다', (tester) async {
    final store = _MemoryStore();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderView(
          path: '/book.txt',
          title: 'book.txt',
          text: '가나다라마바사',
          encoding: TextEncoding.utf8,
          store: store,
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('위치 이동'), findsOneWidget);
    expect(find.text('본문 검색'), findsOneWidget);
    expect(find.text('북마크'), findsOneWidget);
    expect(find.text('표시 설정'), findsOneWidget);

    await tester.tap(find.text('표시 설정'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('페이지 넘김'));
    await tester.tap(find.text('페이지 넘김'));
    final red = find.byKey(const Key('background-red'));
    await tester.ensureVisible(red);
    await tester.enterText(red, '100');
    await tester.ensureVisible(find.text('적용'));
    await tester.tap(find.text('적용'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(store.data.settings.mode, ReadingMode.page);
    expect(store.data.settings.background.red, 100);
    expect(store.data.settings.background.green, 236);
  });

  test('같은 RGB 색의 명암비는 1이다', () {
    expect(
      contrastRatio(
        const RgbColor(196, 236, 187),
        const RgbColor(196, 236, 187),
      ),
      1,
    );
  });
}

class _MemoryStore extends AppStore {
  _MemoryStore() : super(File('unused'));

  @override
  Future<void> save() async {}
}
