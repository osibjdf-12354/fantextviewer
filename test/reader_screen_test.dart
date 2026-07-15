import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geulbom/app_store.dart';
import 'package:geulbom/models.dart';
import 'package:geulbom/page_index_cache.dart';
import 'package:geulbom/reader_screen.dart';
import 'package:geulbom/text_document.dart';
import 'package:geulbom/text_paginator.dart';

final _longText = List.filled(300, '가나다라마바사아자차카타파하\n').join();

void main() {
  testWidgets('강제 인코딩마다 별도 페이지 캐시를 사용한다', (tester) async {
    const text = '같은길이본문';
    final cache = _MemoryPageIndexCache();
    var paginationCalls = 0;
    Future<List<TextPage>> paginator({
      required String text,
      required Size size,
      required TextStyle style,
      ValueChanged<double>? onProgress,
      PaginationBatchCallback? onBatch,
      TextLayoutCallback? onLayout,
      bool Function()? isCancelled,
    }) async {
      paginationCalls++;
      return [TextPage(start: 0, end: text.length)];
    }

    Future<void> pumpEncoding(TextEncoding encoding) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderView(
            key: ValueKey(encoding),
            path: '/book.txt',
            title: 'book.txt',
            text: text,
            encoding: encoding,
            store: _MemoryStore(),
            fileSize: 12,
            modified: DateTime.utc(2026, 7, 15),
            pageIndexCache: cache,
            paginator: paginator,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpEncoding(TextEncoding.utf8);
    await pumpEncoding(TextEncoding.cp949);

    expect(paginationCalls, 2);
    expect(cache.loadSignatures.toSet(), hasLength(2));
  });

  testWidgets('페이지 계산 완료 전에 저장 위치를 덮는 배치를 표시한다', (tester) async {
    const text = '첫페이지둘째페이지';
    final store = _MemoryStore()
      ..updateSettings(const ReaderSettings(mode: ReadingMode.page))
      ..updateProgress('/book.txt', offset: 4, documentLength: text.length);
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
          paginator:
              ({
                required text,
                required size,
                required style,
                onProgress,
                onBatch,
                onLayout,
                isCancelled,
              }) {
                emitBatch = onBatch;
                onBatch?.call(const [TextPage(start: 0, end: 4)]);
                return completion.future;
              },
        ),
      ),
    );
    await tester.pump();

    expect(find.text('페이지를 계산하고 있습니다.'), findsOneWidget);
    expect(find.text('첫페이지'), findsNothing);

    emitBatch?.call([TextPage(start: 4, end: text.length)]);
    await tester.pump();

    expect(completion.isCompleted, isFalse);
    expect(find.text('둘째페이지'), findsOneWidget);

    completion.complete([
      const TextPage(start: 0, end: 4),
      TextPage(start: 4, end: text.length),
    ]);
    await tester.pump();
  });

  testWidgets('나중 배치가 검색 위치를 덮으면 해당 페이지로 이동한다', (tester) async {
    const text = '첫페이지둘째페이지찾을본문';
    final store = _MemoryStore()
      ..updateSettings(const ReaderSettings(mode: ReadingMode.page));
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
          paginator:
              ({
                required text,
                required size,
                required style,
                onProgress,
                onBatch,
                onLayout,
                isCancelled,
              }) {
                emitBatch = onBatch;
                onBatch?.call(const [TextPage(start: 0, end: 4)]);
                return completion.future;
              },
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('본문 검색'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '찾을본문');
    await tester.tap(find.text('검색'));
    await tester.pumpAndSettle();

    expect(store.document('/book.txt').offset, 9);
    expect(tester.widget<PageView>(find.byType(PageView)).controller?.page, 0);

    emitBatch?.call([
      const TextPage(start: 4, end: 9),
      TextPage(start: 9, end: text.length),
    ]);
    await tester.pump();
    await tester.pump();

    expect(tester.widget<PageView>(find.byType(PageView)).controller?.page, 2);
    expect(find.text('찾을본문'), findsOneWidget);

    completion.complete([
      const TextPage(start: 0, end: 4),
      const TextPage(start: 4, end: 9),
      TextPage(start: 9, end: text.length),
    ]);
    await tester.pump();
  });

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

  testWidgets('표시 설정은 단계 버튼으로 값과 과거 소수값을 조절한다', (tester) async {
    final store = _MemoryStore()
      ..updateSettings(
        const ReaderSettings(
          fontSize: 20.4,
          lineHeight: 1.66,
          horizontalPadding: 20.4,
        ),
      );
    await _pumpReader(tester, store, '본문');
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('표시 설정'));
    await tester.pumpAndSettle();

    expect(find.byType(Slider), findsNothing);
    expect(find.byKey(const Key('font-size-increase')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('font-size-increase')));
    await tester.tap(find.byKey(const Key('font-size-increase')));
    await tester.tap(find.byKey(const Key('line-height-decrease')));
    await tester.tap(find.byKey(const Key('horizontal-padding-increase')));
    await tester.ensureVisible(find.text('적용'));
    await tester.tap(find.text('적용'));
    await tester.pumpAndSettle();

    expect(store.data.settings.fontSize, 21);
    expect(store.data.settings.lineHeight, 1.6);
    expect(store.data.settings.horizontalPadding, 21);
  });

  testWidgets('단계 버튼은 최솟값과 최댓값을 넘지 않는다', (tester) async {
    final store = _MemoryStore()
      ..updateSettings(
        const ReaderSettings(
          fontSize: 36,
          lineHeight: 1.2,
          horizontalPadding: 40,
        ),
      );
    await _pumpReader(tester, store, '본문');
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('표시 설정'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('font-size-increase')), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('font-size-increase')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('line-height-decrease')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('horizontal-padding-increase')),
          )
          .onPressed,
      isNull,
    );
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

class _MemoryPageIndexCache extends PageIndexCache {
  final records = <String, List<TextPage>>{};
  final loadSignatures = <String>[];

  @override
  Future<List<TextPage>?> load({
    required String signature,
    required int textLength,
  }) async {
    loadSignatures.add(signature);
    return records[signature];
  }

  @override
  Future<void> save({
    required String signature,
    required int textLength,
    required List<TextPage> pages,
  }) async {
    records[signature] = pages;
  }
}
