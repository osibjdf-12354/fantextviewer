import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geulbom/text_paginator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    var calculatedPages = 0;

    final pages = await paginateText(
      text: text,
      size: const Size(160, 120),
      style: const TextStyle(fontSize: 20, height: 1.5),
      onProgress: (_) => calculatedPages++,
      isCancelled: () => calculatedPages >= 3,
    );

    expect(pages, hasLength(3));
    expect(pages.last.end, lessThan(text.length));
  });
}
