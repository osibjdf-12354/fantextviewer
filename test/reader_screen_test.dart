import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geulbom/app_store.dart';
import 'package:geulbom/font_library.dart';
import 'package:geulbom/models.dart';
import 'package:geulbom/page_index_cache.dart';
import 'package:geulbom/page_turn_view.dart';
import 'package:geulbom/reader_screen.dart';
import 'package:geulbom/text_document.dart';
import 'package:geulbom/text_paginator.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

final _longText = List.filled(300, '가나다라마바사아자차카타파하\n').join();

void main() {
  testWidgets('페이지 계산과 본문은 같은 시스템 글자 배율을 사용한다', (tester) async {
    const text = '본문';
    TextStyle? measuredStyle;
    final store = _MemoryStore()
      ..updateSettings(
        const ReaderSettings(mode: ReadingMode.page, fontSize: 20),
      );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: ReaderView(
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
                    required paragraphIndent,
                    onProgress,
                    onBatch,
                    onLayout,
                    isCancelled,
                  }) async {
                    measuredStyle = style;
                    final pages = [TextPage(start: 0, end: text.length)];
                    onBatch?.call(pages);
                    return pages;
                  },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pageContent = find.byKey(const Key('page-content-0'));
    final pageText = tester.widget<Text>(
      find.descendant(
        of: pageContent,
        matching: find.byWidgetPredicate(
          (widget) => widget is Text && widget.data == text,
        ),
      ),
    );
    expect(measuredStyle?.fontSize, 30);
    expect(pageText.style, measuredStyle);
    expect(pageText.style?.inherit, isFalse);
    expect(pageText.textScaler, TextScaler.noScaling);
    expect(
      find.descendant(of: pageContent, matching: find.byType(SelectionArea)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: pageContent, matching: find.byType(Scrollable)),
      findsNothing,
    );
  });

  testWidgets('선택 글꼴을 본문에 적용하고 글꼴별 페이지 캐시를 사용한다', (tester) async {
    const text = '본문';
    final cache = _MemoryPageIndexCache();

    Future<void> pumpFont(String fileName) async {
      final store = _MemoryStore()
        ..updateSettings(ReaderSettings(fontFileName: fileName));
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderView(
            key: ValueKey(fileName),
            path: '/book.txt',
            title: 'book.txt',
            text: text,
            encoding: TextEncoding.utf8,
            store: store,
            pageIndexCache: cache,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(
              find
                  .descendant(
                    of: find.byKey(const Key('scroll-selection-area')),
                    matching: find.byType(Text),
                  )
                  .first,
            )
            .style
            ?.fontFamily,
        fontFamilyFor(fileName),
      );
    }

    await pumpFont('명조.ttf');
    await pumpFont('고딕.otf');

    expect(cache.loadSignatures.toSet(), hasLength(2));
  });

  testWidgets('같은 파일명의 글꼴이 바뀌면 새 페이지 캐시 서명을 사용한다', (tester) async {
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('geulbom_font_version'),
    ))!;
    addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
    final fonts = Directory('${root.path}${Platform.pathSeparator}fonts');
    final font = File('${fonts.path}${Platform.pathSeparator}same.ttf');
    final originalModified = DateTime.utc(2026, 7, 18, 1);
    final replacedModified = DateTime.utc(2026, 7, 18, 2);
    await tester.runAsync(() async {
      await fonts.create();
      await font.writeAsBytes([1]);
      await font.setLastModified(originalModified);
    });
    final cache = _MemoryPageIndexCache();

    Future<void> pumpFontLibrary(FontLibrary library, Object key) async {
      await tester.runAsync(library.listFonts);
      final store = _MemoryStore()
        ..updateSettings(const ReaderSettings(fontFileName: 'same.ttf'));
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderView(
            key: ValueKey(key),
            path: '/book.txt',
            title: 'book.txt',
            text: '본문',
            encoding: TextEncoding.utf8,
            store: store,
            pageIndexCache: cache,
            fontLibrary: library,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpFontLibrary(FontLibrary(fonts), 'before');
    await tester.runAsync(() async {
      await font.writeAsBytes([2]);
      await font.setLastModified(replacedModified);
    });
    await pumpFontLibrary(FontLibrary(fonts), 'after');

    expect(cache.loadSignatures.toSet(), hasLength(2));
  });

  testWidgets('문단 들여쓰기별 페이지 캐시와 페이지 본문을 분리한다', (tester) async {
    const text = '첫 문단\n둘째 문단';
    final cache = _MemoryPageIndexCache();

    Future<void> pumpIndent(int paragraphIndent) async {
      final store = _MemoryStore()
        ..updateSettings(
          ReaderSettings(
            mode: ReadingMode.page,
            paragraphIndent: paragraphIndent,
          ),
        );
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderView(
            key: ValueKey(paragraphIndent),
            path: '/book.txt',
            title: 'book.txt',
            text: text,
            encoding: TextEncoding.utf8,
            store: store,
            pageIndexCache: cache,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpIndent(0);
    await pumpIndent(2);

    expect(cache.loadSignatures.toSet(), hasLength(2));
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const Key('page-content-0')),
              matching: find.byWidgetPredicate(
                (widget) => widget is Text && widget.data == '　　첫 문단\n　　둘째 문단',
              ),
            ),
          )
          .data,
      '　　첫 문단\n　　둘째 문단',
    );
  });

  testWidgets('표시 설정에서 문단 들여쓰기를 닫을 때 적용한다', (tester) async {
    final store = _MemoryStore();
    await _pumpReader(tester, store, '첫 문단\n둘째 문단');
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('표시 설정'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('paragraph-indent-two')));
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('paragraph-indent-none')))
          .selected,
      isTrue,
    );
    await tester.tap(find.byKey(const Key('paragraph-indent-two')));
    expect(store.data.settings.paragraphIndent, 0);

    await _dismissSettings(tester);

    expect(store.data.settings.paragraphIndent, 2);
    expect(
      tester
          .widget<Text>(
            find
                .descendant(
                  of: find.byKey(const Key('scroll-selection-area')),
                  matching: find.byType(Text),
                )
                .first,
          )
          .data,
      '　　첫 문단\n　　둘째 문단',
    );
  });

  testWidgets('late wakelock enable is disabled after reader disposal', (
    tester,
  ) async {
    const channel =
        'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
    final enableReply = Completer<ByteData?>();
    final success = const StandardMessageCodec().encodeMessage(<Object?>[null]);
    var calls = 0;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMessageHandler(channel, (_) {
      calls++;
      return calls == 1 ? enableReply.future : Future.value(success);
    });
    addTearDown(() => messenger.setMockMessageHandler(channel, null));
    final store = _MemoryStore()
      ..updateSettings(const ReaderSettings(keepAwake: true));

    await _pumpReader(tester, store, 'text');
    expect(calls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    enableReply.complete(success);
    await tester.pump();

    expect(calls, 2);
  });

  testWidgets(
    'large scroll mode shares pagination and recalculates after resize',
    (tester) async {
      var paginationCalls = 0;
      final text = List.filled(300 * 1024, 'a').join();
      await tester.binding.setSurfaceSize(const Size(400, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderView(
            path: '/book.txt',
            title: 'book.txt',
            text: text,
            encoding: TextEncoding.utf8,
            store: _MemoryStore(),
            paginator:
                ({
                  required text,
                  required size,
                  required style,
                  required paragraphIndent,
                  onProgress,
                  onBatch,
                  onLayout,
                  isCancelled,
                }) async {
                  paginationCalls++;
                  return const [];
                },
          ),
        ),
      );
      await tester.pump();

      expect(paginationCalls, 1);

      await tester.binding.setSurfaceSize(const Size(700, 400));
      await tester.pumpAndSettle();

      expect(paginationCalls, 2);
    },
  );

  testWidgets(
    'large scroll mode indexes a bounded prefix until distant navigation',
    (tester) async {
      final text = List.filled(300 * 1024, 'a').join();
      final store = _MemoryStore();
      final producedPerCall = <int>[];

      Future<List<TextPage>> boundedPaginator({
        required String text,
        required Size size,
        required TextStyle style,
        required int paragraphIndent,
        ValueChanged<double>? onProgress,
        PaginationBatchCallback? onBatch,
        TextLayoutCallback? onLayout,
        bool Function()? isCancelled,
      }) async {
        final pages = <TextPage>[];
        while (pages.length < 80 && isCancelled?.call() != true) {
          final start = pages.length * 1000;
          final page = TextPage(start: start, end: start + 1000);
          pages.add(page);
          onBatch?.call([page]);
          onProgress?.call(page.end / text.length);
          await Future<void>.delayed(Duration.zero);
        }
        producedPerCall.add(pages.length);
        return pages;
      }

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderView(
            path: '/book.txt',
            title: 'book.txt',
            text: text,
            encoding: TextEncoding.utf8,
            store: store,
            paginator: boundedPaginator,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(producedPerCall, [32]);

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('위치 이동'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '60');
      await tester.tap(find.text('이동'));
      await tester.pumpAndSettle();

      expect(producedPerCall, [32, 80]);
      expect(store.document('/book.txt').offset, 59000);
    },
  );

  testWidgets('scroll and auto modes share exact page numbers', (tester) async {
    final line = '${List.filled(80, 'a').join()}\n';
    final text = List.filled(4000, line).join();
    final chunks = splitText(text, maxChars: 700);
    final targetOffset = chunks[200].start;
    final pages = [
      for (var start = 0; start < text.length; start += 100)
        TextPage(start: start, end: math.min(start + 100, text.length)),
    ];
    final store = _MemoryStore()
      ..updateSettings(const ReaderSettings(autoPageIntervalSeconds: 60))
      ..updateProgress(
        '/book.txt',
        offset: targetOffset,
        documentLength: text.length,
      );

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
    final pageLabel = '${pageForOffset(pages, targetOffset) + 1}';

    expect(
      tester.widget<Text>(find.byKey(const Key('page-indicator'))).data,
      pageLabel,
    );

    await _enableAutoMode(tester);

    expect(
      tester.widget<Text>(find.byKey(const Key('page-indicator'))).data,
      pageLabel,
    );
    expect(store.document('/book.txt').offset, targetOffset);
  });

  testWidgets('unindexed scroll position hides the estimated page number', (
    tester,
  ) async {
    final line = '${List.filled(80, 'a').join()}\n';
    final text = List.filled(4000, line).join();
    final targetOffset = splitText(text, maxChars: 700)[200].start;
    final pagination = Completer<List<TextPage>>();
    addTearDown(() {
      if (!pagination.isCompleted) pagination.complete(const []);
    });
    final store = _MemoryStore()
      ..updateProgress(
        '/book.txt',
        offset: targetOffset,
        documentLength: text.length,
      );

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
                required paragraphIndent,
                onProgress,
                onBatch,
                onLayout,
                isCancelled,
              }) => pagination.future,
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.widget<Text>(find.byKey(const Key('page-indicator'))).data,
      '계산 중',
    );
  });

  testWidgets('계산 중에도 페이지 번호로 즉시 이동한다', (tester) async {
    final text = List.generate(400, (index) => '문장 $index 가나다라\n').join();
    final exactPages = <TextPage>[
      for (var start = 0; start < text.length; start += 100)
        TextPage(start: start, end: math.min(start + 100, text.length)),
    ];
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
                required paragraphIndent,
                onProgress,
                onBatch,
                onLayout,
                isCancelled,
              }) {
                emitBatch = onBatch;
                onBatch?.call([exactPages.first]);
                return completion.future;
              },
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('위치 이동'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '5');
    await tester.tap(find.text('이동'));
    await tester.pumpAndSettle();

    expect(completion.isCompleted, isFalse);
    expect(store.document('/book.txt').offset, 0);
    expect(find.text('5페이지까지 계산하고 있습니다. 계산되는 즉시 이동합니다.'), findsOneWidget);

    emitBatch?.call(exactPages.sublist(1, 5));
    await tester.pump();
    await tester.pump();

    expect(store.document('/book.txt').offset, exactPages[4].start);
    expect(
      tester.widget<Text>(find.byKey(const Key('page-indicator'))).data,
      '5',
    );
    expect(find.textContaining('%'), findsNothing);
    final selectedOffset = store.document('/book.txt').offset;

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('현재 5페이지'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);

    completion.complete(exactPages);
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('위치 이동'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(store.document('/book.txt').offset, selectedOffset);
  });

  testWidgets('하단은 숫자만 표시하고 햄버거 메뉴는 페이지 문구를 유지한다', (tester) async {
    final store = _MemoryStore()
      ..updateSettings(const ReaderSettings(mode: ReadingMode.page));
    await _pumpReader(tester, store, _longText);
    await tester.pumpAndSettle();

    final indicator = tester.widget<Text>(
      find.byKey(const Key('page-indicator')),
    );
    expect(indicator.data, matches(RegExp(r'^\d+$')));
    expect(indicator.data, isNot(contains('페이지')));

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    expect(find.textContaining(RegExp(r'^현재 \d+페이지$')), findsOneWidget);
  });

  testWidgets('표시 설정에서 현재와 전체 페이지 표시를 선택하고 저장한다', (tester) async {
    final store = _MemoryStore()
      ..updateSettings(const ReaderSettings(mode: ReadingMode.page));
    await _pumpReader(tester, store, _longText);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('표시 설정'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('page-display-current-total')),
    );
    await tester.tap(find.byKey(const Key('page-display-current-total')));
    await _dismissSettings(tester);

    expect(store.data.settings.showTotalPages, isTrue);
    final indicator = tester.widget<Text>(
      find.byKey(const Key('page-indicator')),
    );
    expect(indicator.data, matches(RegExp(r'^\d+/\d+$')));
  });

  testWidgets('page mode uses the full reader viewport for pagination', (
    tester,
  ) async {
    final bottomSystemArea = FakeViewPadding(
      bottom: 32 * tester.view.devicePixelRatio,
    );
    tester.view.padding = bottomSystemArea;
    tester.view.viewPadding = bottomSystemArea;
    addTearDown(() {
      tester.view.resetPadding();
      tester.view.resetViewPadding();
    });
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
          paginator:
              ({
                required text,
                required size,
                required style,
                required paragraphIndent,
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
    expect(measuredSize?.height, pagerHeight);
    final padding = tester.widget<Padding>(
      find.byKey(const Key('page-content-0')),
    );
    expect((padding.padding as EdgeInsets).bottom, 0);
    expect(
      find.ancestor(
        of: find.byType(PageTurnView),
        matching: find.byType(SafeArea),
      ),
      findsNothing,
    );
  });

  testWidgets('page indicator occupies the bottom-right system gesture area', (
    tester,
  ) async {
    final bottomSystemArea = FakeViewPadding(
      bottom: 32 * tester.view.devicePixelRatio,
    );
    tester.view.padding = bottomSystemArea;
    tester.view.viewPadding = bottomSystemArea;
    addTearDown(() {
      tester.view.resetPadding();
      tester.view.resetViewPadding();
    });
    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final gestureTop =
        (tester.view.physicalSize.height - tester.view.viewPadding.bottom) /
        tester.view.devicePixelRatio;
    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;

    for (final mode in [ReadingMode.scroll, ReadingMode.page]) {
      final store = _MemoryStore()..updateSettings(ReaderSettings(mode: mode));
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpReader(tester, store, _longText);
      await tester.pumpAndSettle();

      final reader = mode == ReadingMode.scroll
          ? find.byType(ScrollablePositionedList)
          : find.byType(PageTurnView);
      final indicatorRect = tester.getRect(
        find.byKey(const Key('page-indicator')),
      );
      final readerRect = tester.getRect(reader);
      expect(
        readerRect.bottom,
        gestureTop,
        reason: '${mode.name}: reader=$readerRect indicator=$indicatorRect',
      );
      expect(indicatorRect.top, greaterThanOrEqualTo(gestureTop));
      expect(indicatorRect.bottom, lessThanOrEqualTo(screenHeight));
      expect(indicatorRect.right, greaterThan(screenWidth / 2));
      expect(
        find.ancestor(of: reader, matching: find.byType(SafeArea)),
        findsNothing,
      );
    }
  });

  testWidgets('page rendering repeats overlap without moving progress', (
    tester,
  ) async {
    const text = 'firstsecondthird';
    const pages = [
      TextPage(start: 0, end: 5),
      TextPage(start: 5, end: 11, displayStart: 0),
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
          paginator:
              ({
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

    await tester.drag(find.byType(PageTurnView), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(store.document('/book.txt').offset, 5);
    expect(find.text('firstsecond'), findsOneWidget);
  });

  testWidgets('tap reading mode ignores swipes and advances by tap', (
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
          mode: ReadingMode.tap,
          pageTurnDirection: PageTurnDirection.horizontal,
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
          paginator:
              ({
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

    await tester.drag(find.byType(PageTurnView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(store.document('/book.txt').offset, 0);

    final rect = tester.getRect(find.byType(PageTurnView));
    await tester.tapAt(Offset(rect.right - 20, rect.center.dy));
    await tester.pumpAndSettle();

    expect(store.document('/book.txt').offset, 5);
    expect(find.text('second'), findsOneWidget);
  });

  testWidgets('정확한 페이지 계산이 끝나면 추정값 대신 정확한 총 페이지 수를 쓴다', (tester) async {
    final text = List.filled(1000, '가').join();
    const pages = [
      TextPage(start: 0, end: 333),
      TextPage(start: 333, end: 666),
      TextPage(start: 666, end: 1000),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderView(
          path: '/book.txt',
          title: 'book.txt',
          text: text,
          encoding: TextEncoding.utf8,
          store: _MemoryStore(),
          paginator:
              ({
                required text,
                required size,
                required style,
                required paragraphIndent,
                onProgress,
                onBatch,
                onLayout,
                isCancelled,
              }) async => pages,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('위치 이동'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration?.hintText, '1~3');
  });

  testWidgets('이동창을 연 뒤 계산이 끝나면 최신 페이지 범위를 다시 확인한다', (tester) async {
    final text = List.filled(1000, '가').join();
    const exactPages = [
      TextPage(start: 0, end: 333),
      TextPage(start: 333, end: 666),
      TextPage(start: 666, end: 1000),
    ];
    final completion = Completer<List<TextPage>>();

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderView(
          path: '/book.txt',
          title: 'book.txt',
          text: text,
          encoding: TextEncoding.utf8,
          store: _MemoryStore(),
          paginator:
              ({
                required text,
                required size,
                required style,
                required paragraphIndent,
                onProgress,
                onBatch,
                onLayout,
                isCancelled,
              }) {
                onBatch?.call(const [TextPage(start: 0, end: 250)]);
                return completion.future;
              },
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('위치 이동'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).decoration?.hintText,
      '약 1~4 (추정)',
    );

    completion.complete(exactPages);
    await tester.pump();
    await tester.pump();
    await tester.enterText(find.byType(TextField), '4');
    await tester.tap(find.text('이동'));
    await tester.pumpAndSettle();

    expect(find.text('1~3 사이 페이지를 입력해 주세요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('비균일한 대형 파일도 요청한 1716페이지의 정확한 색인을 기다린다', (tester) async {
    const textLength = 1299500;
    const totalPages = 12995;
    const requestedPage = 1716;
    final text = List.filled(textLength, '가').join();
    final exactPages = <TextPage>[];
    var start = 0;
    for (var index = 0; index < 6095; index++) {
      final length = index < 8 ? 100 : 28;
      exactPages.add(TextPage(start: start, end: start + length));
      start += length;
    }
    final remainingStart = start;
    final remainingPages = totalPages - exactPages.length;
    final remainingCharacters = textLength - remainingStart;
    for (var index = 0; index < remainingPages; index++) {
      final end =
          remainingStart +
          ((index + 1) * remainingCharacters ~/ remainingPages);
      exactPages.add(TextPage(start: start, end: end));
      start = end;
    }
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
                required paragraphIndent,
                onProgress,
                onBatch,
                onLayout,
                isCancelled,
              }) {
                emitBatch = onBatch;
                onBatch?.call(exactPages.sublist(0, 8));
                return completion.future;
              },
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('위치 이동'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).decoration?.hintText,
      '약 1~$totalPages (추정)',
    );
    await tester.enterText(find.byType(TextField), '$requestedPage');
    await tester.tap(find.text('이동'));
    await tester.pumpAndSettle();

    expect(store.document('/book.txt').offset, 0);

    emitBatch?.call(exactPages.sublist(8, requestedPage));
    await tester.pump();
    await tester.pump();
    final exactRequestedOffset = exactPages[requestedPage - 1].start;
    expect(store.document('/book.txt').offset, exactRequestedOffset);
    expect(
      tester.widget<Text>(find.byKey(const Key('page-indicator'))).data,
      '$requestedPage',
    );

    completion.complete(exactPages);
    await tester.pumpAndSettle();
    expect(store.document('/book.txt').offset, exactRequestedOffset);
  });

  testWidgets('위치 이동창의 키보드와 취소는 페이지 계산을 다시 시작하지 않는다', (tester) async {
    var paginationCalls = 0;
    final text = List.filled(1000, '가').join();
    final pages = <TextPage>[
      for (var start = 0; start < text.length; start += 100)
        TextPage(start: start, end: math.min(start + 100, text.length)),
    ];
    final store = _MemoryStore()
      ..updateSettings(const ReaderSettings(mode: ReadingMode.page))
      ..updateProgress('/book.txt', offset: 500, documentLength: text.length);
    addTearDown(tester.view.resetViewInsets);

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
                required paragraphIndent,
                onProgress,
                onBatch,
                onLayout,
                isCancelled,
              }) async {
                paginationCalls++;
                return pages;
              },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(paginationCalls, 1);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('위치 이동'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();

    expect(paginationCalls, 1);
    expect(store.document('/book.txt').offset, 500);
  });

  testWidgets('계산이 끝나지 않아도 이미 색인된 페이지는 정확한 위치로 이동한다', (tester) async {
    final text = List.filled(1000, '가').join();
    const indexedPrefix = [
      TextPage(start: 0, end: 100),
      TextPage(start: 100, end: 200),
      TextPage(start: 200, end: 300),
    ];
    final completion = Completer<List<TextPage>>();
    final store = _MemoryStore();

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
                required paragraphIndent,
                onProgress,
                onBatch,
                onLayout,
                isCancelled,
              }) {
                onBatch?.call(indexedPrefix);
                return completion.future;
              },
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('위치 이동'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '2');
    await tester.tap(find.text('이동'));
    await tester.pump();

    expect(store.document('/book.txt').offset, 100);

    completion.complete(indexedPrefix);
    await tester.pump();
  });

  testWidgets('스크롤 본문은 여러 청크를 하나의 선택 영역으로 묶는다', (tester) async {
    final text = List.filled(70 * 1024, '가').join();
    final pages = <TextPage>[
      for (var start = 0; start < text.length; start += 50)
        TextPage(start: start, end: math.min(start + 50, text.length)),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderView(
          path: '/book.txt',
          title: 'book.txt',
          text: text,
          encoding: TextEncoding.utf8,
          store: _MemoryStore(),
          paginator:
              ({
                required text,
                required size,
                required style,
                required paragraphIndent,
                onProgress,
                onBatch,
                onLayout,
                isCancelled,
              }) async => pages,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final selectionArea = find.byKey(const Key('scroll-selection-area'));
    expect(selectionArea, findsOneWidget);
    expect(
      find.descendant(of: selectionArea, matching: find.byType(Text)),
      findsWidgets,
    );
    expect(
      find.descendant(of: selectionArea, matching: find.byType(SelectableText)),
      findsNothing,
    );
  });

  testWidgets('스크롤 위치는 보이는 청크의 화면 정렬값까지 복원한다', (tester) async {
    final text = List.filled(40 * 1024, '가').join();
    final store = _MemoryStore();
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Widget buildReader(Key key) => MaterialApp(
      home: ReaderView(
        key: key,
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
              required paragraphIndent,
              onProgress,
              onBatch,
              onLayout,
              isCancelled,
            }) async => [TextPage(start: 0, end: text.length)],
      ),
    );

    await tester.pumpWidget(buildReader(const ValueKey('first')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(ScrollablePositionedList),
      const Offset(0, -350),
    );
    await tester.pumpAndSettle();

    final saved = store.document('/book.txt');
    expect(saved.offset, greaterThan(0));
    expect(saved.scrollAlignment, greaterThan(0));
    expect(saved.scrollAlignment, lessThan(1));

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pumpWidget(buildReader(const ValueKey('restored')));
    await tester.pumpAndSettle();

    final restoredList = tester.widget<ScrollablePositionedList>(
      find.byType(ScrollablePositionedList),
    );
    expect(restoredList.initialScrollIndex, greaterThan(0));
    expect(restoredList.initialAlignment, closeTo(saved.scrollAlignment, .01));
  });

  testWidgets('대기 중 사용자가 스크롤하면 오래된 페이지 이동을 취소한다', (tester) async {
    const indexedPages = [
      TextPage(start: 0, end: 100),
      TextPage(start: 100, end: 200),
      TextPage(start: 200, end: 300),
      TextPage(start: 300, end: 400),
      TextPage(start: 400, end: 500),
    ];
    final store = _MemoryStore();
    final completion = Completer<List<TextPage>>();
    PaginationBatchCallback? emitBatch;
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderView(
          path: '/book.txt',
          title: 'book.txt',
          text: _longText,
          encoding: TextEncoding.utf8,
          store: store,
          paginator:
              ({
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
                onBatch?.call(indexedPages.take(1).toList());
                return completion.future;
              },
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('위치 이동'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '5');
    await tester.tap(find.text('이동'));
    await tester.pumpAndSettle();

    for (var index = 0; index < 5; index++) {
      await tester.drag(
        find.byType(ScrollablePositionedList),
        const Offset(0, -400),
      );
      await tester.pump();
    }
    final manualOffset = store.document('/book.txt').offset;

    emitBatch?.call(indexedPages.sublist(1));
    await tester.pump();
    await tester.pump();
    expect(store.document('/book.txt').offset, manualOffset);

    completion.complete(indexedPages);
    await tester.pump();
  });

  testWidgets('강제 인코딩마다 별도 페이지 캐시를 사용한다', (tester) async {
    const text = '같은길이본문';
    final cache = _MemoryPageIndexCache();
    var paginationCalls = 0;
    Future<List<TextPage>> paginator({
      required String text,
      required Size size,
      required TextStyle style,
      required int paragraphIndent,
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
                required paragraphIndent,
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

  testWidgets(
    'large page mode restores the saved offset before full indexing',
    (tester) async {
      final prefix = List.filled(300 * 1024, 'a').join();
      final text = '${prefix}TARGET${List.filled(1000, 'b').join()}';
      final targetOffset = prefix.length;
      final store = _MemoryStore()
        ..updateSettings(const ReaderSettings(mode: ReadingMode.page))
        ..updateProgress(
          '/book.txt',
          offset: targetOffset,
          documentLength: text.length,
        );
      final completion = Completer<List<TextPage>>();
      var windowCalls = 0;

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
                  required paragraphIndent,
                  onProgress,
                  onBatch,
                  onLayout,
                  isCancelled,
                }) => completion.future,
            windowPaginator:
                ({
                  required text,
                  required startOffset,
                  required size,
                  required style,
                  required paragraphIndent,
                  onLayout,
                  isCancelled,
                }) async {
                  windowCalls++;
                  return [
                    TextPage(start: startOffset, end: targetOffset),
                    TextPage(
                      start: targetOffset,
                      end: math.min(targetOffset + 32, text.length),
                    ),
                  ];
                },
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(windowCalls, 1);
      expect(completion.isCompleted, isFalse);
      expect(find.textContaining('TARGET'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      completion.complete(const []);
      await tester.pump();
    },
  );

  testWidgets('keeps many progressive delta batches unique', (tester) async {
    final text = List.generate(
      48,
      (index) => String.fromCharCode(0x100 + index),
    ).join();
    final pages = List.generate(
      text.length,
      (index) => TextPage(start: index, end: index + 1),
    );
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
                required paragraphIndent,
                onProgress,
                onBatch,
                onLayout,
                isCancelled,
              }) {
                emitBatch = onBatch;
                return completion.future;
              },
        ),
      ),
    );
    await tester.pump();

    for (final page in pages) {
      emitBatch?.call([page]);
    }
    await tester.pump();

    expect(
      tester.widget<PageTurnView>(find.byType(PageTurnView)).itemCount,
      pages.length,
    );

    completion.complete(pages);
    await tester.pump();
    await tester.pump();

    final pager = tester.widget<PageTurnView>(find.byType(PageTurnView));
    expect(pager.itemCount, pages.length);
    pager.onPageChanged(pages.length - 1);
    await tester.pumpAndSettle();
    expect(
      tester.widget<PageTurnView>(find.byType(PageTurnView)).index,
      pages.length - 1,
    );
    expect(find.text(text.substring(text.length - 1)), findsOneWidget);
  });

  testWidgets('계산 중에도 먼 검색 결과를 즉시 표시한다', (tester) async {
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
                required paragraphIndent,
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
    expect(find.textContaining('찾을본문'), findsWidgets);
    expect(completion.isCompleted, isFalse);

    emitBatch?.call([
      const TextPage(start: 4, end: 9),
      TextPage(start: 9, end: text.length),
    ]);
    await tester.pumpAndSettle();

    expect(find.textContaining('찾을본문'), findsWidgets);

    completion.complete([
      const TextPage(start: 0, end: 4),
      const TextPage(start: 4, end: 9),
      TextPage(start: 9, end: text.length),
    ]);
    await tester.pumpAndSettle();

    expect(find.textContaining('찾을본문'), findsWidgets);
  });

  testWidgets('검색 결과를 강조하고 다음과 이전 결과를 순환한다', (tester) async {
    const text = '앞 찾기 가운데 찾기 뒤';
    final store = _MemoryStore();
    await _pumpReader(tester, store, text);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('본문 검색'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '찾기');
    await tester.tap(find.text('검색'));
    await tester.pumpAndSettle();

    final first = text.indexOf('찾기');
    final second = text.indexOf('찾기', first + 1);
    expect(store.document('/book.txt').offset, first);
    expect(find.byKey(const Key('active-search-match')), findsOneWidget);
    expect(find.byKey(const Key('search-navigation-bar')), findsOneWidget);

    await tester.tap(find.byKey(const Key('search-next')));
    await tester.pumpAndSettle();
    expect(store.document('/book.txt').offset, second);

    await tester.tap(find.byKey(const Key('search-previous')));
    await tester.pumpAndSettle();
    expect(store.document('/book.txt').offset, first);

    await tester.tap(find.byKey(const Key('search-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('active-search-match')), findsNothing);
    expect(find.byKey(const Key('search-navigation-bar')), findsNothing);
  });

  testWidgets('새 이동은 완료가 늦은 검색 페이지 창을 취소한다', (tester) async {
    const text = '첫페이지둘째페이지찾을본문';
    final store = _MemoryStore()
      ..updateSettings(const ReaderSettings(mode: ReadingMode.page));
    final paginationCompletion = Completer<List<TextPage>>();
    final windowCompletion = Completer<List<TextPage>>();
    var windowStarted = false;

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
                required paragraphIndent,
                onProgress,
                onBatch,
                onLayout,
                isCancelled,
              }) {
                onBatch?.call(const [TextPage(start: 0, end: 4)]);
                return paginationCompletion.future;
              },
          windowPaginator:
              ({
                required text,
                required startOffset,
                required size,
                required style,
                required paragraphIndent,
                onLayout,
                isCancelled,
              }) {
                windowStarted = true;
                return windowCompletion.future;
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
    await tester.pump();
    expect(windowStarted, isTrue);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('위치 이동'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.enterText(find.byType(TextField), '1');
    await tester.tap(find.text('이동'));
    await tester.pump();
    expect(store.document('/book.txt').offset, 0);

    windowCompletion.complete([TextPage(start: 9, end: text.length)]);
    await tester.pump();
    await tester.pump();
    expect(store.document('/book.txt').offset, 0);

    paginationCompletion.complete([
      const TextPage(start: 0, end: 4),
      TextPage(start: 4, end: text.length),
    ]);
    await tester.pump();
  });

  testWidgets('계산 중에도 먼 북마크를 즉시 표시한다', (tester) async {
    const text = '첫페이지둘째페이지찾을본문';
    final store = _MemoryStore()
      ..updateSettings(const ReaderSettings(mode: ReadingMode.page))
      ..addBookmark(
        '/book.txt',
        const Bookmark(
          offset: 9,
          excerpt: '찾을본문',
          createdAt: '2026-07-15T00:00:00Z',
        ),
      );
    final completion = Completer<List<TextPage>>();

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
                required paragraphIndent,
                onProgress,
                onBatch,
                onLayout,
                isCancelled,
              }) {
                onBatch?.call(const [TextPage(start: 0, end: 4)]);
                return completion.future;
              },
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('북마크'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('찾을본문'));
    await tester.pumpAndSettle();

    expect(store.document('/book.txt').offset, 9);
    expect(find.textContaining('찾을본문'), findsWidgets);
    expect(completion.isCompleted, isFalse);

    completion.complete([
      const TextPage(start: 0, end: 4),
      const TextPage(start: 4, end: 9),
      TextPage(start: 9, end: text.length),
    ]);
    await tester.pumpAndSettle();

    expect(tester.widget<PageTurnView>(find.byType(PageTurnView)).index, 2);
    expect(find.text('찾을본문'), findsOneWidget);
  });

  testWidgets(
    'auto mode temporarily uses vertical pages and restores settings',
    (tester) async {
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
            paginator:
                ({
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
        tester
            .widget<SwitchListTile>(find.byKey(const Key('auto-mode-switch')))
            .value,
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
      await tester.pump(const Duration(milliseconds: 200));
      expect(store.document('/book.txt').offset, 5);

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('auto-mode-switch')));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ScrollablePositionedList), findsOneWidget);
    },
  );

  testWidgets('auto mode toggle preserves a distant scroll position', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final line = '${List.filled(80, 'x').join()}\n';
    final text = List.filled(4000, line).join();
    final chunks = splitText(text, maxChars: 700);
    final exactPages = [
      for (var start = 0; start < text.length; start += 100)
        TextPage(start: start, end: math.min(start + 100, text.length)),
    ];
    final pagination = Completer<List<TextPage>>();
    addTearDown(() {
      if (!pagination.isCompleted) pagination.complete(const []);
    });
    final store = _MemoryStore();

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
                required paragraphIndent,
                onProgress,
                onBatch,
                onLayout,
                isCancelled,
              }) => pagination.future,
          windowPaginator:
              ({
                required text,
                required startOffset,
                required size,
                required style,
                required paragraphIndent,
                onLayout,
                isCancelled,
              }) async => [
                for (
                  var start = startOffset;
                  start < math.min(startOffset + 2500, text.length);
                  start += 100
                )
                  TextPage(
                    start: start,
                    end: math.min(start + 100, text.length),
                  ),
              ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .widget<ScrollablePositionedList>(find.byType(ScrollablePositionedList))
        .itemScrollController!
        .jumpTo(index: chunks.length - 2);
    await tester.pumpAndSettle();
    final offset = store.document('/book.txt').offset;
    expect(
      tester.widget<Text>(find.byKey(const Key('page-indicator'))).data,
      '계산 중',
    );

    await _enableAutoMode(tester);

    expect(
      tester.widget<Text>(find.byKey(const Key('page-indicator'))).data,
      '계산 중',
    );
    expect(store.document('/book.txt').offset, offset);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('auto-mode-switch')));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(ScrollablePositionedList), findsOneWidget);
    expect(store.document('/book.txt').offset, offset);

    pagination.complete(exactPages);
    await tester.pumpAndSettle();
    tester
        .widget<ScrollablePositionedList>(find.byType(ScrollablePositionedList))
        .itemScrollController!
        .jumpTo(index: chunks.length ~/ 2);
    await tester.pumpAndSettle();
    final nextOffset = store.document('/book.txt').offset;
    final nextPage = pageForOffset(exactPages, nextOffset);

    await _enableAutoMode(tester);

    expect(
      tester.widget<PageTurnView>(find.byType(PageTurnView)).index,
      nextPage,
    );
    expect(store.document('/book.txt').offset, nextOffset);
  });

  testWidgets(
    'auto mode hides a stale page window while resolving the scroll position',
    (tester) async {
      final line = '${List.filled(80, 'x').join()}\n';
      var text = List.filled(4000, line).join();
      final chunks = splitText(text, maxChars: 700);
      final distantOffset = chunks[chunks.length - 2].start;
      text = text.replaceRange(0, 8, 'BEGIN!!!');
      text = text.replaceRange(distantOffset, distantOffset + 8, 'DISTANT!');
      final pagination = Completer<List<TextPage>>();
      final nearbyWindow = Completer<List<TextPage>>();
      addTearDown(() {
        if (!pagination.isCompleted) pagination.complete(const []);
        if (!nearbyWindow.isCompleted) nearbyWindow.complete(const []);
      });
      var windowCalls = 0;
      final store = _MemoryStore()
        ..updateSettings(const ReaderSettings(autoPageIntervalSeconds: 60))
        ..updateProgress(
          '/book.txt',
          offset: distantOffset,
          documentLength: text.length,
        );

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
                  required paragraphIndent,
                  onProgress,
                  onBatch,
                  onLayout,
                  isCancelled,
                }) => pagination.future,
            windowPaginator:
                ({
                  required text,
                  required startOffset,
                  required size,
                  required style,
                  required paragraphIndent,
                  onLayout,
                  isCancelled,
                }) {
                  windowCalls++;
                  if (windowCalls > 1) return nearbyWindow.future;
                  return Future.value([
                    TextPage(start: distantOffset - 100, end: distantOffset),
                    TextPage(
                      start: distantOffset,
                      end: math.min(distantOffset + 100, text.length),
                    ),
                  ]);
                },
          ),
        ),
      );
      await tester.pump();

      await _enableAutoMode(tester);

      expect(windowCalls, 1);
      expect(find.textContaining('DISTANT!'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('auto-mode-switch')));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      tester
          .widget<ScrollablePositionedList>(
            find.byType(ScrollablePositionedList),
          )
          .itemScrollController!
          .jumpTo(index: 0);
      await tester.pumpAndSettle();
      expect(store.document('/book.txt').offset, 0);

      await _enableAutoMode(tester, settle: false);

      expect(windowCalls, 2);
      expect(find.textContaining('DISTANT!'), findsNothing);
      expect(find.text('페이지를 계산하고 있습니다.'), findsOneWidget);
      expect(store.document('/book.txt').offset, 0);

      nearbyWindow.complete(const [
        TextPage(start: 0, end: 100),
        TextPage(start: 100, end: 200),
      ]);
      await tester.pumpAndSettle();

      expect(find.textContaining('BEGIN!!!'), findsOneWidget);
      expect(store.document('/book.txt').offset, 0);
    },
  );

  testWidgets('manual page turn restarts the full auto interval', (
    tester,
  ) async {
    final store = _MemoryStore()
      ..updateSettings(const ReaderSettings(autoPageIntervalSeconds: 5));
    await _pumpAutoReader(tester, store);
    await _enableAutoMode(tester);

    await tester.drag(find.byType(PageTurnView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(store.document('/book.txt').offset, 5);

    await tester.pump(const Duration(milliseconds: 4850));
    await tester.pump(const Duration(milliseconds: 200));
    expect(store.document('/book.txt').offset, 5);
    await tester.pump(const Duration(milliseconds: 200));
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
    addTearDown(() {
      if (!completion.isCompleted) completion.complete(pages);
    });
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
    await tester.pump(const Duration(milliseconds: 200));
    expect(store.document('/book.txt').offset, 5);
    completion.complete(pages);
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
    expect(find.text('세로 스크롤'), findsOneWidget);
    expect(find.text('스와이프'), findsOneWidget);
    expect(find.text('탭'), findsOneWidget);
    expect(find.text('페이지 넘김'), findsNothing);
    await tester.ensureVisible(find.text('스와이프'));
    await tester.tap(find.text('스와이프'));
    final red = find.byKey(const Key('background-red'));
    await tester.ensureVisible(red);
    await tester.enterText(red, '100');
    await _dismissSettings(tester);

    expect(store.data.settings.mode, ReadingMode.page);
    expect(store.data.settings.background.red, 100);
    expect(store.data.settings.background.green, 236);
  });

  testWidgets('display settings persist tap mode and both direction helper', (
    tester,
  ) async {
    final store = _MemoryStore();
    await _pumpReader(tester, store, _longText);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('표시 설정'));
    await tester.pumpAndSettle();

    expect(find.text('좌우 넘김'), findsOneWidget);
    expect(find.text('상하 넘김'), findsOneWidget);
    expect(find.text('둘 다'), findsOneWidget);
    expect(find.text('둘 다 모드에서는 탭 영역이 위/아래로 나뉩니다.'), findsNothing);
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('page-turn-horizontal')))
          .selected,
      isTrue,
    );
    await tester.ensureVisible(find.text('탭'));
    await tester.tap(find.text('탭'));
    await tester.ensureVisible(find.byKey(const Key('page-turn-both')));
    await tester.tap(find.byKey(const Key('page-turn-both')));
    await tester.pump();
    expect(find.text('둘 다 모드에서는 탭 영역이 위/아래로 나뉩니다.'), findsOneWidget);
    await _dismissSettings(tester);

    expect(store.data.settings.mode, ReadingMode.tap);
    expect(store.data.settings.pageTurnDirection, PageTurnDirection.both);
  });

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
    final totalPages = int.parse(field.decoration!.hintText!.substring(2));
    await tester.enterText(find.byType(TextField), '$totalPages');
    await tester.tap(find.text('이동'));
    await tester.pumpAndSettle();

    final jumpedOffset = store.document('/book.txt').offset;
    expect(jumpedOffset, greaterThan(0));

    for (var i = 0; i < 3; i++) {
      await tester.drag(
        find.byType(ScrollablePositionedList),
        const Offset(0, 400),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(store.document('/book.txt').offset, lessThan(jumpedOffset));
  });

  testWidgets('마우스 휠 스크롤도 페이지 이동 보호 상태를 해제한다', (tester) async {
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
    final totalPages = int.parse(field.decoration!.hintText!.substring(2));
    await tester.enterText(find.byType(TextField), '$totalPages');
    await tester.tap(find.text('이동'));
    await tester.pumpAndSettle();
    final jumpedOffset = store.document('/book.txt').offset;

    final reader = find.byType(ScrollablePositionedList);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(reader),
        scrollDelta: const Offset(0, -1800),
      ),
    );
    await tester.pumpAndSettle();

    expect(store.document('/book.txt').offset, lessThan(jumpedOffset));
  });

  testWidgets('비포인터 스크롤이 이동 뒤 저장 위치를 갱신한다', (tester) async {
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
    final totalPages = int.parse(field.decoration!.hintText!.substring(2));
    await tester.enterText(find.byType(TextField), '$totalPages');
    await tester.tap(find.text('이동'));
    await tester.pumpAndSettle();
    final jumpedOffset = store.document('/book.txt').offset;

    final list = tester.widget<ScrollablePositionedList>(
      find.byType(ScrollablePositionedList),
    );
    list.itemScrollController!.jumpTo(index: 0);
    await tester.pumpAndSettle();

    expect(store.document('/book.txt').offset, lessThan(jumpedOffset));
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

  testWidgets('북마크를 숫자 페이지로 안내하고 표시한다', (tester) async {
    final store = _MemoryStore();
    await _pumpReader(tester, store, _longText);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.bookmark_add_outlined));
    await tester.pump();
    expect(
      find.textContaining(RegExp(r'^\d+에 북마크를 저장했습니다\.$')),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('북마크'));
    await tester.pumpAndSettle();
    final bookmarkPage = tester.widget<Text>(
      find.byKey(const Key('bookmark-page-0')),
    );
    expect(bookmarkPage.data, matches(RegExp(r'^\d+$')));
  });

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
      find.text('세로 스크롤에서도 오토모드를 켜면 스와이프·상하 넘김으로 자동 전환됩니다.'),
      findsOneWidget,
    );
    await tester.tap(increase);
    await _dismissSettings(tester);

    expect(store.data.settings.autoPageIntervalSeconds, 6);
  });

  testWidgets(
    'drawer pauses auto mode and closing restarts the full interval',
    (tester) async {
      final store = _MemoryStore()
        ..updateSettings(const ReaderSettings(autoPageIntervalSeconds: 1));
      await _pumpAutoReader(tester, store);
      await _enableAutoMode(tester);

      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 200));
      expect(store.document('/book.txt').offset, 0);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 700));
      expect(store.document('/book.txt').offset, 0);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 200));
      expect(store.document('/book.txt').offset, 5);
    },
  );

  testWidgets(
    'inactive lifecycle pauses auto mode until a full interval resumes',
    (tester) async {
      final store = _MemoryStore()
        ..updateSettings(const ReaderSettings(autoPageIntervalSeconds: 1));
      await _pumpAutoReader(tester, store);
      await _enableAutoMode(tester);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 200));
      expect(store.document('/book.txt').offset, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 999));
      expect(store.document('/book.txt').offset, 0);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 200));
      expect(store.document('/book.txt').offset, 5);
    },
  );

  testWidgets('reaching the last page turns auto mode off', (tester) async {
    final store = _MemoryStore()
      ..updateSettings(const ReaderSettings(autoPageIntervalSeconds: 1));
    await _pumpAutoReader(tester, store, pageCount: 2);
    await _enableAutoMode(tester);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('마지막 페이지입니다. 오토모드를 종료했습니다.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('auto-mode-switch')))
          .value,
      isFalse,
    );
  });

  testWidgets('all drawer actions keep auto mode paused while open', (
    tester,
  ) async {
    final store = _MemoryStore()
      ..updateSettings(const ReaderSettings(autoPageIntervalSeconds: 1));
    await _pumpAutoReader(tester, store);
    await _enableAutoMode(tester);

    for (final label in ['위치 이동', '본문 검색', '북마크', '표시 설정', '파일 정보']) {
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 200));
      expect(store.document('/book.txt').offset, 0, reason: label);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }
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

    expect(store.data.settings.fontSize, 20.4);
    expect(store.data.settings.lineHeight, 1.66);
    expect(store.data.settings.horizontalPadding, 20.4);
    expect(find.text('적용'), findsNothing);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('font-size-increase')))
          .visualDensity,
      VisualDensity.compact,
    );

    await _dismissSettings(tester);

    expect(store.data.settings.fontSize, 21);
    expect(store.data.settings.lineHeight, 1.6);
    expect(store.data.settings.horizontalPadding, 21);
  });

  testWidgets('closing unchanged display settings is a no-op', (tester) async {
    var notifications = 0;
    var paginationCalls = 0;
    const text = '본문';
    final store = _MemoryStore()
      ..updateSettings(
        const ReaderSettings(
          mode: ReadingMode.page,
          fontSize: 20.4,
          lineHeight: 1.66,
          horizontalPadding: 20.4,
        ),
      )
      ..addListener(() => notifications++);

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
                required paragraphIndent,
                onProgress,
                onBatch,
                onLayout,
                isCancelled,
              }) async {
                paginationCalls++;
                final pages = [TextPage(start: 0, end: text.length)];
                onBatch?.call(pages);
                return pages;
              },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final callsBefore = paginationCalls;

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('표시 설정'));
    await tester.pumpAndSettle();
    expect(find.text('적용'), findsNothing);

    await _dismissSettings(tester);

    expect(notifications, 0);
    expect(paginationCalls, callsBefore);
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

  testWidgets('표시 설정에서 로컬 글꼴을 가져와 미리보기와 본문에 적용한다', (tester) async {
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('geulbom_font_ui'),
    ))!;
    addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
    final source = File('${root.path}${Platform.pathSeparator}나눔명조.ttf');
    await tester.runAsync(() => source.writeAsBytes([1, 2, 3]));
    final library = FontLibrary(
      Directory('${root.path}${Platform.pathSeparator}fonts'),
      registerFont: (_, _) async {},
    );
    final store = _MemoryStore();
    await _pumpReader(
      tester,
      store,
      '본문',
      fontLibrary: library,
      pickFont: () async => source.path,
    );

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('표시 설정'));
    await _pumpUntil(
      tester,
      () => find.text('로컬 글꼴 가져오기').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('로컬 글꼴 가져오기'));
    await _pumpUntil(tester, () => find.text('나눔명조').evaluate().isNotEmpty);

    expect(find.text('나눔명조'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('font-preview')))
          .style
          ?.fontFamily,
      fontFamilyFor('나눔명조.ttf'),
    );
    expect(await tester.runAsync(source.exists), isTrue);
    expect(
      await tester.runAsync(() => library.findFont('나눔명조.ttf')),
      isNotNull,
    );

    await _dismissSettings(tester);

    expect(store.data.settings.fontFileName, '나눔명조.ttf');
    expect(
      tester
          .widget<Text>(
            find
                .descendant(
                  of: find.byKey(const Key('scroll-selection-area')),
                  matching: find.byType(Text),
                )
                .first,
          )
          .style
          ?.fontFamily,
      fontFamilyFor('나눔명조.ttf'),
    );
  });

  testWidgets('지원하지 않는 글꼴 파일은 한국어 오류를 표시한다', (tester) async {
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('geulbom_bad_font_ui'),
    ))!;
    addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
    final source = File('${root.path}${Platform.pathSeparator}font.txt');
    await tester.runAsync(() => source.writeAsString('text'));
    final library = FontLibrary(
      Directory('${root.path}${Platform.pathSeparator}fonts'),
      registerFont: (_, _) async {},
    );
    await _pumpReader(
      tester,
      _MemoryStore(),
      '본문',
      fontLibrary: library,
      pickFont: () async => source.path,
    );

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('표시 설정'));
    await _pumpUntil(
      tester,
      () => find.text('로컬 글꼴 가져오기').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('로컬 글꼴 가져오기'));
    await _pumpUntil(
      tester,
      () => find.text('지원하는 글꼴은 TTF 또는 OTF 파일입니다.').evaluate().isNotEmpty,
    );

    expect(find.text('지원하는 글꼴은 TTF 또는 OTF 파일입니다.'), findsOneWidget);
    expect(await tester.runAsync(library.listFonts), isEmpty);
  });

  testWidgets('글꼴 선택기 오류는 한국어 가져오기 오류를 표시한다', (tester) async {
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('geulbom_picker_error_ui'),
    ))!;
    addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
    final library = FontLibrary(
      Directory('${root.path}${Platform.pathSeparator}fonts'),
      registerFont: (_, _) async {},
    );
    await _pumpReader(
      tester,
      _MemoryStore(),
      '본문',
      fontLibrary: library,
      pickFont: () async => throw StateError('picker failed'),
    );

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('표시 설정'));
    await _pumpUntil(
      tester,
      () => find.text('로컬 글꼴 가져오기').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('로컬 글꼴 가져오기'));
    await _pumpUntil(
      tester,
      () => find.text('글꼴을 가져오지 못했습니다.').evaluate().isNotEmpty,
    );

    expect(find.text('글꼴을 가져오지 못했습니다.'), findsOneWidget);
  });

  testWidgets('가져온 글꼴을 확인 후 삭제하고 시스템 기본값으로 복구한다', (tester) async {
    _mockWakelock(tester);
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('geulbom_delete_font_ui'),
    ))!;
    addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
    final source = File('${root.path}${Platform.pathSeparator}고딕.otf');
    await tester.runAsync(() => source.writeAsBytes([1]));
    final library = FontLibrary(
      Directory('${root.path}${Platform.pathSeparator}fonts'),
      registerFont: (_, _) async {},
    );
    final imported = (await tester.runAsync(
      () => library.importFont(source.path),
    ))!;
    final store = _TrackingStore()
      ..updateSettings(ReaderSettings(fontFileName: imported.fileName));
    await _pumpReader(tester, store, '본문', fontLibrary: library);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('표시 설정'));
    await _pumpUntil(
      tester,
      () => find
          .byKey(Key('delete-font-${imported.fileName}'))
          .evaluate()
          .isNotEmpty,
    );
    await tester.tap(find.byKey(Key('delete-font-${imported.fileName}')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await _pumpUntil(
      tester,
      () => !imported.file.existsSync() && store.saveCalls > 0,
    );

    expect(await tester.runAsync(imported.file.exists), isFalse);
    expect(store.data.settings.fontFileName, isNull);
    expect(store.saveCalls, 1);
    expect(find.text('고딕'), findsNothing);
  });

  testWidgets('초안에서만 선택한 글꼴 삭제도 저장 설정을 기본값으로 복구한다', (tester) async {
    _mockWakelock(tester);
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('geulbom_delete_draft_font_ui'),
    ))!;
    addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
    final savedSource = File('${root.path}${Platform.pathSeparator}saved.otf');
    final draftSource = File('${root.path}${Platform.pathSeparator}draft.otf');
    await tester.runAsync(() async {
      await savedSource.writeAsBytes([1]);
      await draftSource.writeAsBytes([2]);
    });
    final library = _DelayedDeleteFontLibrary(
      Directory('${root.path}${Platform.pathSeparator}fonts'),
    );
    final saved = (await tester.runAsync(
      () => library.importFont(savedSource.path),
    ))!;
    final drafted = (await tester.runAsync(
      () => library.importFont(draftSource.path),
    ))!;
    final store = _TrackingStore()
      ..updateSettings(ReaderSettings(fontFileName: saved.fileName));
    await _pumpReader(tester, store, '본문', fontLibrary: library);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('표시 설정'));
    await _pumpUntil(
      tester,
      () => find
          .byKey(Key('font-option-${drafted.fileName}'))
          .evaluate()
          .isNotEmpty,
    );
    await tester.tap(find.byKey(Key('font-option-${drafted.fileName}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('delete-font-${drafted.fileName}')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await _pumpUntil(tester, () => library.deleteStarted);

    store.updateSettings(
      ReaderSettings(
        mode: ReadingMode.page,
        background: const RgbColor(1, 2, 3),
        foreground: const RgbColor(4, 5, 6),
        fontFileName: saved.fileName,
        fontSize: 31,
        lineHeight: 2.1,
        horizontalPadding: 33,
      ),
    );
    library.completeDelete();
    await _pumpUntil(tester, () => !drafted.file.existsSync());

    final latest = store.data.settings;
    expect(latest.fontFileName, isNull);
    expect(latest.mode, ReadingMode.page);
    expect(latest.background, const RgbColor(1, 2, 3));
    expect(latest.foreground, const RgbColor(4, 5, 6));
    expect(latest.fontSize, 31);
    expect(latest.lineHeight, 2.1);
    expect(latest.horizontalPadding, 33);
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('font-option-system')))
          .selected,
      isTrue,
    );
    expect(await tester.runAsync(saved.file.exists), isTrue);
    expect(store.saveCalls, greaterThanOrEqualTo(1));
  });

  testWidgets('선택 글꼴 삭제 중 설정창을 닫아도 기본값을 즉시 저장한다', (tester) async {
    _mockWakelock(tester);
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('geulbom_delayed_delete_ui'),
    ))!;
    addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
    final source = File('${root.path}${Platform.pathSeparator}명조.otf');
    await tester.runAsync(() => source.writeAsBytes([1]));
    final library = _DelayedDeleteFontLibrary(
      Directory('${root.path}${Platform.pathSeparator}fonts'),
    );
    final imported = (await tester.runAsync(
      () => library.importFont(source.path),
    ))!;
    final store = _TrackingStore()
      ..updateSettings(ReaderSettings(fontFileName: imported.fileName));
    await _pumpReader(tester, store, '본문', fontLibrary: library);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('표시 설정'));
    await _pumpUntil(
      tester,
      () => find
          .byKey(Key('delete-font-${imported.fileName}'))
          .evaluate()
          .isNotEmpty,
    );
    await tester.tap(find.byKey(Key('delete-font-${imported.fileName}')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await _pumpUntil(tester, () => library.deleteStarted);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    library.completeDelete();
    await _pumpUntil(tester, () => !imported.file.existsSync());

    expect(store.data.settings.fontFileName, isNull);
    expect(store.saveCalls, 1);
  });

  testWidgets('글꼴 삭제 중 바뀐 최신 표시 설정과 글꼴을 보존한다', (tester) async {
    _mockWakelock(tester);
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('geulbom_delete_race_ui'),
    ))!;
    addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
    final source = File('${root.path}${Platform.pathSeparator}old.otf');
    final replacementSource = File(
      '${root.path}${Platform.pathSeparator}replacement.otf',
    );
    await tester.runAsync(() async {
      await source.writeAsBytes([1]);
      await replacementSource.writeAsBytes([2]);
    });
    final library = _DelayedDeleteFontLibrary(
      Directory('${root.path}${Platform.pathSeparator}fonts'),
    );
    final imported = (await tester.runAsync(
      () => library.importFont(source.path),
    ))!;
    final replacement = (await tester.runAsync(
      () => library.importFont(replacementSource.path),
    ))!;
    final store = _TrackingStore()
      ..updateSettings(ReaderSettings(fontFileName: imported.fileName));
    await _pumpReader(tester, store, '본문', fontLibrary: library);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('표시 설정'));
    await _pumpUntil(
      tester,
      () => find
          .byKey(Key('delete-font-${imported.fileName}'))
          .evaluate()
          .isNotEmpty,
    );
    await tester.tap(find.byKey(Key('delete-font-${imported.fileName}')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await _pumpUntil(tester, () => library.deleteStarted);

    store.updateSettings(
      ReaderSettings(
        mode: ReadingMode.page,
        background: const RgbColor(1, 2, 3),
        foreground: const RgbColor(4, 5, 6),
        fontFileName: replacement.fileName,
        fontSize: 31,
        lineHeight: 2.1,
        horizontalPadding: 33,
      ),
    );
    library.completeDelete();
    await _pumpUntil(tester, () => !imported.file.existsSync());

    final latest = store.data.settings;
    expect(latest.fontFileName, replacement.fileName);
    expect(latest.mode, ReadingMode.page);
    expect(latest.background, const RgbColor(1, 2, 3));
    expect(latest.foreground, const RgbColor(4, 5, 6));
    expect(latest.fontSize, 31);
    expect(latest.lineHeight, 2.1);
    expect(latest.horizontalPadding, 33);
    expect(store.saveCalls, 0);
  });

  testWidgets('글꼴 삭제 후 설정 저장 실패는 삭제 성공과 구분해 안내한다', (tester) async {
    _mockWakelock(tester);
    final root = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('geulbom_delete_save_error_ui'),
    ))!;
    addTearDown(() => tester.runAsync(() => root.delete(recursive: true)));
    final source = File('${root.path}${Platform.pathSeparator}고딕.otf');
    await tester.runAsync(() => source.writeAsBytes([1]));
    final library = FontLibrary(
      Directory('${root.path}${Platform.pathSeparator}fonts'),
      registerFont: (_, _) async {},
    );
    final imported = (await tester.runAsync(
      () => library.importFont(source.path),
    ))!;
    final store = _TrackingStore(failNextSave: true)
      ..updateSettings(ReaderSettings(fontFileName: imported.fileName));
    await _pumpReader(tester, store, '본문', fontLibrary: library);

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.text('표시 설정'));
    await _pumpUntil(
      tester,
      () => find
          .byKey(Key('delete-font-${imported.fileName}'))
          .evaluate()
          .isNotEmpty,
    );
    await tester.tap(find.byKey(Key('delete-font-${imported.fileName}')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await _pumpUntil(
      tester,
      () => find.text('글꼴은 삭제했지만 설정을 저장하지 못했습니다.').evaluate().isNotEmpty,
    );

    expect(await tester.runAsync(imported.file.exists), isFalse);
    expect(store.data.settings.fontFileName, isNull);
    expect(find.text('글꼴을 삭제하지 못했습니다.'), findsNothing);
  });
}

void _mockWakelock(WidgetTester tester) {
  const channel =
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
  final success = const StandardMessageCodec().encodeMessage(<Object?>[null]);
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMessageHandler(channel, (_) async => success);
  addTearDown(() => messenger.setMockMessageHandler(channel, null));
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('비동기 UI 작업이 완료되지 않았습니다.');
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
  }
  await tester.pumpAndSettle();
}

Future<void> _dismissSettings(WidgetTester tester) async {
  expect(find.text('적용'), findsNothing);
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

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
        paginator:
            ({
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

Future<void> _enableAutoMode(WidgetTester tester, {bool settle = true}) async {
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('auto-mode-switch')));
  await tester.binding.handlePopRoute();
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(kThemeAnimationDuration);
    await tester.pump();
  }
}

Future<void> _pumpReader(
  WidgetTester tester,
  _MemoryStore store,
  String text, {
  FontLibrary? fontLibrary,
  Future<String?> Function()? pickFont,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ReaderView(
        path: '/book.txt',
        title: 'book.txt',
        text: text,
        encoding: TextEncoding.utf8,
        store: store,
        fontLibrary: fontLibrary,
        pickFont: pickFont ?? pickFontFile,
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

class _TrackingStore extends _MemoryStore {
  _TrackingStore({this.failNextSave = false});

  int saveCalls = 0;
  bool failNextSave;

  @override
  Future<void> save() async {
    saveCalls++;
    if (failNextSave) {
      failNextSave = false;
      throw StateError('save failed');
    }
  }
}

class _DelayedDeleteFontLibrary extends FontLibrary {
  _DelayedDeleteFontLibrary(super.directory)
    : super(registerFont: (_, _) async {});

  final _deleteCompletion = Completer<void>();
  var deleteStarted = false;

  void completeDelete() => _deleteCompletion.complete();

  @override
  Future<void> deleteFont(ImportedFont font) async {
    deleteStarted = true;
    await _deleteCompletion.future;
    await super.deleteFont(font);
  }
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
