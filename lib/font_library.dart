import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

typedef FontRegistrar = Future<void> Function(String family, Uint8List bytes);
typedef FontCopier = Future<void> Function(File source, File target);

const maxImportedFontBytes = 32 * 1024 * 1024;

class ImportedFont {
  const ImportedFont._(this.file, this.version);

  final File file;
  final String version;

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
  FontLibrary(
    this.directory, {
    this.registerFont = _loadFontBytes,
    this.copyFont = _copyFontFile,
  });

  final Directory directory;
  final FontRegistrar registerFont;
  final FontCopier copyFont;
  final Set<String> _loadedFileNames = {};
  final Map<String, String> _versions = {};

  String? versionFor(String? fileName) =>
      fileName == null ? null : _versions[fileName];

  bool isLoaded(String fileName) => _loadedFileNames.contains(fileName);

  Future<List<ImportedFont>> listFonts() async {
    if (!await directory.exists()) {
      _versions.clear();
      return [];
    }
    final fonts = <ImportedFont>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && _isFontPath(entity.path)) {
        try {
          await _validateFont(entity);
          fonts.add(await _describeFont(entity));
        } on FormatException {
          // Ignore stale or corrupt files instead of breaking the whole list.
        } on FileSystemException {
          // A single unreadable font must not hide the remaining library.
        }
      }
    }
    fonts.sort(
      (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
    );
    _versions
      ..clear()
      ..addEntries(fonts.map((font) => MapEntry(font.fileName, font.version)));
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
    final source = File(sourcePath);
    await _validateFont(source);
    await directory.create(recursive: true);
    final target = await _availableTarget(
      source.path.split(Platform.pathSeparator).last,
    );
    try {
      await copyFont(source, target);
      await _validateFont(target);
      final imported = await _describeFont(target);
      await loadFont(imported);
      _versions[imported.fileName] = imported.version;
      return imported;
    } catch (error, stackTrace) {
      try {
        if (await target.exists()) await target.delete();
      } catch (_) {}
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> loadFont(ImportedFont font) async {
    if (_loadedFileNames.contains(font.fileName)) return;
    await _validateFont(font.file);
    await registerFont(font.family, await font.file.readAsBytes());
    _loadedFileNames.add(font.fileName);
  }

  Future<bool> loadSelected(String fileName) async {
    try {
      final font = await findFont(fileName);
      if (font == null) return false;
      await loadFont(font);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> deleteFont(ImportedFont font) async {
    if (await font.file.exists()) await font.file.delete();
    _versions.remove(font.fileName);
  }

  Future<ImportedFont> _describeFont(File file) async {
    final stat = await file.stat();
    final version =
        '${stat.size}:${stat.modified.toUtc().microsecondsSinceEpoch}';
    return ImportedFont._(file, version);
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

  static Future<void> _validateFont(File file) async {
    final stat = await file.stat();
    if (stat.size > maxImportedFontBytes) {
      throw const FormatException('글꼴 파일 크기는 32MB 이하여야 합니다.');
    }
    if (stat.size < 4) {
      throw const FormatException('올바른 TTF 또는 OTF 글꼴 파일이 아닙니다.');
    }

    final handle = await file.open();
    late final Uint8List header;
    try {
      header = await handle.read(4);
    } finally {
      await handle.close();
    }
    final valid =
        _matches(header, const [0x00, 0x01, 0x00, 0x00]) ||
        _matches(header, const [0x4f, 0x54, 0x54, 0x4f]) ||
        _matches(header, const [0x74, 0x72, 0x75, 0x65]) ||
        _matches(header, const [0x74, 0x74, 0x63, 0x66]);
    if (!valid) {
      throw const FormatException('올바른 TTF 또는 OTF 글꼴 파일이 아닙니다.');
    }
  }

  static bool _matches(Uint8List bytes, List<int> signature) {
    if (bytes.length != signature.length) return false;
    for (var index = 0; index < signature.length; index++) {
      if (bytes[index] != signature[index]) return false;
    }
    return true;
  }
}

Future<void> _loadFontBytes(String family, Uint8List bytes) async {
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

Future<void> _copyFontFile(File source, File target) async {
  await source.copy(target.path);
}
