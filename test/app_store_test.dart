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

  test('손상된 저장 파일을 보존하고 기본값으로 복구한다', () async {
    final directory = await Directory.systemTemp.createTemp('geulbom_broken');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}state.json');
    await file.writeAsString('{broken');

    final store = AppStore(file);
    await store.load();

    expect(store.data.settings.background, const RgbColor(196, 236, 187));
    expect(File('${file.path}.broken').existsSync(), isTrue);
  });
}
