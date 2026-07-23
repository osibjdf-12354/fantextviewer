import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fantextviewer/app_store.dart';
import 'package:fantextviewer/font_library.dart';
import 'package:fantextviewer/main.dart';
import 'package:fantextviewer/models.dart';
import 'package:fantextviewer/strings.dart';

void main() {
  test('저장한 글꼴 파일이 없으면 시스템 기본 글꼴로 복구한다', () async {
    final root = await Directory.systemTemp.createTemp(
      'fantextviewer_missing_font',
    );
    addTearDown(() => root.delete(recursive: true));
    final store = _MemoryStore()
      ..updateSettings(const ReaderSettings(fontFileName: 'missing.ttf'));

    await restoreSelectedFont(
      store,
      FontLibrary(Directory('${root.path}${Platform.pathSeparator}fonts')),
    );

    expect(store.data.settings.fontFileName, isNull);
  });

  test('글꼴 목록 조회가 실패해도 시스템 기본 글꼴로 시작한다', () async {
    final store = _MemoryStore()
      ..updateSettings(const ReaderSettings(fontFileName: 'saved.ttf'));

    await restoreSelectedFont(
      store,
      _FailingCatalogFontLibrary(Directory('unused-fonts')),
    );

    expect(store.data.settings.fontFileName, isNull);
  });

  test('기본 글꼴 복구 저장이 실패해도 복구된 설정으로 시작한다', () async {
    final root = await Directory.systemTemp.createTemp(
      'fantextviewer_font_save_failure',
    );
    addTearDown(() => root.delete(recursive: true));
    final store = _FailingSaveStore()
      ..updateSettings(const ReaderSettings(fontFileName: 'missing.ttf'));

    await restoreSelectedFont(
      store,
      FontLibrary(Directory('${root.path}${Platform.pathSeparator}fonts')),
    );

    expect(store.data.settings.fontFileName, isNull);
  });

  testWidgets('앱이 한국어 제목과 파일 탐색 버튼으로 시작한다', (tester) async {
    final store = _MemoryStore();

    await tester.pumpWidget(FanTextViewerApp(store: store));

    expect(find.text(AppStrings.appName), findsOneWidget);
    expect(find.byIcon(Icons.folder_open), findsWidgets);
    expect(find.text(AppStrings.noRecentFiles), findsOneWidget);
  });

  testWidgets('corrupted state exposes its backup and recovery import action', (
    tester,
  ) async {
    final store = _MemoryStore()..recoveryFile = File('state.json.broken');

    await tester.pumpWidget(FanTextViewerApp(store: store));

    expect(find.text('저장 상태 복구'), findsOneWidget);
    expect(find.text('상태 파일 가져오기'), findsOneWidget);
    expect(find.text(AppStrings.exportRecoveryFile), findsOneWidget);
    expect(find.textContaining(store.recoveryFile!.path), findsOneWidget);
  });

  testWidgets('system text import failure is shown without an uncaught error', (
    tester,
  ) async {
    final store = _MemoryStore();

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          store: store,
          textFilePicker: () async =>
              throw PlatformException(code: 'import_failed'),
        ),
      ),
    );
    await tester.tap(find.byTooltip(AppStrings.systemFilePicker));
    await tester.pumpAndSettle();

    expect(
      find.textContaining(AppStrings.textFileImportFailed),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

class _MemoryStore extends AppStore {
  _MemoryStore() : super(File('unused'));

  @override
  Future<void> save() async {}
}

class _FailingSaveStore extends _MemoryStore {
  @override
  Future<void> save() async => throw StateError('save failed');
}

class _FailingCatalogFontLibrary extends FontLibrary {
  _FailingCatalogFontLibrary(super.directory);

  @override
  Future<List<ImportedFont>> listFonts() async {
    throw FileSystemException('catalog failed');
  }
}
