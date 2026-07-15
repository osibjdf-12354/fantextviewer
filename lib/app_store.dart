import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'models.dart';

class AppStore extends ChangeNotifier {
  AppStore(this.file);

  final File file;
  AppData data = AppData();

  Future<void> load() async {
    if (!await file.exists()) return;
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      data = AppData.fromJson(json);
    } catch (_) {
      final broken = File('${file.path}.broken');
      if (await broken.exists()) await broken.delete();
      await file.rename(broken.path);
      data = AppData();
    }
    notifyListeners();
  }

  Future<void> save() async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(data.toJson()), flush: true);
  }

  DocumentState document(String path) {
    return data.documents.putIfAbsent(path, () => DocumentState(path: path));
  }

  List<DocumentState> get recentDocuments {
    final documents = data.documents.values
        .where((document) => document.lastOpened.isNotEmpty)
        .toList();
    documents.sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
    return documents;
  }

  void updateSettings(ReaderSettings settings) {
    data.settings = settings;
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
    notifyListeners();
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
    data.documents.remove(path);
    notifyListeners();
  }
}
