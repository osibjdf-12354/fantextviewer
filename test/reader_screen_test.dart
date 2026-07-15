import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geulbom/app_store.dart';
import 'package:geulbom/models.dart';
import 'package:geulbom/reader_screen.dart';
import 'package:geulbom/text_document.dart';

final _longText = List.filled(300, '가나다라마바사아자차카타파하\n').join();

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

  testWidgets('스크롤 모드에서도 페이지 번호로 이동한다', (tester) async {
    final store = _MemoryStore();
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpReader(tester, store, _longText);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('위치 이동'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration?.labelText, '페이지');
    expect(find.textContaining('퍼센트'), findsNothing);
    await tester.enterText(find.byType(TextField), '2');
    await tester.tap(find.text('이동'));
    await tester.pumpAndSettle();

    expect(store.document('/book.txt').offset, greaterThan(0));
  });

  testWidgets('퍼센트와 범위 밖 페이지를 거부한다', (tester) async {
    final store = _MemoryStore();
    await _pumpReader(tester, store, _longText);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('위치 이동'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '50%');
    await tester.tap(find.text('이동'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining(RegExp(r'^1~\d+ 사이 페이지를 입력해 주세요\.$')),
      findsOneWidget,
    );
  });

  testWidgets('읽기 화면은 작은 상단바와 종료 메뉴를 사용하고 하단바가 없다', (tester) async {
    final store = _MemoryStore()
      ..updateSettings(const ReaderSettings(mode: ReadingMode.page));
    await _pumpReader(tester, store, _longText);
    await tester.pumpAndSettle();

    expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, 48);
    expect(find.byType(Slider), findsNothing);
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('앱 종료'), findsOneWidget);
  });

  testWidgets('종료 메뉴는 플랫폼 앱 종료를 요청한다', (tester) async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await _pumpReader(tester, _MemoryStore(), '본문');
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    expect(find.text('앱 종료'), findsOneWidget);
    await tester.tap(find.text('앱 종료'));
    await tester.pumpAndSettle();
    expect(calls.any((call) => call.method == 'SystemNavigator.pop'), isTrue);
  });

  testWidgets('북마크를 페이지 번호로 안내하고 표시한다', (tester) async {
    final store = _MemoryStore();
    await _pumpReader(tester, store, _longText);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.bookmark_add_outlined));
    await tester.pump();
    expect(
      find.textContaining(RegExp(r'^\d+페이지에 북마크를 저장했습니다\.$')),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('북마크'));
    await tester.pumpAndSettle();
    expect(find.textContaining(RegExp(r'^\d+페이지$')), findsOneWidget);
  });
}

Future<void> _pumpReader(
  WidgetTester tester,
  _MemoryStore store,
  String text,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ReaderView(
        path: '/book.txt',
        title: 'book.txt',
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
