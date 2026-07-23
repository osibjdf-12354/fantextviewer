import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_store.dart';
import 'models.dart';

class ReaderController extends ChangeNotifier {
  ReaderController({
    required this.store,
    required this.path,
    required this.textLength,
    this.saveDelay = const Duration(milliseconds: 400),
  }) : _settings = store.data.settings {
    final document = store.document(path);
    _offset = document.offset.clamp(0, textLength);
    _scrollAlignment = document.scrollAlignment.clamp(0, 1);
  }

  final AppStore store;
  final String path;
  final int textLength;
  final Duration saveDelay;

  late ReaderSettings _settings;
  late int _offset;
  late double _scrollAlignment;
  Timer? _saveTimer;
  Object? _lastSaveError;

  ReaderSettings get settings => _settings;
  int get offset => _offset;
  double get scrollAlignment => _scrollAlignment;
  Object? get lastSaveError => _lastSaveError;

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
    super.dispose();
  }
}
