import 'dart:io';

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
}
