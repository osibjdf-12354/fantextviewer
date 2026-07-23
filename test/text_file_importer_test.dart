import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fantextviewer/app_store.dart';
import 'package:fantextviewer/text_file_importer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Android picker returns the durable path produced by the host',
    () async {
      const channel = MethodChannel('test/text-file-importer');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return '/data/user/0/app/files/imported_texts/id/novel.txt';
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final importer = TextFileImporter(
        channel: channel,
        isAndroid: true,
        fallbackPicker: () async => throw StateError('fallback used'),
      );

      final path = await importer.pick();

      expect(path, '/data/user/0/app/files/imported_texts/id/novel.txt');
      expect(calls.single.method, 'importTextFile');
    },
  );

  test(
    'non-Android picker keeps the platform file selector fallback',
    () async {
      final importer = TextFileImporter(
        isAndroid: false,
        fallbackPicker: () async => '/tmp/novel.txt',
      );

      expect(await importer.pick(), '/tmp/novel.txt');
    },
  );

  test('legacy cache imports move their complete saved state once', () async {
    const channel = MethodChannel('test/text-file-promotion');
    final directory = await Directory.systemTemp.createTemp(
      'fantextviewer_import_promotion',
    );
    addTearDown(() => directory.delete(recursive: true));
    final stateFile = File(
      '${directory.path}${Platform.pathSeparator}state.json',
    );
    final store = AppStore(stateFile)
      ..touchRecent(
        '/data/user/0/app/cache/file_selector/novel.txt',
        openedAt: DateTime.utc(2026, 1, 1),
      )
      ..updateProgress(
        '/data/user/0/app/cache/file_selector/novel.txt',
        offset: 42,
        documentLength: 100,
      );
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'promoteLegacyImport') {
            return '/data/user/0/app/files/imported_texts/legacy/novel.txt';
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final importer = TextFileImporter(channel: channel, isAndroid: true);

    await promoteLegacyTextImports(store, importer: importer);

    expect(calls.single.method, 'promoteLegacyImport');
    expect(calls.single.arguments, {
      'path': '/data/user/0/app/cache/file_selector/novel.txt',
    });
    expect(
      store.data.documents,
      isNot(contains('/data/user/0/app/cache/file_selector/novel.txt')),
    );
    final moved = store.document(
      '/data/user/0/app/files/imported_texts/legacy/novel.txt',
    );
    expect(moved.offset, 42);
    expect(await stateFile.exists(), isTrue);
  });
}
