import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geulbom/page_index_cache.dart';
import 'package:geulbom/text_paginator.dart';

void main() {
  late Directory directory;
  late PageIndexCache cache;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('geulbom_page_cache');
    cache = PageIndexCache(directory: directory);
  });

  tearDown(() => directory.delete(recursive: true));

  test('round-trips page starts through an injected directory', () async {
    const pages = [TextPage(start: 0, end: 4), TextPage(start: 4, end: 9)];

    await cache.save(signature: 'book-a', textLength: 9, pages: pages);
    await cache.save(
      signature: 'book-a',
      textLength: 9,
      pages: const [TextPage(start: 0, end: 3), TextPage(start: 3, end: 9)],
    );
    final restored = await PageIndexCache(
      directory: directory,
    ).load(signature: 'book-a', textLength: 9);

    expect(directory.listSync().whereType<File>(), hasLength(1));
    expect(restored, isNotNull);
    expect(restored!.map((page) => page.start), [0, 3]);
    expect(restored.map((page) => page.end), [3, 9]);
  });

  test('rejects a record whose stored signature is stale', () async {
    await cache.save(
      signature: 'book-a',
      textLength: 9,
      pages: const [TextPage(start: 0, end: 9)],
    );
    final file = directory.listSync().whereType<File>().single;
    final record =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    record['signature'] = 'book-b';
    await file.writeAsString(jsonEncode(record));

    expect(await cache.load(signature: 'book-a', textLength: 9), isNull);
  });

  test('rejects malformed, unordered, and out-of-range starts', () async {
    await cache.save(
      signature: 'book-a',
      textLength: 9,
      pages: const [TextPage(start: 0, end: 9)],
    );
    final file = directory.listSync().whereType<File>().single;
    final record =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;

    for (final starts in <Object>[
      <int>[],
      [1],
      [0, 0],
      [0, 5, 4],
      [0, 9],
      [0, -1],
      [0, 4.5],
    ]) {
      record['starts'] = starts;
      await file.writeAsString(jsonEncode(record));
      expect(
        await cache.load(signature: 'book-a', textLength: 9),
        isNull,
        reason: 'accepted starts $starts',
      );
    }
  });

  test('returns null instead of throwing for malformed JSON', () async {
    await cache.save(
      signature: 'book-a',
      textLength: 9,
      pages: const [TextPage(start: 0, end: 9)],
    );
    final file = directory.listSync().whereType<File>().single;
    await file.writeAsString('{broken');

    expect(await cache.load(signature: 'book-a', textLength: 9), isNull);
  });

  test('retains at most eight records and keeps the latest save', () async {
    for (var index = 0; index < 9; index++) {
      await cache.save(
        signature: 'book-$index',
        textLength: 9,
        pages: const [TextPage(start: 0, end: 9)],
      );
    }

    expect(directory.listSync().whereType<File>(), hasLength(8));
    expect(await cache.load(signature: 'book-8', textLength: 9), isNotNull);
  });
}
