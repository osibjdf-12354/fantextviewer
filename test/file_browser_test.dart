import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geulbom/file_browser.dart';

void main() {
  test('폴더를 먼저 표시하고 보이는 TXT 파일만 남긴다', () async {
    final directory = await Directory.systemTemp.createTemp('geulbom_files');
    addTearDown(() => directory.delete(recursive: true));
    await Directory(
      '${directory.path}${Platform.pathSeparator}folder',
    ).create();
    await File(
      '${directory.path}${Platform.pathSeparator}b.TXT',
    ).writeAsString('b');
    await File(
      '${directory.path}${Platform.pathSeparator}a.txt',
    ).writeAsString('a');
    await File(
      '${directory.path}${Platform.pathSeparator}skip.pdf',
    ).writeAsString('x');
    await File(
      '${directory.path}${Platform.pathSeparator}.hidden.txt',
    ).writeAsString('x');

    final entries = await listTextEntries(directory, BrowserSort.name);

    expect(entries.map((entry) => entry.name), ['folder', 'a.txt', 'b.TXT']);
    expect(entries.first.isDirectory, isTrue);
  });

  test('수정일 정렬에서도 폴더는 파일보다 먼저다', () async {
    final directory = await Directory.systemTemp.createTemp('geulbom_sort');
    addTearDown(() => directory.delete(recursive: true));
    await Directory(
      '${directory.path}${Platform.pathSeparator}folder',
    ).create();
    final older = File('${directory.path}${Platform.pathSeparator}older.txt');
    final newer = File('${directory.path}${Platform.pathSeparator}newer.txt');
    await older.writeAsString('old');
    await newer.writeAsString('new');
    await older.setLastModified(DateTime(2020));
    await newer.setLastModified(DateTime(2025));

    final entries = await listTextEntries(directory, BrowserSort.modified);

    expect(entries.map((entry) => entry.name), [
      'folder',
      'newer.txt',
      'older.txt',
    ]);
  });

  test('stats visible entries concurrently with a bounded batch', () async {
    final directory = await Directory.systemTemp.createTemp('geulbom_many');
    addTearDown(() => directory.delete(recursive: true));
    for (var index = 0; index < 64; index++) {
      await File(
        '${directory.path}${Platform.pathSeparator}$index.txt',
      ).writeAsString('$index');
    }
    var active = 0;
    var maxActive = 0;

    final entries = await listTextEntries(
      directory,
      BrowserSort.name,
      readStat: (entity) async {
        active++;
        if (active > maxActive) maxActive = active;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        final stat = await entity.stat();
        active--;
        return stat;
      },
    );

    expect(entries, hasLength(64));
    expect(maxActive, greaterThan(1));
    expect(maxActive, lessThanOrEqualTo(32));
  });

  test('one unreadable entry does not abort the directory listing', () async {
    final directory = await Directory.systemTemp.createTemp('geulbom_partial');
    addTearDown(() => directory.delete(recursive: true));
    final good = File('${directory.path}${Platform.pathSeparator}good.txt');
    final broken = File('${directory.path}${Platform.pathSeparator}broken.txt');
    await good.writeAsString('good');
    await broken.writeAsString('broken');

    final entries = await listTextEntries(
      directory,
      BrowserSort.name,
      readStat: (entity) {
        if (entity.path == broken.path) {
          throw const FileSystemException('unreadable');
        }
        return entity.stat();
      },
    );

    expect(entries.map((entry) => entry.name), ['good.txt']);
  });

  testWidgets('starts with a system directory picker instead of permissions', (
    tester,
  ) async {
    final directory = Directory(
      Platform.isWindows ? r'C:\selected' : '/selected',
    );
    var pickerCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: FileBrowserScreen(
          onOpenFile: (_) {},
          pickDirectory: ({initialDirectory}) async {
            pickerCalls++;
            return directory.path;
          },
          loadEntries: (_, _) async => [
            BrowserEntry(
              path: '${directory.path}${Platform.pathSeparator}book.txt',
              name: 'book.txt',
              isDirectory: false,
              modified: DateTime(2026),
              size: 4,
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('폴더 선택'), findsOneWidget);
    expect(find.textContaining('모든 파일 접근 권한'), findsNothing);
    await tester.tap(find.text('폴더 선택'));
    await tester.pump();
    await tester.pump();

    expect(pickerCalls, 1);
    expect(find.text('book.txt'), findsOneWidget);
  });

  testWidgets('a stale directory load cannot replace a newer result', (
    tester,
  ) async {
    final first = Completer<List<BrowserEntry>>();
    final second = Completer<List<BrowserEntry>>();
    var calls = 0;
    final directory = Directory.current;

    await tester.pumpWidget(
      MaterialApp(
        home: FileBrowserScreen(
          onOpenFile: (_) {},
          initialDirectory: directory,
          loadEntries: (_, _) => calls++ == 0 ? first.future : second.future,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('정렬'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('수정일순'));
    await tester.pump();
    second.complete([
      BrowserEntry(
        path: '${directory.path}${Platform.pathSeparator}new.txt',
        name: 'new.txt',
        isDirectory: false,
        modified: DateTime(2026),
        size: 3,
      ),
    ]);
    await tester.pump();
    first.complete([
      BrowserEntry(
        path: '${directory.path}${Platform.pathSeparator}old.txt',
        name: 'old.txt',
        isDirectory: false,
        modified: DateTime(2020),
        size: 3,
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('new.txt'), findsOneWidget);
    expect(find.text('old.txt'), findsNothing);
  });
}
