import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fantextviewer/page_index_cache.dart';
import 'package:fantextviewer/text_paginator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late PageIndexCache cache;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'fantextviewer_page_cache',
    );
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

  test('round-trips page display starts', () async {
    const pages = [
      TextPage(start: 0, end: 4),
      TextPage(start: 4, end: 9, displayStart: 2),
    ];

    await cache.save(signature: 'book-a', textLength: 9, pages: pages);
    final restored = await cache.load(signature: 'book-a', textLength: 9);

    expect(restored, isNotNull);
    expect(restored!.map((page) => page.displayStart), [0, 2]);
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
    final quietCache = PageIndexCache(directory: directory, onError: (_, _) {});
    await quietCache.save(
      signature: 'book-a',
      textLength: 9,
      pages: const [TextPage(start: 0, end: 9)],
    );
    final file = directory.listSync().whereType<File>().single;
    await file.writeAsString('{broken');

    expect(await quietCache.load(signature: 'book-a', textLength: 9), isNull);
  });

  test(
    'reports malformed cache diagnostics without failing the reader',
    () async {
      final errors = <Object>[];
      cache = PageIndexCache(
        directory: directory,
        onError: (error, _) => errors.add(error),
      );
      await cache.save(
        signature: 'book-a',
        textLength: 9,
        pages: const [TextPage(start: 0, end: 9)],
      );
      final file = directory.listSync().whereType<File>().single;
      await file.writeAsString('{broken');

      expect(await cache.load(signature: 'book-a', textLength: 9), isNull);
      expect(errors, hasLength(1));
      expect(errors.single, isA<FormatException>());
    },
  );

  test(
    'default cache use reports failures instead of swallowing them',
    () async {
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previous);
      await cache.save(
        signature: 'book-a',
        textLength: 9,
        pages: const [TextPage(start: 0, end: 9)],
      );
      final file = directory.listSync().whereType<File>().single;
      await file.writeAsString('{broken');

      expect(await cache.load(signature: 'book-a', textLength: 9), isNull);
      expect(reported, hasLength(1));
      expect(reported.single.exception, isA<FormatException>());
    },
  );

  test(
    'stores a cache schema and rejects records from another schema',
    () async {
      await cache.save(
        signature: 'book-a',
        textLength: 9,
        pages: const [TextPage(start: 0, end: 9)],
      );
      final file = directory.listSync().whereType<File>().single;
      final record =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(record['schemaVersion'], PageIndexCache.currentSchemaVersion);

      record['schemaVersion'] = -1;
      await file.writeAsString(jsonEncode(record));
      expect(await cache.load(signature: 'book-a', textLength: 9), isNull);
    },
  );

  test('loads a valid 1.1.9 cache without a schema version', () async {
    await cache.save(
      signature: 'book-a',
      textLength: 9,
      pages: const [TextPage(start: 0, end: 4), TextPage(start: 4, end: 9)],
    );
    final file = directory.listSync().whereType<File>().single;
    final record = jsonDecode(await file.readAsString()) as Map<String, dynamic>
      ..remove('schemaVersion');
    await file.writeAsString(jsonEncode(record));

    final restored = await cache.load(signature: 'book-a', textLength: 9);

    expect(restored, isNotNull);
    expect(restored!.map((page) => page.start), [0, 4]);
  });

  test('rejects malformed page display starts', () async {
    await cache.save(
      signature: 'book-a',
      textLength: 9,
      pages: const [
        TextPage(start: 0, end: 3),
        TextPage(start: 3, end: 6, displayStart: 1),
        TextPage(start: 6, end: 9, displayStart: 4),
      ],
    );
    final file = directory.listSync().whereType<File>().single;
    final record =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;

    for (final displayStarts in <Object?>[
      null,
      <int>[],
      [0, 1],
      [0, 4, 4],
      [0, 1, 2],
    ]) {
      record['displayStarts'] = displayStarts;
      await file.writeAsString(jsonEncode(record));
      expect(
        await cache.load(signature: 'book-a', textLength: 9),
        isNull,
        reason: 'accepted display starts $displayStarts',
      );
    }
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

  test(
    'default cache records are written under the temporary directory',
    () async {
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final methods = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            methods.add(call.method);
            return directory.path;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      await PageIndexCache().save(
        signature: 'temporary-book',
        textLength: 9,
        pages: const [TextPage(start: 0, end: 9)],
      );

      expect(methods, ['getTemporaryDirectory']);
      expect(directory.listSync().whereType<File>(), hasLength(1));
    },
  );
}
