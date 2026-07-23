import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'text_paginator.dart';

typedef CacheErrorHandler = void Function(Object error, StackTrace stackTrace);

class PageIndexCache {
  PageIndexCache({this.directory, CacheErrorHandler? onError})
    : onError = onError ?? _reportCacheError;

  final Directory? directory;
  final CacheErrorHandler onError;

  static const currentSchemaVersion = 1;

  Future<List<TextPage>?> load({
    required String signature,
    required int textLength,
  }) async {
    try {
      final file = await _file(signature);
      if (!await file.exists()) return null;
      final record = jsonDecode(await file.readAsString());
      if (record is! Map<String, dynamic> ||
          (record['schemaVersion'] != null &&
              record['schemaVersion'] != currentSchemaVersion) ||
          record['signature'] != signature ||
          record['textLength'] != textLength ||
          record['starts'] is! List ||
          record['displayStarts'] is! List) {
        return null;
      }
      final starts = _validatedStarts(record['starts'], textLength);
      if (starts == null) return null;
      final displayStarts = _validatedDisplayStarts(
        record['displayStarts'],
        starts,
      );
      if (displayStarts == null) return null;
      return [
        for (var index = 0; index < starts.length; index++)
          TextPage(
            start: starts[index],
            end: index + 1 < starts.length ? starts[index + 1] : textLength,
            displayStart: displayStarts[index],
          ),
      ];
    } catch (error, stackTrace) {
      onError(error, stackTrace);
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
      temporary = File('${file.path}.${identityHashCode(pages)}.tmp');
      await temporary.writeAsString(
        jsonEncode({
          'schemaVersion': currentSchemaVersion,
          'signature': signature,
          'textLength': textLength,
          'starts': pages.map((page) => page.start).toList(),
          'displayStarts': pages.map((page) => page.displayStart).toList(),
        }),
        flush: true,
      );
      await temporary.rename(file.path);
      await _prune(file.parent, file);
    } catch (error, stackTrace) {
      onError(error, stackTrace);
      try {
        if (temporary != null && await temporary.exists()) {
          await temporary.delete();
        }
      } catch (cleanupError, cleanupStackTrace) {
        onError(cleanupError, cleanupStackTrace);
      }
    }
  }

  Future<File> _file(String signature) async {
    final directory = this.directory ?? await getTemporaryDirectory();
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
    if (records.length <= 8) return;
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

void _reportCacheError(Object error, StackTrace stackTrace) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      library: 'fantextviewer page cache',
      context: ErrorDescription('while reading or writing a page index'),
    ),
  );
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

List<int>? _validatedDisplayStarts(Object? value, List<int> starts) {
  if (value is! List || value.length != starts.length) return null;
  final result = <int>[];
  for (var index = 0; index < starts.length; index++) {
    final displayStart = value[index];
    final minimum = index == 0 ? starts[index] : starts[index - 1];
    if (displayStart is! int ||
        displayStart < minimum ||
        displayStart > starts[index]) {
      return null;
    }
    result.add(displayStart);
  }
  return result;
}

String _stableHash(String value) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(value)) {
    hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
