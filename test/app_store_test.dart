import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geulbom/app_store.dart';
import 'package:geulbom/models.dart';

void main() {
  test('설정과 문서 상태를 JSON 파일에서 복원한다', () async {
    final directory = await Directory.systemTemp.createTemp('geulbom_store');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}state.json');
    final store = AppStore(file);
    store.updateSettings(
      const ReaderSettings(mode: ReadingMode.page, fontSize: 24),
    );
    store.updateProgress('/books/a.txt', offset: 42, scrollAlignment: .25);
    store.addBookmark(
      '/books/a.txt',
      const Bookmark(
        offset: 42,
        excerpt: '본문',
        createdAt: '2026-07-15T00:00:00.000Z',
      ),
    );
    await store.save();

    final restored = AppStore(file);
    await restored.load();

    expect(restored.data.settings.fontSize, 24);
    expect(restored.data.settings.background, const RgbColor(196, 236, 187));
    expect(restored.data.settings.foreground, const RgbColor(32, 48, 32));
    expect(restored.document('/books/a.txt').offset, 42);
    expect(restored.document('/books/a.txt').bookmarks.single.excerpt, '본문');
  });

  test('북마크 위치 중복을 막고 읽기 위치를 문서 길이로 제한한다', () {
    final store = AppStore(File('unused'));
    const bookmark = Bookmark(
      offset: 9,
      excerpt: '가나다',
      createdAt: '2026-07-15T00:00:00.000Z',
    );

    store.addBookmark('/a.txt', bookmark);
    store.addBookmark('/a.txt', bookmark);
    store.updateProgress('/a.txt', offset: 99, documentLength: 10);

    expect(store.document('/a.txt').bookmarks, hasLength(1));
    expect(store.document('/a.txt').offset, 10);
  });

  test('RGB 채널은 0부터 255까지만 받는다', () {
    expect(RgbColor.tryCreate(196, 236, 187), const RgbColor(196, 236, 187));
    expect(RgbColor.tryCreate(-1, 0, 0), isNull);
    expect(RgbColor.tryCreate(0, 256, 0), isNull);
  });

  test('persists and clears the selected font filename', () {
    final imported = const ReaderSettings().copyWith(fontFileName: '하늘명조.otf');

    expect(imported.fontFileName, '하늘명조.otf');
    expect(ReaderSettings.fromJson(imported.toJson()).fontFileName, '하늘명조.otf');
    expect(imported.copyWith(fontFileName: null).fontFileName, isNull);
    expect(const ReaderSettings().fontFileName, isNull);
  });

  test('absent font filename in JSON defaults to null', () {
    expect(ReaderSettings.fromJson(const {}).fontFileName, isNull);
  });

  test('copyWith preserves the selected font when omitted', () {
    const settings = ReaderSettings(fontFileName: 'saved.otf');

    expect(settings.copyWith(fontSize: 24).fontFileName, 'saved.otf');
  });

  test('persists page indicator format and defaults to current page', () {
    const enabled = ReaderSettings(showTotalPages: true);

    expect(enabled.toJson()['showTotalPages'], true);
    expect(ReaderSettings.fromJson(enabled.toJson()).showTotalPages, isTrue);
    expect(ReaderSettings.fromJson(const {}).showTotalPages, isFalse);
    expect(enabled.copyWith(fontSize: 24).showTotalPages, isTrue);
  });

  test(
    'persists paragraph indentation and defaults invalid values to none',
    () {
      const settings = ReaderSettings(paragraphIndent: 2);

      expect(settings.toJson()['paragraphIndent'], 2);
      expect(ReaderSettings.fromJson(settings.toJson()).paragraphIndent, 2);
      expect(ReaderSettings.fromJson(const {}).paragraphIndent, 0);
      for (final invalid in [-1, 1.5, 3]) {
        expect(
          ReaderSettings.fromJson({'paragraphIndent': invalid}).paragraphIndent,
          0,
        );
      }
      expect(settings.copyWith(fontSize: 24).paragraphIndent, 2);
    },
  );

  test('persists auto page interval and defaults invalid values to five', () {
    const settings = ReaderSettings(autoPageIntervalSeconds: 12);

    expect(
      ReaderSettings.fromJson(settings.toJson()).autoPageIntervalSeconds,
      12,
    );
    expect(ReaderSettings.fromJson(const {}).autoPageIntervalSeconds, 5);
    for (final invalid in [0, 61, -1, '5']) {
      expect(
        ReaderSettings.fromJson({
          'autoPageIntervalSeconds': invalid,
        }).autoPageIntervalSeconds,
        5,
      );
    }
    expect(
      settings.copyWith(autoPageIntervalSeconds: 30).autoPageIntervalSeconds,
      30,
    );
  });

  test('persists page turn direction and defaults to horizontal', () {
    const settings = ReaderSettings(pageTurnDirection: PageTurnDirection.both);

    expect(settings.toJson()['pageTurnDirection'], 'both');
    expect(
      ReaderSettings.fromJson(settings.toJson()).pageTurnDirection,
      PageTurnDirection.both,
    );
    expect(
      ReaderSettings.fromJson(const {}).pageTurnDirection,
      PageTurnDirection.horizontal,
    );
    expect(
      settings.copyWith(fontSize: 24).pageTurnDirection,
      PageTurnDirection.both,
    );
  });

  test('persists page turn animation and defaults to enabled', () {
    const disabled = ReaderSettings(pageTurnAnimationEnabled: false);

    expect(disabled.toJson()['pageTurnAnimationEnabled'], isFalse);
    expect(
      ReaderSettings.fromJson(disabled.toJson()).pageTurnAnimationEnabled,
      isFalse,
    );
    expect(ReaderSettings.fromJson(const {}).pageTurnAnimationEnabled, isTrue);
    expect(disabled.copyWith(fontSize: 24).pageTurnAnimationEnabled, isFalse);
  });

  test('persists tap mode without changing saved page mode', () {
    const tap = ReaderSettings(mode: ReadingMode.tap);

    expect(tap.toJson()['mode'], 'tap');
    expect(ReaderSettings.fromJson(tap.toJson()).mode, ReadingMode.tap);
    expect(
      ReaderSettings.fromJson(const {'mode': 'page'}).mode,
      ReadingMode.page,
    );
    expect(ReaderSettings.fromJson(const {}).mode, ReadingMode.scroll);
  });

  test('progress updates do not notify home listeners', () {
    final store = AppStore(File('unused'));
    var notifications = 0;
    store.addListener(() => notifications++);

    store.updateProgress('/book.txt', offset: 42, documentLength: 100);

    expect(store.document('/book.txt').offset, 42);
    expect(notifications, 0);
  });

  test(
    'writes the current schema and loads legacy state without one',
    () async {
      final directory = await Directory.systemTemp.createTemp('geulbom_schema');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}${Platform.pathSeparator}state.json');
      await file.writeAsString('''
{
  "settings": {"fontSize": 24},
  "documents": {
    "/legacy.txt": {"path": "/wrong.txt", "offset": 7}
  }
}
''');

      final store = AppStore(file);
      await store.load();
      await store.save();

      final saved = await file.readAsString();
      expect(
        saved,
        contains('"schemaVersion":${AppData.currentSchemaVersion}'),
      );
      expect(store.document('/legacy.txt').path, '/legacy.txt');
      expect(store.document('/legacy.txt').offset, 7);
    },
  );

  test('invalid persisted values are replaced or clamped safely', () {
    final settings = ReaderSettings.fromJson({
      'fontSize': double.nan,
      'lineHeight': double.infinity,
      'horizontalPadding': -100,
      'background': {'red': 'bad', 'green': 999, 'blue': null},
      'foreground': 'bad',
      'keepAwake': 'yes',
    });
    final document = DocumentState.fromJson({
      'path': '/book.txt',
      'offset': -12,
      'scrollAlignment': 9,
      'fileSize': -1,
      'bookmarks': [
        {'offset': -4, 'excerpt': 123, 'createdAt': null},
        {'offset': 8, 'excerpt': 'valid', 'createdAt': 'now'},
      ],
    });

    expect(settings.fontSize, 20);
    expect(settings.lineHeight, 1.65);
    expect(settings.horizontalPadding, 8);
    expect(settings.background, const RgbColor(196, 236, 187));
    expect(settings.foreground, const RgbColor(32, 48, 32));
    expect(settings.keepAwake, isFalse);
    expect(document.offset, 0);
    expect(document.scrollAlignment, 1);
    expect(document.fileSize, isNull);
    expect(document.bookmarks, hasLength(1));
    expect(document.bookmarks.single.offset, 8);
    expect(document.bookmarks.single.excerpt, 'valid');
  });

  test('save captures a snapshot before the first asynchronous wait', () async {
    final directory = await Directory.systemTemp.createTemp('geulbom_snapshot');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}state.json');
    final store = AppStore(file)
      ..updateSettings(const ReaderSettings(fontSize: 24));

    final save = store.save();
    store.updateSettings(const ReaderSettings(fontSize: 30));
    await save;

    final restored = AppStore(file);
    await restored.load();
    expect(restored.data.settings.fontSize, 24);
  });

  test(
    'overlapping saves are serialized and the latest request wins',
    () async {
      final directory = await Directory.systemTemp.createTemp('geulbom_serial');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}${Platform.pathSeparator}state.json');
      final store = AppStore(file);

      store.updateSettings(const ReaderSettings(fontSize: 24));
      final first = store.save();
      store.updateSettings(const ReaderSettings(fontSize: 30));
      final second = store.save();
      await Future.wait([first, second]);

      final restored = AppStore(file);
      await restored.load();
      expect(restored.data.settings.fontSize, 30);
      expect(
        directory
            .listSync()
            .whereType<File>()
            .where((entry) => entry.path.contains('.tmp'))
            .toList(),
        isEmpty,
      );
    },
  );

  test('each corrupted state is preserved in a separate backup', () async {
    final directory = await Directory.systemTemp.createTemp(
      'geulbom_broken_unique',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}state.json');

    await file.writeAsString('{first');
    await AppStore(file).load();
    await file.writeAsString('{second');
    await AppStore(file).load();

    final backups = directory
        .listSync()
        .whereType<File>()
        .where((entry) => entry.path.contains('.broken.'))
        .toList();
    expect(backups, hasLength(2));
    expect(
      backups.map((entry) => entry.readAsStringSync()),
      containsAll(['{first', '{second']),
    );
  });

  test('save failures are returned to every caller', () async {
    final directory = await Directory.systemTemp.createTemp(
      'geulbom_save_error',
    );
    addTearDown(() => directory.delete(recursive: true));
    final parentFile = File(
      '${directory.path}${Platform.pathSeparator}not-a-directory',
    );
    await parentFile.writeAsString('occupied');
    final store = AppStore(
      File('${parentFile.path}${Platform.pathSeparator}state.json'),
    );

    await expectLater(store.save(), throwsA(isA<FileSystemException>()));
    await expectLater(store.save(), throwsA(isA<FileSystemException>()));
  });

  test('손상된 저장 파일을 보존하고 기본값으로 복구한다', () async {
    final directory = await Directory.systemTemp.createTemp('geulbom_broken');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}state.json');
    await file.writeAsString('{broken');

    final store = AppStore(file);
    await store.load();

    expect(store.data.settings.background, const RgbColor(196, 236, 187));
    expect(
      directory.listSync().whereType<File>().any(
        (entry) => entry.path.contains('.broken.'),
      ),
      isTrue,
    );
  });
}
