import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

const _textFileChannel = MethodChannel('com.songs.fantextviewer/text-file');
const _suggestedRecoveryName = 'fantextviewer-state-recovery.json';

class RecoveryFileExporter {
  RecoveryFileExporter({this.channel = _textFileChannel, bool? isAndroid})
    : _isAndroid = isAndroid ?? Platform.isAndroid;

  final MethodChannel channel;
  final bool _isAndroid;

  Future<bool> export(File source) async {
    if (_isAndroid) {
      return await channel.invokeMethod<bool>('exportRecoveryFile', {
            'path': source.path,
            'suggestedName': _suggestedRecoveryName,
          }) ??
          false;
    }
    const jsonFiles = XTypeGroup(
      label: 'JSON',
      extensions: ['json'],
      mimeTypes: ['application/json'],
    );
    final location = await getSaveLocation(
      acceptedTypeGroups: const [jsonFiles],
      suggestedName: _suggestedRecoveryName,
    );
    if (location == null) return false;
    await source.copy(location.path);
    return true;
  }
}
