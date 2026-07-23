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
      await source.writeAsBytes(_validTtfBytes);
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
      await library.loadFont(first);
      expect(registered, hasLength(2));

      await library.deleteFont(first);

      expect(await first.file.exists(), isFalse);
      expect(library.isLoaded(first.fileName), isTrue);
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

  test('removes a partial copy and preserves the copy error', () async {
    final root = await Directory.systemTemp.createTemp('geulbom_partial_font');
    addTearDown(() => root.delete(recursive: true));
    final source = File('${root.path}${Platform.pathSeparator}partial.ttf');
    await source.writeAsBytes(_validTtfBytes);
    final fonts = Directory('${root.path}${Platform.pathSeparator}fonts');
    final copyError = StateError('copy failed');
    final library = FontLibrary(
      fonts,
      registerFont: (_, _) async {},
      copyFont: (source, target) async {
        await target.writeAsBytes([1]);
        Error.throwWithStackTrace(copyError, StackTrace.current);
      },
    );

    await expectLater(
      library.importFont(source.path),
      throwsA(same(copyError)),
    );

    expect(await library.listFonts(), isEmpty);
  });

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

  test('rejects oversized and invalid SFNT files before copying', () async {
    final root = await Directory.systemTemp.createTemp('geulbom_font_limits');
    addTearDown(() => root.delete(recursive: true));
    final fonts = Directory('${root.path}${Platform.pathSeparator}fonts');
    final invalid = File('${root.path}${Platform.pathSeparator}invalid.ttf');
    final oversized = File(
      '${root.path}${Platform.pathSeparator}oversized.otf',
    );
    await invalid.writeAsBytes([1, 2, 3, 4, 5]);
    final handle = await oversized.open(mode: FileMode.write);
    await handle.truncate(maxImportedFontBytes + 1);
    await handle.close();
    var copyCalls = 0;
    final library = FontLibrary(
      fonts,
      registerFont: (_, _) async {},
      copyFont: (source, target) async {
        copyCalls++;
        await source.copy(target.path);
      },
    );

    await expectLater(
      library.importFont(invalid.path),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      library.importFont(oversized.path),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('크기'),
        ),
      ),
    );

    expect(copyCalls, 0);
    expect(await fonts.exists(), isFalse);
  });

  test('lists only files with valid SFNT headers', () async {
    final root = await Directory.systemTemp.createTemp('geulbom_font_headers');
    addTearDown(() => root.delete(recursive: true));
    final fonts = Directory('${root.path}${Platform.pathSeparator}fonts');
    await fonts.create();
    await File(
      '${fonts.path}${Platform.pathSeparator}valid.otf',
    ).writeAsBytes(_validOtfBytes);
    await File(
      '${fonts.path}${Platform.pathSeparator}broken.ttf',
    ).writeAsBytes([0, 1, 2, 3]);

    final listed = await FontLibrary(
      fonts,
      registerFont: (_, _) async {},
    ).listFonts();

    expect(listed.map((font) => font.fileName), ['valid.otf']);
  });
}

const _validTtfBytes = [0x00, 0x01, 0x00, 0x00, 0, 0, 0, 0];
const _validOtfBytes = [0x4f, 0x54, 0x54, 0x4f, 0, 0, 0, 0];
