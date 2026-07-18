import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geulbom/font_library.dart';

void main() {
  test(
    'copies TTF files, preserves duplicate names, and deletes only the copy',
    () async {
      final root = await Directory.systemTemp.createTemp('geulbom_fonts');
      addTearDown(() => root.delete(recursive: true));
      final source = File('${root.path}${Platform.pathSeparator}Nanum.ttf');
      await source.writeAsBytes([1, 2, 3]);
      final registered = <String>[];
      final library = FontLibrary(
        Directory('${root.path}${Platform.pathSeparator}app-fonts'),
        registerFont: (family, bytes) async {
          registered.add('$family:${bytes.length}');
        },
      );

      final first = await library.importFont(source.path);
      final second = await library.importFont(source.path);
      await File(
        '${library.directory.path}${Platform.pathSeparator}ignore.txt',
      ).writeAsString('not a font');
      await source.delete();

      expect(first.fileName, 'Nanum.ttf');
      expect(second.fileName, 'Nanum (2).ttf');
      expect((await library.listFonts()).map((font) => font.fileName), [
        'Nanum.ttf',
        'Nanum (2).ttf',
      ]);
      expect(await first.file.exists(), isTrue);
      expect(registered, hasLength(2));

      await library.deleteFont(first);

      expect(await first.file.exists(), isFalse);
    },
  );

  test(
    'rejects unsupported extensions and removes copies when registration fails',
    () async {
      final root = await Directory.systemTemp.createTemp('geulbom_bad_font');
      addTearDown(() => root.delete(recursive: true));
      final fonts = Directory('${root.path}${Platform.pathSeparator}fonts');
      final text = File('${root.path}${Platform.pathSeparator}font.txt');
      final broken = File('${root.path}${Platform.pathSeparator}broken.otf');
      await text.writeAsString('text');
      await broken.writeAsBytes([0]);
      final library = FontLibrary(
        fonts,
        registerFont: (_, _) async => throw const FormatException('broken'),
      );

      await expectLater(
        library.importFont(text.path),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        library.importFont(broken.path),
        throwsA(isA<FormatException>()),
      );

      expect(await library.listFonts(), isEmpty);
    },
  );

  test(
    'loadSelected returns false for a missing or unloadable saved font',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'geulbom_restore_font',
      );
      addTearDown(() => root.delete(recursive: true));
      final library = FontLibrary(
        Directory('${root.path}${Platform.pathSeparator}fonts'),
        registerFont: (_, _) async => throw const FormatException('broken'),
      );

      expect(await library.loadSelected('missing.ttf'), isFalse);
      final font = File(
        '${library.directory.path}${Platform.pathSeparator}broken.ttf',
      );
      await font.parent.create(recursive: true);
      await font.writeAsBytes([0]);
      expect(await library.loadSelected('broken.ttf'), isFalse);
    },
  );
}
