import 'dart:async';
import 'dart:isolate';

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
  Timer? _autoTimer;
  Object? _lastSaveError;
  String _searchQuery = '';
  ReaderSearchMatch? _activeSearchMatch;
  bool _autoMode = false;
  int _autoPauseDepth = 0;
  bool _appActive = true;
  int _searchGeneration = 0;

  ReaderSettings get settings => _settings;
  int get offset => _offset;
  double get scrollAlignment => _scrollAlignment;
  Object? get lastSaveError => _lastSaveError;
  String get searchQuery => _searchQuery;
  ReaderSearchMatch? get activeSearchMatch => _activeSearchMatch;
  bool get autoMode => _autoMode;
  bool get appActive => _appActive;
  bool get canAutoAdvance => _autoMode && _autoPauseDepth == 0 && _appActive;

  void setAutoMode(bool value) {
    if (_autoMode == value) return;
    _autoMode = value;
    if (!value) cancelAutoAdvance();
    notifyListeners();
  }

  void pauseAuto() {
    _autoPauseDepth++;
    cancelAutoAdvance();
  }

  void resumeAuto() {
    if (_autoPauseDepth > 0) _autoPauseDepth--;
  }

  void setAppActive(bool value) {
    if (_appActive == value) return;
    _appActive = value;
    if (!value) cancelAutoAdvance();
  }

  void scheduleAutoAdvance(Duration delay, FutureOr<void> Function() advance) {
    cancelAutoAdvance();
    if (!canAutoAdvance) return;
    _autoTimer = Timer(delay, () async {
      _autoTimer = null;
      if (canAutoAdvance) await advance();
    });
  }

  void cancelAutoAdvance() {
    _autoTimer?.cancel();
    _autoTimer = null;
  }

  Future<ReaderSearchMatch?> startSearch(String query) async {
    final generation = ++_searchGeneration;
    _searchQuery = query;
    if (query.isEmpty || text.isEmpty) {
      _activeSearchMatch = null;
      notifyListeners();
      return null;
    }
    final start = (_offset + 1).clamp(0, text.length);
    final found = await _findText(
      text: text,
      query: query,
      start: start,
      backwards: false,
    );
    return _applySearchResult(found, query, generation);
  }

  Future<ReaderSearchMatch?> nextSearchResult() async {
    if (_searchQuery.isEmpty || text.isEmpty) return null;
    final generation = ++_searchGeneration;
    final query = _searchQuery;
    final current = _activeSearchMatch;
    final start = current?.end ?? (_offset + 1).clamp(0, text.length);
    final found = await _findText(
      text: text,
      query: query,
      start: start,
      backwards: false,
    );
    return _applySearchResult(found, query, generation);
  }

  Future<ReaderSearchMatch?> previousSearchResult() async {
    if (_searchQuery.isEmpty || text.isEmpty) return null;
    final generation = ++_searchGeneration;
    final query = _searchQuery;
    final current = _activeSearchMatch;
    final start = current == null ? _offset - 1 : current.start - 1;
    final found = await _findText(
      text: text,
      query: query,
      start: start,
      backwards: true,
    );
    return _applySearchResult(found, query, generation);
  }

  ReaderSearchMatch? _applySearchResult(
    int found,
    String query,
    int generation,
  ) {
    if (generation != _searchGeneration) return _activeSearchMatch;
    _activeSearchMatch = found < 0
        ? null
        : ReaderSearchMatch(start: found, length: query.length);
    notifyListeners();
    return _activeSearchMatch;
  }

  void clearSearch() {
    if (_searchQuery.isEmpty && _activeSearchMatch == null) return;
    _searchGeneration++;
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
    _autoTimer?.cancel();
    paginationActivity.dispose();
    super.dispose();
  }
}

const _isolateSearchThreshold = 256 * 1024;

Future<int> _findText({
  required String text,
  required String query,
  required int start,
  required bool backwards,
}) async {
  int find() {
    if (backwards) {
      var found = start < 0 ? -1 : text.lastIndexOf(query, start);
      if (found < 0) found = text.lastIndexOf(query);
      return found;
    }
    var found = text.indexOf(query, start);
    if (found < 0) found = text.indexOf(query);
    return found;
  }

  return text.length < _isolateSearchThreshold
      ? find()
      : Isolate.run(find, debugName: 'reader-search');
}
