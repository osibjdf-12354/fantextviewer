import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

import 'app_store.dart';
import 'strings.dart';

const _textFileChannel = MethodChannel('com.songs.fantextviewer/text-file');

class TextFileImporter {
  TextFileImporter({
    MethodChannel channel = _textFileChannel,
    bool? isAndroid,
    Future<String?> Function()? fallbackPicker,
  }) : _channel = channel,
       _isAndroid = isAndroid ?? Platform.isAndroid,
       _fallbackPicker = fallbackPicker ?? _pickWithFileSelector;

  final MethodChannel _channel;
  final bool _isAndroid;
  final Future<String?> Function() _fallbackPicker;

  Future<String?> pick() {
    if (_isAndroid) {
      return _channel.invokeMethod<String>('importTextFile');
    }
    return _fallbackPicker();
  }

  Future<String?> promoteLegacy(String path) {
    if (!_isAndroid) return Future.value();
    return _channel.invokeMethod<String>('promoteLegacyImport', {'path': path});
  }
}

Future<String?> pickTextFile() => TextFileImporter().pick();

Future<void> promoteLegacyTextImports(
  AppStore store, {
  TextFileImporter? importer,
}) async {
  final textFileImporter = importer ?? TextFileImporter();
  var changed = false;
  for (final document in store.data.documents.values.toList()) {
    final durablePath = await textFileImporter.promoteLegacy(document.path);
    if (durablePath == null || durablePath == document.path) continue;
    store.moveDocument(document.path, durablePath);
    changed = true;
  }
  if (changed) await store.save();
}

Future<String?> _pickWithFileSelector() async {
  const textFiles = XTypeGroup(
    label: AppStrings.textFile,
    extensions: ['txt'],
    mimeTypes: ['text/plain'],
  );
  return (await openFile(acceptedTypeGroups: const [textFiles]))?.path;
}
