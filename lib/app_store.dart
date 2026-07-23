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
  File? recoveryFile;

  Future<void> load() async {
    if (!await file.exists()) return;
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _data = AppData.fromJson(json);
      lastLoadError = null;
      lastLoadStackTrace = null;
      recoveryFile = null;
    } catch (error, stackTrace) {
      lastLoadError = error;
      lastLoadStackTrace = stackTrace;
      recoveryFile = await file.rename(await _nextBrokenPath());
      _data = AppData();
    }
    notifyListeners();
  }

  Future<void> importState(File source) async {
    final decoded =
        jsonDecode(await source.readAsString()) as Map<String, dynamic>;
    final imported = AppData.fromJson(decoded);
    final previous = _data;
    _data = imported;
    try {
      await save();
    } catch (_) {
      _data = previous;
      rethrow;
    }
    lastLoadError = null;
    lastLoadStackTrace = null;
    recoveryFile = null;
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
    return _data.documents[path] ?? DocumentState(path: path);
  }

  List<DocumentState> get recentDocuments {
    final documents = _data.documents.values
        .where((document) => document.lastOpened.isNotEmpty)
        .toList();
    documents.sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
    return documents;
  }

  void updateSettings(ReaderSettings settings) {
    _data = _data.copyWith(settings: settings);
    notifyListeners();
  }

  void touchRecent(
    String path, {
    int? fileSize,
    DateTime? modified,
    DateTime? openedAt,
  }) {
    final state = document(path);
    _putDocument(
      state.copyWith(
        lastOpened: (openedAt ?? DateTime.now()).toUtc().toIso8601String(),
        fileSize: fileSize ?? state.fileSize,
        modified: modified?.toUtc().toIso8601String() ?? state.modified,
      ),
    );
    notifyListeners();
  }

  bool updateFileFingerprint(
    String path, {
    required int fileSize,
    required DateTime modified,
  }) {
    final state = document(path);
    final modifiedUtc = modified.toUtc().toIso8601String();
    final changed =
        (state.fileSize != null && state.fileSize != fileSize) ||
        (state.modified != null && state.modified != modifiedUtc);
    _putDocument(
      state.copyWith(
        offset: changed ? 0 : state.offset,
        scrollAlignment: changed ? 0 : state.scrollAlignment,
        encoding: changed ? null : state.encoding,
        bookmarks: changed ? const [] : state.bookmarks,
        fileSize: fileSize,
        modified: modifiedUtc,
      ),
    );
    return changed;
  }

  void updateProgress(
    String path, {
    required int offset,
    double scrollAlignment = 0,
    int? documentLength,
  }) {
    final state = document(path);
    _putDocument(
      state.copyWith(
        offset: offset.clamp(0, documentLength ?? offset),
        scrollAlignment: scrollAlignment.clamp(0, 1),
      ),
    );
  }

  void addBookmark(String path, Bookmark bookmark) {
    final state = document(path);
    if (state.bookmarks.any((saved) => saved.offset == bookmark.offset)) return;
    final bookmarks = [...state.bookmarks, bookmark]
      ..sort((a, b) => a.offset.compareTo(b.offset));
    _putDocument(state.copyWith(bookmarks: bookmarks));
    notifyListeners();
  }

  void removeBookmark(String path, int offset) {
    final state = _data.documents[path];
    if (state == null) return;
    final bookmarks = state.bookmarks
        .where((bookmark) => bookmark.offset != offset)
        .toList();
    if (bookmarks.length == state.bookmarks.length) return;
    _putDocument(state.copyWith(bookmarks: bookmarks));
    notifyListeners();
  }

  void setEncoding(String path, String? encoding) {
    _putDocument(document(path).copyWith(encoding: encoding));
    notifyListeners();
  }

  void removeDocument(String path) {
    if (!_data.documents.containsKey(path)) return;
    final documents = Map<String, DocumentState>.of(_data.documents)
      ..remove(path);
    _data = _data.copyWith(documents: documents);
    notifyListeners();
  }

  void _putDocument(DocumentState document) {
    _data = _data.copyWith(
      documents: {..._data.documents, document.path: document},
    );
  }
}
