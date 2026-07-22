import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geulbom/text_paginator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('moves a boundary newline to the previous page', () async {
    const text = 'first line\nsecond line\nthird line';

    final pages = await paginateText(
      text: text,
      size: const Size(500, 24),
      style: const TextStyle(fontSize: 20, height: 1),
    );

    expect(pages.length, greaterThan(1));
    expect(text.codeUnitAt(pages[1].start), isNot(0x0a));
    expect(
      pages.map((page) => text.substring(page.start, page.end)).join(),
      text,
    );
  });

  test('keeps one intentional newline from a consecutive pair', () async {
    const text = 'first line\n\nsecond line\nthird line';

    final pages = await paginateText(
      text: text,
      size: const Size(500, 20),
      style: const TextStyle(fontSize: 20, height: 1),
    );

    expect(text.substring(pages.first.end), startsWith('\nsecond line'));
  });

  test('window pagination uses the same boundary newline ownership', () async {
    const text = 'first line\n\nsecond line\nthird line';

    final pages = await paginateTextWindow(
      text: text,
      startOffset: 0,
      size: const Size(500, 20),
      style: const TextStyle(fontSize: 20, height: 1),
    );

    expect(text.substring(pages.first.end), startsWith('\nsecond line'));
    expect(
      pages.map((page) => text.substring(page.start, page.end)).join(),
      text,
    );
  });

  test('페이지 범위가 원문을 중복 없이 모두 덮는다', () async {
    final text = List.filled(200, '가나다라마바사아자차카타파하 ').join();

    final pages = await paginateText(
      text: text,
      size: const Size(240, 320),
      style: const TextStyle(fontSize: 20, height: 1.5),
    );

    expect(pages.length, greaterThan(1));
    expect(pages.first.start, 0);
    expect(pages.last.end, text.length);
    for (var index = 1; index < pages.length; index++) {
      expect(pages[index - 1].end, pages[index].start);
    }
    expect(pageForOffset(pages, pages[1].start), 1);
  });

  test(
    'paragraph indentation changes layout but preserves source ranges',
    () async {
      final text = List.filled(20, '가나다라\n').join();
      const size = Size(80, 40);
      const style = TextStyle(fontSize: 20, height: 1);

      final plain = await paginateText(text: text, size: size, style: style);
      final indented = await paginateText(
        text: text,
        size: size,
        style: style,
        paragraphIndent: 2,
      );

      expect(indented.length, greaterThan(plain.length));
      expect(indented.first.start, 0);
      expect(indented.last.end, text.length);
      for (var index = 1; index < indented.length; index++) {
        expect(indented[index - 1].end, indented[index].start);
      }
      expect(
        indented.map((page) => text.substring(page.start, page.end)).join(),
        text,
      );
    },
  );

  test('문서 밖 위치는 첫 페이지와 마지막 페이지로 제한한다', () async {
    final pages = await paginateText(
      text: List.filled(100, '가나다라마바사아자차카타파하 ').join(),
      size: const Size(160, 120),
      style: const TextStyle(fontSize: 20, height: 1.5),
    );

    expect(pageForOffset(pages, -10), 0);
    expect(pageForOffset(pages, 999999), pages.length - 1);
  });

  test('빈 문서는 페이지가 없다', () async {
    expect(
      await paginateText(
        text: '',
        size: const Size(240, 320),
        style: const TextStyle(fontSize: 20),
      ),
      isEmpty,
    );
  });

  test('페이지 계산 취소 요청이 오면 남은 본문 계산을 멈춘다', () async {
    final text = List.filled(1000, '가나다라마바사아자차카타파하 ').join();
    var cancellationChecks = 0;

    final pages = await paginateText(
      text: text,
      size: const Size(160, 120),
      style: const TextStyle(fontSize: 20, height: 1.5),
      isCancelled: () => cancellationChecks++ >= 3,
    );

    expect(pages, isNotEmpty);
    expect(pages.last.end, lessThan(text.length));
  });

  test('emits new pages in eight-page batches', () async {
    final batches = <List<TextPage>>[];

    final pages = await paginateText(
      text: List.filled(80, 'batch pagination text ').join(),
      size: const Size(160, 120),
      style: const TextStyle(fontSize: 20, height: 1.5),
      onBatch: batches.add,
    );

    expect(batches.length, greaterThan(1));
    for (final batch in batches.take(batches.length - 1)) {
      expect(batch, hasLength(8));
    }
    expect(batches.last, hasLength(inInclusiveRange(1, 8)));
    expect(batches.expand((batch) => batch), orderedEquals(pages));
  });

  test('yields to the event loop after at most two pages', () async {
    var eventLoopTurn = false;
    Timer.run(() => eventLoopTurn = true);

    final pages = await paginateText(
      text: List.filled(1000, 'responsive pagination text ').join(),
      size: const Size(160, 120),
      style: const TextStyle(fontSize: 20, height: 1.5),
      isCancelled: () => eventLoopTurn,
    );

    expect(pages, hasLength(2));
  });

  test('uses the previous page length as the next first probe', () async {
    final layoutLengths = <int>[];

    await paginateText(
      text: List.filled(400, 'adaptive pagination text ').join(),
      size: const Size(240, 320),
      style: const TextStyle(fontSize: 20, height: 1.5),
      onLayout: layoutLengths.add,
    );

    expect(layoutLengths.first, 4096);
    expect(layoutLengths.skip(1), isNotEmpty);
    expect(layoutLengths[1], lessThan(2048));
  });

  test(
    'stable text usually needs one layout probe per page after warmup',
    () async {
      final layoutLengths = <int>[];
      final pages = await paginateText(
        text: List.filled(500, '가나다라마바사아자차카타파하 ').join(),
        size: const Size(160, 120),
        style: const TextStyle(fontSize: 20, height: 1.5),
        onLayout: layoutLengths.add,
      );

      expect(pages.length, greaterThan(20));
      expect(layoutLengths.length, lessThan(pages.length * 1.5));
    },
  );

  test('bounds layout probes when page density changes', () async {
    final layoutLengths = <int>[];
    final text =
        '${List.filled(100, '\n').join()}${List.filled(12000, 'i').join()}';

    final pages = await paginateText(
      text: text,
      size: const Size(2000, 2000),
      style: const TextStyle(fontSize: 20),
      onLayout: layoutLengths.add,
    );

    expect(pages.length, greaterThan(1));
    expect(layoutLengths, hasLength(lessThan(20)));
  });

  test('cancels while growing a dense-page probe', () async {
    final layoutLengths = <int>[];
    final text =
        '${List.filled(100, '\n').join()}${List.filled(12000, 'i').join()}';
    var cancelled = false;

    final pages = await paginateText(
      text: text,
      size: const Size(2000, 2000),
      style: const TextStyle(fontSize: 20),
      onLayout: (length) {
        layoutLengths.add(length);
        if (length < 4096) cancelled = true;
      },
      isCancelled: () => cancelled,
    );

    expect(pages, hasLength(1));
    expect(pages.single.end, lessThan(text.length));
    expect(layoutLengths, hasLength(2));
  });

  test('임의 문서의 페이지 수와 위치를 추정한다', () {
    final pages = List.generate(
      8,
      (index) => TextPage(start: index * 250, end: (index + 1) * 250),
    );

    expect(
      estimatedPageCount(250000, pages, fallbackCharactersPerPage: 300),
      1000,
    );
    expect(
      estimatedPageForOffset(125000, textLength: 250000, totalPages: 1000),
      500,
    );
  });

  test('추정 페이지와 위치를 문서 경계로 제한한다', () {
    expect(estimatedPageForOffset(-1, textLength: 1000, totalPages: 10), 1);
    expect(estimatedPageForOffset(5000, textLength: 1000, totalPages: 10), 10);
  });

  test('원문 중간에서 제한된 수의 페이지 구간을 계산한다', () async {
    final text = List.generate(300, (index) => '줄 $index 가나다라\n').join();

    final pages = await paginateTextWindow(
      text: text,
      startOffset: text.length ~/ 2,
      size: const Size(240, 180),
      style: const TextStyle(fontSize: 18),
      maxPages: 12,
    );

    expect(pages, isNotEmpty);
    expect(pages.length, lessThanOrEqualTo(12));
    expect(pages.first.start, greaterThan(0));
    expect(pages.last.end, lessThanOrEqualTo(text.length));
    for (var index = 1; index < pages.length; index++) {
      expect(pages[index - 1].end, pages[index].start);
    }
  });

  test(
    'window pagination preserves a leading newline at offset zero',
    () async {
      final pages = await paginateTextWindow(
        text: '\nfirst line\nsecond line',
        startOffset: 0,
        size: const Size(240, 180),
        style: const TextStyle(fontSize: 18),
      );

      expect(pages.first.start, 0);
    },
  );

  test(
    'window pagination aligns only within the previous 4096 chars',
    () async {
      final text = 'outside\n${List.filled(4100, 'x').join()}\ninside';
      final insideNewline = text.lastIndexOf('\n');

      final nearbyPages = await paginateTextWindow(
        text: text,
        startOffset: text.length - 2,
        size: const Size(240, 180),
        style: const TextStyle(fontSize: 18),
      );
      final distantPages = await paginateTextWindow(
        text: text,
        startOffset: insideNewline - 1,
        size: const Size(240, 180),
        style: const TextStyle(fontSize: 18),
      );

      expect(nearbyPages.first.start, insideNewline + 1);
      expect(distantPages.first.start, insideNewline - 1);
    },
  );
}
