import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'text_paginator.dart';

class PageIndexCache {
  PageIndexCache({this.directory});

  final Directory? directory;

  Future<List<TextPage>?> load({
    required String signature,
    required int textLength,
  }) async {
    try {
      final file = await _file(signature);
      if (!await file.exists()) return null;
      final record = jsonDecode(await file.readAsString());
      if (record is! Map<String, dynamic> ||
          record['signature'] != signature ||
          record['textLength'] != textLength ||
          record['starts'] is! List) {
        return null;
      }
      final starts = _validatedStarts(record['starts'], textLength);
      if (starts == null) return null;
      return [
        for (var index = 0; index < starts.length; index++)
          TextPage(
            start: starts[index],
            end: index + 1 < starts.length ? starts[index + 1] : textLength,
          ),
      ];
    } catch (_) {
      return null;
    }
  }

  Future<void> save({
    required String signature,
    required int textLength,
    required List<TextPage> pages,
  }) async {
    File? temporary;
    try {
      final file = await _file(signature);
      await file.parent.create(recursive: true);
      temporary = File('${file.path}.tmp');
      await temporary.writeAsString(
        jsonEncode({
          'signature': signature,
          'textLength': textLength,
          'starts': pages.map((page) => page.start).toList(),
        }),
        flush: true,
      );
      await temporary.rename(file.path);
      await _prune(file.parent, file);
    } catch (_) {
      try {
        if (temporary != null && await temporary.exists()) {
          await temporary.delete();
        }
      } catch (_) {}
    }
  }

  Future<File> _file(String signature) async {
    final directory = this.directory ?? await getApplicationSupportDirectory();
    return File(
      '${directory.path}${Platform.pathSeparator}'
      'page_index_${_stableHash(signature)}.json',
    );
  }

  Future<void> _prune(Directory directory, File saved) async {
    final records = <(File, DateTime)>[];
    await for (final entity in directory.list()) {
      final name = entity.uri.pathSegments.last;
      if (entity is File &&
          name.startsWith('page_index_') &&
          name.endsWith('.json')) {
        records.add((entity, await entity.lastModified()));
      }
    }
    records.sort((a, b) {
      final modified = a.$2.compareTo(b.$2);
      return modified != 0 ? modified : a.$1.path.compareTo(b.$1.path);
    });
    final excess = records.length - 8;
    for (final record
        in records
            .where((record) => record.$1.path != saved.path)
            .take(excess)) {
      await record.$1.delete();
    }
  }
}

List<int>? _validatedStarts(Object? value, int textLength) {
  if (value is! List || value.isEmpty || textLength <= 0) return null;
  final starts = <int>[];
  for (final start in value) {
    if (start is! int ||
        start < 0 ||
        start >= textLength ||
        (starts.isEmpty ? start != 0 : start <= starts.last)) {
      return null;
    }
    starts.add(start);
  }
  return starts;
}

String _stableHash(String value) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(value)) {
    hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
