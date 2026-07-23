import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_store.dart';
import 'models.dart';

@immutable
class ReaderSearchMatch {
  const ReaderSearchMatch({required this.start, required this.length});

  final int start;
  final int length;

  int get end => start + length;
}

@immutable
class PaginationActivity {
  const PaginationActivity({this.progress = 0, this.revision = 0});

  final double progress;
  final int revision;
}

class ReaderController extends ChangeNotifier {
  ReaderController({
    required this.store,
    required this.path,
    required this.textLength,
    this.text = '',
    this.saveDelay = const Duration(milliseconds: 400),
  }) : _settings = store.data.settings {
    final document = store.document(path);
    _offset = document.offset.clamp(0, textLength);
    _scrollAlignment = document.scrollAlignment.clamp(0, 1);
  }

  final AppStore store;
  final String path;
  final int textLength;
  final String text;
  final Duration saveDelay;
  final paginationActivity = ValueNotifier(const PaginationActivity());

  late ReaderSettings _settings;
  late int _offset;
  late double _scrollAlignment;
  Timer? _saveTimer;
  Object? _lastSaveError;
  String _searchQuery = '';
  ReaderSearchMatch? _activeSearchMatch;

  ReaderSettings get settings => _settings;
  int get offset => _offset;
  double get scrollAlignment => _scrollAlignment;
  Object? get lastSaveError => _lastSaveError;
  String get searchQuery => _searchQuery;
  ReaderSearchMatch? get activeSearchMatch => _activeSearchMatch;

  ReaderSearchMatch? startSearch(String query) {
    _searchQuery = query;
    if (query.isEmpty || text.isEmpty) {
      _activeSearchMatch = null;
      notifyListeners();
      return null;
    }
    final start = (_offset + 1).clamp(0, text.length);
    var found = text.indexOf(query, start);
    if (found < 0) found = text.indexOf(query);
    _activeSearchMatch = found < 0
        ? null
        : ReaderSearchMatch(start: found, length: query.length);
    notifyListeners();
    return _activeSearchMatch;
  }

  ReaderSearchMatch? nextSearchResult() {
    if (_searchQuery.isEmpty || text.isEmpty) return null;
    final current = _activeSearchMatch;
    final start = current?.end ?? (_offset + 1).clamp(0, text.length);
    var found = text.indexOf(_searchQuery, start);
    if (found < 0) found = text.indexOf(_searchQuery);
    return _setSearchMatch(found);
  }

  ReaderSearchMatch? previousSearchResult() {
    if (_searchQuery.isEmpty || text.isEmpty) return null;
    final current = _activeSearchMatch;
    final start = current == null ? _offset - 1 : current.start - 1;
    var found = start < 0 ? -1 : text.lastIndexOf(_searchQuery, start);
    if (found < 0) found = text.lastIndexOf(_searchQuery);
    return _setSearchMatch(found);
  }

  ReaderSearchMatch? _setSearchMatch(int found) {
    _activeSearchMatch = found < 0
        ? null
        : ReaderSearchMatch(start: found, length: _searchQuery.length);
    notifyListeners();
    return _activeSearchMatch;
  }

  void clearSearch() {
    if (_searchQuery.isEmpty && _activeSearchMatch == null) return;
    _searchQuery = '';
    _activeSearchMatch = null;
    notifyListeners();
  }

  void resetPaginationActivity() {
    paginationActivity.value = PaginationActivity(
      revision: paginationActivity.value.revision + 1,
    );
  }

  void updatePaginationProgress(double progress) {
    paginationActivity.value = PaginationActivity(
      progress: progress.clamp(0, 1).toDouble(),
      revision: paginationActivity.value.revision,
    );
  }

  void notifyPaginationChanged() {
    paginationActivity.value = PaginationActivity(
      progress: paginationActivity.value.progress,
      revision: paginationActivity.value.revision + 1,
    );
  }

  void updateOffset(int value, {double scrollAlignment = 0}) {
    final nextOffset = value.clamp(0, textLength);
    final nextAlignment = scrollAlignment.clamp(0, 1).toDouble();
    if (_offset == nextOffset && _scrollAlignment == nextAlignment) return;
    _offset = nextOffset;
    _scrollAlignment = nextAlignment;
    store.updateProgress(
      path,
      offset: nextOffset,
      scrollAlignment: nextAlignment,
      documentLength: textLength,
    );
    _scheduleSave();
    notifyListeners();
  }

  void applySettings(ReaderSettings value) {
    if (_settings == value) return;
    _settings = value;
    store.updateSettings(value);
    _scheduleSave();
    notifyListeners();
  }

  void scheduleSave() => _scheduleSave();

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDelay, () async {
      try {
        await store.save();
        _lastSaveError = null;
      } catch (error) {
        _lastSaveError = error;
        notifyListeners();
      }
    });
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    try {
      await store.save();
      _lastSaveError = null;
    } catch (error) {
      _lastSaveError = error;
      notifyListeners();
      rethrow;
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    paginationActivity.dispose();
    super.dispose();
  }
}
