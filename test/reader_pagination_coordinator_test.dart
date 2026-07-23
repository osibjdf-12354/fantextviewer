import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fantextviewer/app_store.dart';
import 'package:fantextviewer/models.dart';
import 'package:fantextviewer/reader_controller.dart';
import 'package:fantextviewer/reader_pagination_coordinator.dart';
import 'package:fantextviewer/text_document.dart';
import 'package:fantextviewer/text_paginator.dart';

void main() {
  testWidgets(
    'far page jump publishes a provisional page before local layout completes',
    (tester) async {
      final text = List.filled(10000, 'a').join();
      final store = AppStore(File('unused-reader-state.json'))
        ..updateSettings(const ReaderSettings(mode: ReadingMode.page));
      final controller = ReaderController(
        store: store,
        path: '/book.txt',
        textLength: text.length,
        text: text,
      );
      final fullPagination = Completer<List<TextPage>>();
      final localPagination = Completer<List<TextPage>>();
      var offset = 0;
      var viewChanges = 0;

      late final ReaderPaginationCoordinator coordinator;
      coordinator = ReaderPaginationCoordinator(
        text: text,
        path: '/book.txt',
        encoding: TextEncoding.utf8,
        fileSize: text.length,
        modified: DateTime.utc(2026, 7, 24),
        contentFingerprint: 'test-fingerprint',
        pageIndexCache: null,
        paginator:
            ({
              required text,
              required size,
              required style,
              required paragraphIndent,
              onProgress,
              onBatch,
              onLayout,
              isCancelled,
            }) {
              onBatch?.call(const [TextPage(start: 0, end: 100)]);
              return fullPagination.future;
            },
        windowPaginator:
            ({
              required text,
              required startOffset,
              required size,
              required style,
              required paragraphIndent,
              onLayout,
              isCancelled,
            }) => localPagination.future,
        readerController: controller,
        settings: () => store.data.settings,
        currentOffset: () => offset,
        activeMode: () => ReadingMode.page,
        fallbackCharactersPerPage: () => 100,
        onViewChanged: () => viewChanges++,
        onJumpToOffset: (value) => offset = value,
        onSetOffset: (value) => offset = value,
        onMessage: (_) {},
        onPaginationError: (_, _) {},
        onRestartAuto: () {},
        isActive: () => true,
      );
      addTearDown(() {
        coordinator.dispose();
        controller.dispose();
      });

      final indexing = coordinator.ensurePages(
        size: const Size(400, 700),
        style: const TextStyle(fontSize: 20),
        fontFileName: null,
        fontFileVersion: null,
      );
      await tester.pump();

      final viewChangesBeforeJump = viewChanges;
      final jump = coordinator.jumpToPageNumber(50);

      expect(offset, 4900);
      expect(coordinator.displayPageNumber, 50);
      expect(coordinator.pageIndex, 0);
      expect(coordinator.pageWindow?.firstPage, 50);
      expect(coordinator.pageWindow?.pages.single.start, 4900);
      expect(viewChanges, greaterThan(viewChangesBeforeJump));
      expect(localPagination.isCompleted, isFalse);

      localPagination.complete([
        for (var start = 4500; start < 6900; start += 100)
          TextPage(start: start, end: start + 100),
      ]);
      await jump;
      expect(offset, 4900);
      expect(coordinator.displayPageNumber, 50);

      coordinator.dispose();
      fullPagination.complete(const []);
      await indexing;
    },
  );
}
