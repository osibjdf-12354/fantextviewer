import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

typedef FontRegistrar = Future<void> Function(String family, Uint8List bytes);

class ImportedFont {
  const ImportedFont(this.file);

  final File file;

  String get fileName => file.path.split(Platform.pathSeparator).last;

  String get label {
    final dot = fileName.lastIndexOf('.');
    return dot < 1 ? fileName : fileName.substring(0, dot);
  }

  String get family => fontFamilyFor(fileName)!;
}

String? fontFamilyFor(String? fileName) =>
    fileName == null ? null : 'geulbom::$fileName';

Future<String?> pickFontFile() async {
  const fonts = XTypeGroup(
    label: '글꼴 파일',
    extensions: ['ttf', 'otf'],
    mimeTypes: ['font/ttf', 'font/otf'],
  );
  return (await openFile(acceptedTypeGroups: const [fonts]))?.path;
}

class FontLibrary {
  FontLibrary(this.directory, {FontRegistrar registerFont = _loadFontBytes})
    : _registerFont = registerFont;

  final Directory directory;
  final FontRegistrar _registerFont;
  final Set<String> _loadedFileNames = {};

  Future<List<ImportedFont>> listFonts() async {
    if (!await directory.exists()) return [];
    final fonts = <ImportedFont>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && _isFontPath(entity.path)) {
        fonts.add(ImportedFont(entity));
      }
    }
    fonts.sort(
      (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
    );
    return fonts;
  }

  Future<ImportedFont?> findFont(String fileName) async {
    for (final font in await listFonts()) {
      if (font.fileName == fileName) return font;
    }
    return null;
  }

  Future<ImportedFont> importFont(String sourcePath) async {
    if (!_isFontPath(sourcePath)) {
      throw const FormatException('지원하는 글꼴은 TTF 또는 OTF 파일입니다.');
    }
    await directory.create(recursive: true);
    final source = File(sourcePath);
    final target = await _availableTarget(
      source.path.split(Platform.pathSeparator).last,
    );
    await source.copy(target.path);
    final imported = ImportedFont(target);
    try {
      await loadFont(imported);
      return imported;
    } catch (_) {
      if (await target.exists()) await target.delete();
      rethrow;
    }
  }

  Future<void> loadFont(ImportedFont font) async {
    if (_loadedFileNames.contains(font.fileName)) return;
    await _registerFont(font.family, await font.file.readAsBytes());
    _loadedFileNames.add(font.fileName);
  }

  Future<bool> loadSelected(String fileName) async {
    final font = await findFont(fileName);
    if (font == null) return false;
    try {
      await loadFont(font);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> deleteFont(ImportedFont font) async {
    if (await font.file.exists()) await font.file.delete();
  }

  Future<File> _availableTarget(String fileName) async {
    final dot = fileName.lastIndexOf('.');
    final stem = dot < 1 ? fileName : fileName.substring(0, dot);
    final extension = dot < 1 ? '' : fileName.substring(dot);
    var candidate = fileName;
    var suffix = 2;
    while (_loadedFileNames.contains(candidate) ||
        await File(
          '${directory.path}${Platform.pathSeparator}$candidate',
        ).exists()) {
      candidate = '$stem ($suffix)$extension';
      suffix++;
    }
    return File('${directory.path}${Platform.pathSeparator}$candidate');
  }

  static bool _isFontPath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.ttf') || lower.endsWith('.otf');
  }
}

Future<void> _loadFontBytes(String family, Uint8List bytes) async {
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}
