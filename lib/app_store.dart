import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'models.dart';

class AppStore extends ChangeNotifier {
  AppStore(this.file);

  final File file;
  AppData _data = AppData();
  Future<void> _saveTail = Future<void>.value();

  AppData get data => _data;
  Object? lastLoadError;
  StackTrace? lastLoadStackTrace;

  Future<void> load() async {
    if (!await file.exists()) return;
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _data = AppData.fromJson(json);
      lastLoadError = null;
      lastLoadStackTrace = null;
    } catch (error, stackTrace) {
      lastLoadError = error;
      lastLoadStackTrace = stackTrace;
      await file.rename(await _nextBrokenPath());
      _data = AppData();
    }
    notifyListeners();
  }

  Future<String> _nextBrokenPath() async {
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    var path = '${file.path}.broken.$stamp';
    var suffix = 1;
    while (await File(path).exists()) {
      path = '${file.path}.broken.$stamp.${suffix++}';
    }
    return path;
  }

  Future<void> save() {
    final snapshot = jsonEncode(_data.toJson());
    final operation = _saveTail.then((_) => _writeSnapshot(snapshot));
    _saveTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> _writeSnapshot(String snapshot) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.${identityHashCode(this)}.tmp');
    try {
      await temporary.writeAsString(snapshot, flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  DocumentState document(String path) {
    return _data.documents.putIfAbsent(path, () => DocumentState(path: path));
  }

  List<DocumentState> get recentDocuments {
    final documents = _data.documents.values
        .where((document) => document.lastOpened.isNotEmpty)
        .toList();
    documents.sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
    return documents;
  }

  void updateSettings(ReaderSettings settings) {
    _data.settings = settings;
    notifyListeners();
  }

  void touchRecent(
    String path, {
    int? fileSize,
    DateTime? modified,
    DateTime? openedAt,
  }) {
    final state = document(path);
    state.lastOpened = (openedAt ?? DateTime.now()).toUtc().toIso8601String();
    state.fileSize = fileSize ?? state.fileSize;
    state.modified = modified?.toUtc().toIso8601String() ?? state.modified;
    notifyListeners();
  }

  void updateProgress(
    String path, {
    required int offset,
    double scrollAlignment = 0,
    int? documentLength,
  }) {
    final state = document(path);
    state.offset = offset.clamp(0, documentLength ?? offset);
    state.scrollAlignment = scrollAlignment.clamp(0, 1);
  }

  void addBookmark(String path, Bookmark bookmark) {
    final state = document(path);
    if (state.bookmarks.any((saved) => saved.offset == bookmark.offset)) return;
    state.bookmarks.add(bookmark);
    state.bookmarks.sort((a, b) => a.offset.compareTo(b.offset));
    notifyListeners();
  }

  void removeBookmark(String path, int offset) {
    document(
      path,
    ).bookmarks.removeWhere((bookmark) => bookmark.offset == offset);
    notifyListeners();
  }

  void setEncoding(String path, String? encoding) {
    document(path).encoding = encoding;
    notifyListeners();
  }

  void removeDocument(String path) {
    _data.documents.remove(path);
    notifyListeners();
  }
}
