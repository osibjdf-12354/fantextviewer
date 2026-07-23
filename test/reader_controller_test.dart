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
}
