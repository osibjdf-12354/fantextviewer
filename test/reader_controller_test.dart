import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geulbom/app_store.dart';
import 'package:geulbom/models.dart';
import 'package:geulbom/reader_controller.dart';

void main() {
  test('owns and clamps reader settings and position', () {
    final store = AppStore(File('unused'))
      ..updateSettings(const ReaderSettings(fontSize: 24))
      ..updateProgress(
        '/book.txt',
        offset: 40,
        scrollAlignment: .25,
        documentLength: 100,
      );
    final controller = ReaderController(
      store: store,
      path: '/book.txt',
      textLength: 100,
    );
    addTearDown(controller.dispose);

    expect(controller.settings.fontSize, 24);
    expect(controller.offset, 40);
    expect(controller.scrollAlignment, .25);

    controller.updateOffset(120, scrollAlignment: 2);
    expect(controller.offset, 100);
    expect(controller.scrollAlignment, 1);
    expect(store.document('/book.txt').offset, 100);
    expect(store.document('/book.txt').scrollAlignment, 1);
  });

  test('debounces changes and flush persists the latest snapshot', () async {
    final directory = await Directory.systemTemp.createTemp(
      'geulbom_controller',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}state.json');
    final store = AppStore(file);
    final controller = ReaderController(
      store: store,
      path: '/book.txt',
      textLength: 100,
      saveDelay: const Duration(hours: 1),
    );
    addTearDown(controller.dispose);

    controller.updateOffset(10, scrollAlignment: .1);
    controller.updateOffset(20, scrollAlignment: .2);
    controller.applySettings(const ReaderSettings(fontSize: 30));
    await controller.flush();

    final restored = AppStore(file);
    await restored.load();
    expect(restored.document('/book.txt').offset, 20);
    expect(restored.document('/book.txt').scrollAlignment, .2);
    expect(restored.data.settings.fontSize, 30);
  });

  test('notifies only when reader-owned values actually change', () {
    final store = AppStore(File('unused'));
    final controller = ReaderController(
      store: store,
      path: '/book.txt',
      textLength: 100,
    );
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.updateOffset(0);
    controller.applySettings(const ReaderSettings());
    expect(notifications, 0);

    controller.updateOffset(1);
    controller.applySettings(const ReaderSettings(fontSize: 24));
    expect(notifications, 2);
  });

  test('search traverses forward and backward with wrapping', () {
    const text = '하나 찾기 둘 찾기 셋';
    final store = AppStore(File('unused'));
    final controller = ReaderController(
      store: store,
      path: '/book.txt',
      textLength: text.length,
      text: text,
    );
    addTearDown(controller.dispose);

    expect(controller.startSearch('찾기')?.start, 3);
    expect(controller.nextSearchResult()?.start, 8);
    expect(controller.nextSearchResult()?.start, 3);
    expect(controller.previousSearchResult()?.start, 8);
    expect(controller.activeSearchMatch?.length, 2);

    controller.clearSearch();
    expect(controller.activeSearchMatch, isNull);
    expect(controller.searchQuery, isEmpty);
  });

  test('search reports no match without moving the reading position', () {
    const text = '검색할 본문';
    final store = AppStore(File('unused'))
      ..updateProgress('/book.txt', offset: 4, documentLength: text.length);
    final controller = ReaderController(
      store: store,
      path: '/book.txt',
      textLength: text.length,
      text: text,
    );
    addTearDown(controller.dispose);

    expect(controller.startSearch('없음'), isNull);
    expect(controller.offset, 4);
    expect(controller.searchQuery, '없음');
    expect(controller.activeSearchMatch, isNull);
  });

  test('pagination progress notifies only the narrow activity listenable', () {
    final controller = ReaderController(
      store: AppStore(File('unused')),
      path: '/book.txt',
      textLength: 10,
    );
    addTearDown(controller.dispose);
    var controllerNotifications = 0;
    var activityNotifications = 0;
    controller.addListener(() => controllerNotifications++);
    controller.paginationActivity.addListener(() => activityNotifications++);

    controller.updatePaginationProgress(.5);
    controller.notifyPaginationChanged();

    expect(controllerNotifications, 0);
    expect(activityNotifications, 2);
    expect(controller.paginationActivity.value.progress, .5);
  });

  testWidgets('owns automatic page timing, pauses, and lifecycle state', (
    tester,
  ) async {
    final controller = ReaderController(
      store: AppStore(File('unused')),
      path: '/book.txt',
      textLength: 10,
    );
    addTearDown(controller.dispose);
    var advances = 0;

    expect(controller.autoMode, isFalse);
    expect(controller.canAutoAdvance, isFalse);

    controller.setAutoMode(true);
    controller.scheduleAutoAdvance(
      const Duration(seconds: 2),
      () => advances++,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(advances, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(advances, 1);

    controller.pauseAuto();
    controller.scheduleAutoAdvance(
      const Duration(seconds: 1),
      () => advances++,
    );
    await tester.pump(const Duration(seconds: 1));
    expect(controller.canAutoAdvance, isFalse);
    expect(advances, 1);

    controller.resumeAuto();
    controller.setAppActive(false);
    expect(controller.canAutoAdvance, isFalse);
    controller.setAppActive(true);
    expect(controller.canAutoAdvance, isTrue);

    controller.scheduleAutoAdvance(
      const Duration(seconds: 1),
      () => advances++,
    );
    controller.setAutoMode(false);
    await tester.pump(const Duration(seconds: 1));
    expect(advances, 1);
  });
}
