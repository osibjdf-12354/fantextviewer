// Public test parameters intentionally initialize private dependency fields.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app_store.dart';
import 'font_library.dart';
import 'models.dart';
import 'page_index_cache.dart';
import 'page_turn_view.dart';
import 'reader_controller.dart';
import 'reader_pagination_coordinator.dart';
import 'reader_settings_sheet.dart';
import 'strings.dart';
import 'text_document.dart';
import 'text_paginator.dart';

export 'reader_settings_sheet.dart' show contrastRatio;

const _scrollTopPadding = 16.0;

typedef TextDocumentLoader =
    Future<DecodedText> Function(String path, {TextEncoding? forced});

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.path,
    required this.store,
    this.fontLibrary,
    this.loadDocument = loadTextFile,
  });

  final String path;
  final AppStore store;
  final FontLibrary? fontLibrary;
  final TextDocumentLoader loadDocument;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late final PageIndexCache _pageIndexCache;
  DecodedText? _document;
  FileStat? _stat;
  Object? _error;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    _pageIndexCache = PageIndexCache(onError: _showPageCacheError);
    _load();
  }

  void _showPageCacheError(Object error, StackTrace stackTrace) {
    debugPrint('Page cache failed: $error\n$stackTrace');
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text(AppStrings.pageCacheFailed)),
      );
    });
  }

  Future<void> _load([TextEncoding? forced]) async {
    final generation = ++_generation;
    setState(() {
      _document = null;
      _error = null;
    });
    try {
      final file = File(widget.path);
      final stat = await file.stat();
      if (!mounted || generation != _generation) return;
      final saved = widget.store.document(widget.path).encoding;
      final encoding = forced ?? _encodingByName(saved);
      if (stat.size > 32 * 1024 * 1024) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || generation != _generation) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(AppStrings.openingLargeFile)),
          );
        });
      }
      Future<DecodedText> decode(TextEncoding? selectedEncoding) async {
        final decoded = await widget.loadDocument(
          widget.path,
          forced: selectedEncoding,
        );
        final decodedStat = await file.stat();
        if (decodedStat.size != stat.size ||
            decodedStat.modified.toUtc() != stat.modified.toUtc()) {
          throw const FileSystemException(AppStrings.fileChangedWhileReading);
        }
        return decoded;
      }

      var document = await decode(encoding);
      final contentChanged = widget.store.fileChanged(
        widget.path,
        fileSize: stat.size,
        modified: stat.modified,
        contentFingerprint: document.fingerprint,
      );
      if (contentChanged && forced == null && saved != null) {
        document = await decode(null);
      }
      if (!mounted || generation != _generation) return;

      widget.store.updateFileFingerprint(
        widget.path,
        fileSize: stat.size,
        modified: stat.modified,
        contentFingerprint: document.fingerprint,
      );
      widget.store.setEncoding(widget.path, document.encoding.name);
      widget.store.touchRecent(
        widget.path,
        fileSize: stat.size,
        modified: stat.modified,
      );
      final current = widget.store.document(widget.path);
      widget.store.updateProgress(
        widget.path,
        offset: current.offset,
        documentLength: document.text.length,
      );
      setState(() {
        _document = document;
        _stat = stat;
      });
      try {
        await widget.store.save();
      } catch (error, stackTrace) {
        debugPrint(AppStrings.readingStateSaveDiagnostic(error, stackTrace));
        if (mounted && generation == _generation) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(AppStrings.saveReadingPositionFailed)),
          );
        }
      }
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final document = _document;
    if (document == null) {
      return Scaffold(
        appBar: AppBar(title: Text(_fileName(widget.path))),
        body: _error == null
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48),
                      const SizedBox(height: 16),
                      const Text(AppStrings.fileReadFailed),
                      const SizedBox(height: 8),
                      Text(
                        '$_error',
                        textAlign: TextAlign.center,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        children: [
                          FilledButton(
                            onPressed: _load,
                            child: const Text(AppStrings.retry),
                          ),
                          PopupMenuButton<TextEncoding>(
                            onSelected: _load,
                            itemBuilder: _encodingItems,
                            child: const Padding(
                              padding: EdgeInsets.all(12),
                              child: Text(AppStrings.openWithEncoding),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
      );
    }

    return ReaderView._configured(
      key: ValueKey('${widget.path}:${document.encoding.name}'),
      path: widget.path,
      title: _fileName(widget.path),
      text: document.text,
      encoding: document.encoding,
      contentFingerprint: document.fingerprint,
      fileSize: _stat?.size,
      modified: _stat?.modified,
      store: widget.store,
      pageIndexCache: _pageIndexCache,
      onEncodingChanged: _load,
      onOpenFile: () => Navigator.of(context).pop(),
      fontLibrary: widget.fontLibrary,
    );
  }
}

class ReaderView extends StatefulWidget {
  const ReaderView({
    super.key,
    required this.path,
    required this.title,
    required this.text,
    required this.encoding,
    required this.store,
    this.contentFingerprint,
    this.fileSize,
    this.modified,
    this.onEncodingChanged,
    this.onOpenFile,
    this.fontLibrary,
  }) : _pageIndexCache = null,
       _paginator = paginateText,
       _windowPaginator = paginateTextWindow,
       _pickFont = pickFontFile,
       _controller = null;

  const ReaderView._configured({
    super.key,
    required this.path,
    required this.title,
    required this.text,
    required this.encoding,
    required this.store,
    required this._pageIndexCache,
    this.contentFingerprint,
    this.fileSize,
    this.modified,
    this.onEncodingChanged,
    this.onOpenFile,
    this.fontLibrary,
  }) : _paginator = paginateText,
       _windowPaginator = paginateTextWindow,
       _pickFont = pickFontFile,
       _controller = null;

  @visibleForTesting
  const ReaderView.test({
    super.key,
    required this.path,
    required this.title,
    required this.text,
    required this.encoding,
    required this.store,
    this.contentFingerprint,
    this.fileSize,
    this.modified,
    PageIndexCache? pageIndexCache,
    ReaderPaginator paginator = paginateText,
    ReaderWindowPaginator windowPaginator = paginateTextWindow,
    this.onEncodingChanged,
    this.onOpenFile,
    this.fontLibrary,
    Future<String?> Function() pickFont = pickFontFile,
    ReaderController? controller,
  }) : _pageIndexCache = pageIndexCache,
       _paginator = paginator,
       _windowPaginator = windowPaginator,
       _pickFont = pickFont,
       _controller = controller;

  final String path;
  final String title;
  final String text;
  final TextEncoding encoding;
  final AppStore store;
  final String? contentFingerprint;
  final int? fileSize;
  final DateTime? modified;
  final PageIndexCache? _pageIndexCache;
  final ReaderPaginator _paginator;
  final ReaderWindowPaginator _windowPaginator;
  final ValueChanged<TextEncoding>? onEncodingChanged;
  final VoidCallback? onOpenFile;
  final FontLibrary? fontLibrary;
  final Future<String?> Function() _pickFont;
  final ReaderController? _controller;

  @override
  State<ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends State<ReaderView> with WidgetsBindingObserver {
  late final ReaderController _controller;
  late final bool _ownsController;
  late List<TextChunk> _chunks;
  final _itemScrollController = ItemScrollController();
  final _scrollOffsetController = ScrollOffsetController();
  final _itemPositionsListener = ItemPositionsListener.create();
  final _pageTurnKey = GlobalKey<PageTurnViewState>();
  late final ReaderPaginationCoordinator _pagination;
  int? _pendingScrollOffset;
  Size? _pageSize;
  bool _allowPop = false;
  String? _scrollChunkLayoutKey;
  String? _pendingScrollChunkLayoutKey;
  int _scrollChunkGeneration = 0;
  bool _scrollPositionsReady = false;
  bool _scrollPositionChanged = false;
  bool _restoringExactScrollPosition = false;
  Object? _paginationError;
  Timer? _scrollSaveTimer;

  ReaderSettings get _settings => _controller.settings;
  int get _offset => _controller.offset;
  ReadingMode get _activeMode =>
      _controller.autoMode ? ReadingMode.page : _settings.mode;
  PageTurnDirection get _activePageTurnDirection => _controller.autoMode
      ? PageTurnDirection.vertical
      : _settings.pageTurnDirection;
  int get _fallbackCharactersPerPage {
    final size = _pageSize;
    if (size == null) return 400;
    final charactersPerLine = math.max(
      1,
      (size.width / math.max(1, _settings.fontSize)).floor(),
    );
    final linesPerPage = math.max(
      1,
      (size.height / math.max(1, _settings.fontSize * _settings.lineHeight))
          .floor(),
    );
    return charactersPerLine * linesPerPage;
  }

  int get _displayTotalPages => _pagination.displayTotalPages;
  int get _currentPageNumber => _pagination.currentPageNumber;
  String get _pageIndicatorLabel =>
      _pagination.pageIndicatorLabel(showTotalPages: _settings.showTotalPages);

  TextStyle get _textStyle => TextStyle(
    inherit: false,
    color: Color(_settings.foreground.value),
    fontFamily: fontFamilyFor(_settings.fontFileName),
    fontSize: MediaQuery.textScalerOf(context).scale(_settings.fontSize),
    height: _settings.lineHeight,
    textBaseline: TextBaseline.alphabetic,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownsController = widget._controller == null;
    _controller =
        widget._controller ??
        ReaderController(
          store: widget.store,
          path: widget.path,
          textLength: widget.text.length,
          text: widget.text,
        );
    _controller.addListener(_onControllerChanged);
    _pagination = ReaderPaginationCoordinator(
      text: widget.text,
      path: widget.path,
      encoding: widget.encoding,
      fileSize: widget.fileSize,
      modified: widget.modified,
      contentFingerprint:
          widget.contentFingerprint ?? 'memory:${widget.text.hashCode}',
      pageIndexCache: widget._pageIndexCache,
      paginator: widget._paginator,
      windowPaginator: widget._windowPaginator,
      readerController: _controller,
      settings: () => _settings,
      currentOffset: () => _offset,
      activeMode: () => _activeMode,
      fallbackCharactersPerPage: () => _fallbackCharactersPerPage,
      onViewChanged: _onPaginationViewChanged,
      onJumpToOffset: _jumpToOffset,
      onSetOffset: _setOffset,
      onMessage: _showMessage,
      onPaginationError: _reportPaginationError,
      onRestartAuto: _restartAutoTimer,
      isActive: () => mounted,
    );
    _chunks = splitText(widget.text, maxChars: 700);
    _itemPositionsListener.itemPositions.addListener(_recordScrollPosition);
    if (_settings.keepAwake) _syncWakelock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _itemPositionsListener.itemPositions.removeListener(_recordScrollPosition);
    _pagination.dispose();
    _controller.removeListener(_onControllerChanged);
    _scrollSaveTimer?.cancel();
    if (_ownsController) _controller.dispose();
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    if (_controller.appActive == active) return;
    _controller.setAppActive(active);
    if (active) {
      if (_controller.lastSaveError != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _showMessage(AppStrings.saveReadingPositionFailed);
          }
        });
      }
      _restartAutoTimer();
    } else {
      _controller.cancelAutoAdvance();
      _pageTurnKey.currentState?.cancelTurn();
      _captureExactScrollPosition();
      _flushInBackground();
    }
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _onPaginationViewChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final background = Color(_settings.background.value);
    final foreground = Color(_settings.foreground.value);
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_popAfterFlush(result));
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: background,
        appBar: AppBar(
          toolbarHeight: 48,
          backgroundColor: background,
          foregroundColor: foreground,
          title: Text(widget.title),
          actions: [
            IconButton(
              tooltip: AppStrings.addBookmark,
              onPressed: widget.text.isEmpty ? null : _addBookmark,
              icon: const Icon(Icons.bookmark_add_outlined),
            ),
          ],
        ),
        drawer: _buildDrawer(),
        onDrawerChanged: (open) {
          if (open) {
            _pauseAuto(cancelTurn: true);
          } else {
            _resumeAuto();
          }
        },
        body: widget.text.isEmpty
            ? Center(
                child: Text(
                  AppStrings.emptyFile,
                  style: TextStyle(color: foreground),
                ),
              )
            : Stack(
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final pageSize = Size(
                              math.max(
                                1,
                                constraints.maxWidth -
                                    _settings.horizontalPadding * 2,
                              ),
                              math.max(1, constraints.maxHeight),
                            );
                            final mode = _activeMode;
                            WidgetsBinding.instance.addPostFrameCallback((
                              _,
                            ) async {
                              if (!mounted) return;
                              _pageSize = pageSize;
                              if (_activeMode == ReadingMode.scroll) {
                                _ensureScrollChunks(pageSize);
                              }
                              if (_paginationError == null) {
                                await _ensurePagination(pageSize);
                              }
                            });
                            return mode == ReadingMode.scroll
                                ? _buildScrollReader()
                                : _buildPageReader();
                          },
                        ),
                      ),
                      _buildSystemPageIndicator(context),
                    ],
                  ),
                  if (_controller.activeSearchMatch != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: MediaQuery.viewPaddingOf(context).bottom + 28,
                      child: _buildSearchNavigationBar(),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: ListView(
          children: [
            ListTile(
              title: Text(widget.title),
              subtitle: Text(AppStrings.currentPage(_currentPageNumber)),
            ),
            SwitchListTile(
              key: const Key('auto-mode-switch'),
              secondary: const Icon(Icons.play_circle_outline),
              title: const Text(AppStrings.autoMode),
              value: _controller.autoMode,
              onChanged:
                  widget.text.isEmpty || MediaQuery.disableAnimationsOf(context)
                  ? null
                  : _setAutoMode,
            ),
            const Divider(),
            _drawerItem(
              Icons.folder_open,
              AppStrings.openFile,
              widget.onOpenFile == null
                  ? null
                  : () async => widget.onOpenFile!(),
            ),
            _drawerItem(
              Icons.pin_drop_outlined,
              AppStrings.goToPosition,
              _showGoToDialog,
            ),
            _drawerItem(Icons.search, AppStrings.searchBody, _showSearchDialog),
            _drawerItem(
              Icons.bookmarks_outlined,
              AppStrings.bookmarks,
              _showBookmarks,
            ),
            _drawerItem(Icons.tune, AppStrings.displaySettings, _showSettings),
            _drawerItem(Icons.info_outline, AppStrings.fileInfo, _showFileInfo),
            _drawerItem(Icons.exit_to_app, AppStrings.exitApp, _exitApp),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem(
    IconData icon,
    String label,
    Future<void> Function()? action,
  ) {
    final callback = action;
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      enabled: action != null,
      onTap: callback == null
          ? null
          : () {
              Navigator.of(context).pop();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) unawaited(_runDrawerAction(callback));
              });
            },
    );
  }

  Future<void> _runDrawerAction(Future<void> Function() action) async {
    _pauseAuto(cancelTurn: true);
    try {
      await action();
    } finally {
      _resumeAuto();
    }
  }

  Widget _buildScrollReader() {
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          _scrollPositionChanged = true;
          _invalidateQueuedNavigation();
        }
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollUpdateNotification ||
              (notification is ScrollStartNotification &&
                  notification.dragDetails != null) ||
              (notification is UserScrollNotification &&
                  notification.direction != ScrollDirection.idle)) {
            if (_scrollPositionsReady) _scrollPositionChanged = true;
            _invalidateQueuedNavigation();
          }
          if (notification is ScrollEndNotification ||
              (notification is UserScrollNotification &&
                  notification.direction == ScrollDirection.idle)) {
            _scrollSaveTimer?.cancel();
            _captureExactScrollPosition();
          }
          return false;
        },
        child: SelectionArea(
          key: const Key('scroll-selection-area'),
          child: ScrollablePositionedList.builder(
            key: ValueKey(_scrollChunkLayoutKey),
            itemCount: _chunks.length,
            itemScrollController: _itemScrollController,
            scrollOffsetController: _scrollOffsetController,
            itemPositionsListener: _itemPositionsListener,
            initialScrollIndex: _chunkForOffset(_offset),
            initialAlignment: _offset > _chunks[_chunkForOffset(_offset)].start
                ? 0
                : _controller.scrollAlignment.clamp(0, 1),
            padding: EdgeInsets.fromLTRB(
              _settings.horizontalPadding,
              _scrollTopPadding,
              _settings.horizontalPadding,
              0,
            ),
            itemBuilder: (context, index) {
              final chunk = _chunks[index];
              return _buildReaderText(
                formatParagraphIndentation(
                  widget.text,
                  start: chunk.start,
                  end: chunk.end,
                  paragraphIndent: _settings.paragraphIndent,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _ensureScrollChunks(Size size) {
    final style = _textStyle;
    final key = jsonEncode({
      'algorithm': 2,
      'width': size.width,
      'height': size.height,
      'fontSize': style.fontSize,
      'fontFamily': style.fontFamily,
      'lineHeight': style.height,
      'paragraphIndent': _settings.paragraphIndent,
    });
    if (_scrollChunkLayoutKey == key || _pendingScrollChunkLayoutKey == key) {
      return;
    }
    _pendingScrollChunkLayoutKey = key;
    final generation = ++_scrollChunkGeneration;
    final maxChars = math.max(128, _fallbackCharactersPerPage);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _scrollChunkGeneration ||
          _pendingScrollChunkLayoutKey != key) {
        return;
      }
      final chunks = splitText(
        widget.text,
        maxChars: maxChars,
        layoutStyle: style,
        maxWidth: size.width,
        textDirection: Directionality.of(context),
      );
      if (!mounted || generation != _scrollChunkGeneration) return;
      setState(() {
        _scrollPositionsReady = false;
        _scrollPositionChanged = false;
        _chunks = chunks;
        _scrollChunkLayoutKey = key;
        _pendingScrollChunkLayoutKey = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && generation == _scrollChunkGeneration) {
          _scrollPositionsReady = true;
          _restoreExactScrollPosition();
        }
      });
    });
  }

  Widget _buildPageReader() {
    final paginationError = _paginationError;
    if (paginationError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              const Text(AppStrings.paginationFailed),
              const SizedBox(height: 8),
              Text(
                '$paginationError',
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('pagination-retry'),
                onPressed: _retryPagination,
                icon: const Icon(Icons.refresh),
                label: const Text(AppStrings.retry),
              ),
            ],
          ),
        ),
      );
    }
    final window = _pagination.pageWindow;
    final pages = window?.pages ?? _pagination.pages;
    final pageIndex = _pagination.pageIndex;
    if (pages == null || pageIndex == null || pages.isEmpty) {
      return ValueListenableBuilder<PaginationActivity>(
        valueListenable: _controller.paginationActivity,
        builder: (context, activity, child) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                value: activity.progress == 0 ? null : activity.progress,
              ),
              const SizedBox(height: 12),
              const Text(AppStrings.calculatingPages),
            ],
          ),
        ),
      );
    }
    final safeIndex = pageIndex.clamp(0, pages.length - 1).toInt();
    return PageTurnView(
      key: _pageTurnKey,
      index: safeIndex,
      itemCount: pages.length,
      direction: _activePageTurnDirection,
      tapOnly: _activeMode == ReadingMode.tap,
      animationEnabled: _settings.pageTurnAnimationEnabled,
      onInteractionStart: _pauseAuto,
      onInteractionEnd: _resumeAuto,
      onPageChanged: (index) {
        if (!_pagination.matchesActivePages(pages)) return;
        _pendingScrollOffset = null;
        _pagination.updateCurrentPage(index);
      },
      itemBuilder: (context, index) {
        final page = pages[index];
        return Padding(
          key: Key('page-content-$index'),
          padding: EdgeInsets.fromLTRB(
            _settings.horizontalPadding,
            0,
            _settings.horizontalPadding,
            0,
          ),
          child: Align(
            alignment: Alignment.topLeft,
            child: SelectionArea(
              child: _buildReaderText(
                formatParagraphIndentation(
                  widget.text,
                  start: page.displayStart,
                  end: page.end,
                  paragraphIndent: _settings.paragraphIndent,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _ensurePagination(Size pageSize) async {
    try {
      await _pagination.ensurePages(
        size: pageSize,
        style: _textStyle,
        fontFileName: _settings.fontFileName,
        fontFileVersion: widget.fontLibrary?.versionFor(_settings.fontFileName),
      );
    } catch (error, stackTrace) {
      _reportPaginationError(error, stackTrace);
    }
  }

  void _reportPaginationError(Object error, StackTrace stackTrace) {
    debugPrint('Page calculation failed: $error\n$stackTrace');
    if (!mounted) return;
    setState(() => _paginationError = error);
    if (_activeMode == ReadingMode.scroll) {
      _showMessage(AppStrings.paginationFailed);
    }
  }

  void _retryPagination() {
    _pagination.resetForSettings();
    setState(() => _paginationError = null);
  }

  Widget _buildReaderText(IndentedText formatted) {
    final match = _controller.activeSearchMatch;
    if (match == null ||
        match.end <= formatted.sourceStart ||
        match.start >= formatted.sourceEnd) {
      return Text(
        formatted.text,
        style: _textStyle,
        textScaler: TextScaler.noScaling,
      );
    }

    final sourceStart = math.max(match.start, formatted.sourceStart);
    final sourceEnd = math.min(match.end, formatted.sourceEnd);
    final displayStart = formatted.displayOffsetForSource(sourceStart);
    final displayEnd = formatted.displayOffsetForSource(sourceEnd);
    return Text.rich(
      TextSpan(
        children: [
          if (displayStart > 0)
            TextSpan(text: formatted.text.substring(0, displayStart)),
          TextSpan(
            text: formatted.text.substring(displayStart, displayEnd),
            style: TextStyle(
              backgroundColor: Color(
                _settings.foreground.value,
              ).withValues(alpha: .22),
              decoration: TextDecoration.underline,
              decorationThickness: 2,
            ),
          ),
          if (displayEnd < formatted.text.length)
            TextSpan(text: formatted.text.substring(displayEnd)),
        ],
      ),
      key: match.start >= formatted.sourceStart
          ? const Key('active-search-match')
          : null,
      style: _textStyle,
      textScaler: TextScaler.noScaling,
    );
  }

  Widget _buildSearchNavigationBar() {
    return Material(
      color: Color(_settings.background.value),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Row(
          key: const Key('search-navigation-bar'),
          children: [
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _controller.searchQuery,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Color(_settings.foreground.value)),
              ),
            ),
            IconButton(
              key: const Key('search-previous'),
              tooltip: AppStrings.previousSearchResult,
              onPressed: () => _moveSearchResult(forward: false),
              icon: const Icon(Icons.keyboard_arrow_up),
            ),
            IconButton(
              key: const Key('search-next'),
              tooltip: AppStrings.nextSearchResult,
              onPressed: () => _moveSearchResult(forward: true),
              icon: const Icon(Icons.keyboard_arrow_down),
            ),
            IconButton(
              key: const Key('search-close'),
              tooltip: AppStrings.endSearch,
              onPressed: _controller.clearSearch,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemPageIndicator(BuildContext context) {
    return ValueListenableBuilder<PaginationActivity>(
      valueListenable: _controller.paginationActivity,
      builder: (context, activity, child) => ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Align(
          alignment: Alignment.bottomRight,
          heightFactor: 1,
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              end: _settings.horizontalPadding,
            ),
            child: _buildPageIndicator(),
          ),
        ),
      ),
    );
  }

  Widget _buildPageIndicator() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color(_settings.background.value).withValues(alpha: .85),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          _pageIndicatorLabel,
          key: const Key('page-indicator'),
          style: TextStyle(color: Color(_settings.foreground.value)),
        ),
      ),
    );
  }

  void _recordScrollPosition() {
    if (_activeMode != ReadingMode.scroll ||
        !_scrollPositionsReady ||
        _restoringExactScrollPosition) {
      return;
    }
    _scrollSaveTimer?.cancel();
    _scrollSaveTimer = Timer(
      const Duration(milliseconds: 80),
      _captureExactScrollPosition,
    );
  }

  void _captureExactScrollPosition() {
    if (_activeMode != ReadingMode.scroll ||
        !_scrollPositionsReady ||
        _restoringExactScrollPosition) {
      return;
    }
    final visible =
        _itemPositionsListener.itemPositions.value
            .where(
              (position) =>
                  position.itemTrailingEdge > 0 && position.itemLeadingEdge < 1,
            )
            .toList()
          ..sort((a, b) => a.itemLeadingEdge.compareTo(b.itemLeadingEdge));
    if (visible.isEmpty) return;
    final position = visible.first;
    final index = position.index;
    if (index >= _chunks.length) return;
    final pendingScrollOffset = _pendingScrollOffset;
    if (!_scrollPositionChanged &&
        pendingScrollOffset == null &&
        index == _chunkForOffset(_offset)) {
      return;
    }
    if (pendingScrollOffset != null) {
      if (index == _chunkForOffset(pendingScrollOffset)) {
        _pendingScrollOffset = null;
        return;
      }
      _registerManualNavigation();
    }
    final chunk = _chunks[index];
    final formatted = formatParagraphIndentation(
      widget.text,
      start: chunk.start,
      end: chunk.end,
      paragraphIndent: _settings.paragraphIndent,
    );
    final painter = TextPainter(
      text: TextSpan(text: formatted.text, style: _textStyle),
      textDirection: Directionality.of(context),
    )..layout(maxWidth: _pageSize?.width ?? 1);
    final hiddenPixels = math.max(
      0,
      -position.itemLeadingEdge * (_pageSize?.height ?? 1),
    );
    final textPosition = painter.getPositionForOffset(
      Offset(0, hiddenPixels.toDouble()),
    );
    final offset = formatted.sourceOffsetAt(
      painter.getLineBoundary(textPosition).start,
    );
    painter.dispose();
    const alignment = 0.0;
    if (offset == _offset &&
        (_controller.scrollAlignment - alignment).abs() < .001) {
      return;
    }
    _invalidateQueuedNavigation();
    _controller.updateOffset(offset, scrollAlignment: alignment);
  }

  void _restoreExactScrollPosition() {
    if (!_scrollPositionsReady || !_itemScrollController.isAttached) return;
    final chunk = _chunks[_chunkForOffset(_offset)];
    if (_offset <= chunk.start) return;
    final formatted = formatParagraphIndentation(
      widget.text,
      start: chunk.start,
      end: chunk.end,
      paragraphIndent: _settings.paragraphIndent,
    );
    final painter = TextPainter(
      text: TextSpan(text: formatted.text, style: _textStyle),
      textDirection: Directionality.of(context),
    )..layout(maxWidth: _pageSize?.width ?? 1);
    final pixels =
        painter
            .getOffsetForCaret(
              TextPosition(offset: formatted.displayOffsetForSource(_offset)),
              Rect.zero,
            )
            .dy +
        (chunk.start == 0 ? _scrollTopPadding : 0);
    painter.dispose();
    if (pixels <= 0) return;
    _restoringExactScrollPosition = true;
    unawaited(
      _scrollOffsetController
          .animateScroll(
            offset: pixels,
            duration: const Duration(milliseconds: 1),
          )
          .whenComplete(() {
            if (!mounted) return;
            _restoringExactScrollPosition = false;
            _pendingScrollOffset = null;
          }),
    );
  }

  int _chunkForOffset(int offset) {
    var low = 0;
    var high = _chunks.length - 1;
    while (low <= high) {
      final middle = (low + high) ~/ 2;
      final chunk = _chunks[middle];
      if (offset < chunk.start) {
        high = middle - 1;
      } else if (offset >= chunk.end) {
        low = middle + 1;
      } else {
        return middle;
      }
    }
    return low.clamp(0, _chunks.length - 1);
  }

  void _setOffset(int offset) {
    _controller.updateOffset(offset);
  }

  void _jumpToOffset(int offset) {
    _setOffset(offset);
    _pagination.navigateToOffset(offset);
    if (_activeMode == ReadingMode.scroll) {
      _pendingScrollOffset = _offset;
      if (_itemScrollController.isAttached) {
        _itemScrollController.jumpTo(index: _chunkForOffset(_offset));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _restoreExactScrollPosition();
        });
      }
    }
  }

  Future<void> _jumpToPageNumber(int page, {int? sourceOffset}) =>
      _pagination.jumpToPageNumber(page, sourceOffset: sourceOffset);

  void _setAutoMode(bool enabled) {
    if (_controller.autoMode == enabled) return;
    _controller.cancelAutoAdvance();
    if (!enabled && _settings.mode == ReadingMode.scroll) {
      _pendingScrollOffset = _offset;
    }
    _controller.setAutoMode(enabled);
    if (enabled) _jumpToOffset(_offset);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _restartAutoTimer();
    });
  }

  void _restartAutoTimer() {
    _controller.cancelAutoAdvance();
    if (!_controller.canAutoAdvance ||
        MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    final pages = _pagination.pageWindow?.pages ?? _pagination.pages;
    final index = _pagination.pageIndex;
    if (pages == null || index == null || index >= pages.length) return;
    if (pages[index].end == widget.text.length) {
      _setAutoMode(false);
      _showMessage(AppStrings.lastPageAutoStopped);
      return;
    }
    if (index + 1 >= pages.length) return;
    _controller.scheduleAutoAdvance(
      Duration(seconds: _settings.autoPageIntervalSeconds),
      _advanceAutoPage,
    );
  }

  Future<void> _advanceAutoPage() async {
    if (!_controller.canAutoAdvance) return;
    final moved =
        await _pageTurnKey.currentState?.animateNext(Axis.vertical) ?? false;
    if (!moved && mounted) _restartAutoTimer();
  }

  void _pauseAuto({bool cancelTurn = false}) {
    _controller.pauseAuto();
    if (cancelTurn) _pageTurnKey.currentState?.cancelTurn();
  }

  void _resumeAuto() {
    _controller.resumeAuto();
    if (mounted && _controller.canAutoAdvance) _restartAutoTimer();
  }

  void _scheduleSave() {
    _controller.scheduleSave();
  }

  void _addBookmark() {
    final page = _pageNumberForOffset(_offset);
    if (page == null) {
      _showMessage(AppStrings.calculatingPages);
      return;
    }
    final start = math.max(0, _offset - 20);
    final end = math.min(widget.text.length, _offset + 40);
    final excerpt = widget.text
        .substring(start, end)
        .replaceAll('\n', ' ')
        .trim();
    widget.store.addBookmark(
      widget.path,
      Bookmark(
        offset: _offset,
        excerpt: excerpt,
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ),
    );
    _scheduleSave();
    _showMessage(AppStrings.bookmarkSaved(page));
    _restartAutoTimer();
  }

  Future<void> _showGoToDialog() async {
    final totalPages = _displayTotalPages;
    if (totalPages < 1) {
      _showMessage(AppStrings.calculatingPages);
      return;
    }
    final exactRange = _pagination.complete;
    var value = '';
    final input = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(AppStrings.goToPosition),
        content: TextField(
          autofocus: true,
          keyboardType: TextInputType.number,
          onChanged: (next) => value = next,
          decoration: InputDecoration(
            labelText: AppStrings.page,
            hintText: exactRange
                ? '1~$totalPages'
                : AppStrings.approximatePageRange(totalPages),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, value),
            child: const Text(AppStrings.move),
          ),
        ],
      ),
    );
    if (input == null || !mounted) return;
    final page = int.tryParse(input.trim());
    final latestTotalPages = _displayTotalPages;
    final exactPages = _pagination.completePages;
    if (page == null ||
        page < 1 ||
        (exactPages != null && page > exactPages.length)) {
      _showMessage(AppStrings.pageRange(latestTotalPages));
      return;
    }
    await _jumpToPageNumber(page);
  }

  Future<void> _showSearchDialog() async {
    var value = '';
    final query = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(AppStrings.searchBody),
        content: TextField(autofocus: true, onChanged: (next) => value = next),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, value),
            child: const Text(AppStrings.search),
          ),
        ],
      ),
    );
    if (query == null || query.isEmpty || !mounted) return;
    final match = await _controller.startSearch(query);
    if (!mounted) return;
    if (match == null) {
      _showMessage(AppStrings.noSearchResults);
    } else {
      _jumpToOffset(match.start);
    }
  }

  Future<void> _moveSearchResult({required bool forward}) async {
    final match = forward
        ? await _controller.nextSearchResult()
        : await _controller.previousSearchResult();
    if (!mounted) return;
    if (match == null) {
      _showMessage(AppStrings.noSearchResults);
      return;
    }
    _jumpToOffset(match.start);
  }

  Future<void> _showBookmarks() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final bookmarks = widget.store.document(widget.path).bookmarks;
          if (bookmarks.isEmpty) {
            return const SizedBox(
              height: 180,
              child: Center(child: Text(AppStrings.noBookmarks)),
            );
          }
          return SafeArea(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: bookmarks.length,
              itemBuilder: (context, index) {
                final bookmark = bookmarks[index];
                return ListTile(
                  title: Text(
                    bookmark.excerpt.isEmpty
                        ? AppStrings.blankLine
                        : bookmark.excerpt,
                  ),
                  subtitle: Text(
                    '${_pageNumberForOffset(bookmark.offset)}',
                    key: Key('bookmark-page-${bookmark.offset}'),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _jumpToOffset(bookmark.offset);
                  },
                  trailing: IconButton(
                    tooltip: AppStrings.deleteBookmark,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      widget.store.removeBookmark(widget.path, bookmark.offset);
                      _scheduleSave();
                      setSheetState(() {});
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _showSettings() async {
    final fontLibrary = widget.fontLibrary;
    final fonts = fontLibrary == null
        ? <ImportedFont>[]
        : await fontLibrary.listFonts();
    if (!mounted) return;
    var draft = _settings;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => ReaderSettingsSheet(
        initialSettings: draft,
        initialFonts: fonts,
        store: widget.store,
        fontLibrary: fontLibrary,
        pickFont: widget._pickFont,
        onChanged: (settings) => draft = settings,
        onApplySettings: _applySettings,
        onSave: _controller.flush,
        onMessage: _showMessage,
      ),
    );
    if (!mounted || draft == _settings) return;
    _applySettings(draft);
  }

  void _applySettings(ReaderSettings settings) {
    _registerManualNavigation();
    _pendingScrollOffset = null;
    setState(() {
      _scrollChunkGeneration++;
      _scrollPositionsReady = false;
      _scrollPositionChanged = false;
      _scrollChunkLayoutKey = null;
      _pendingScrollChunkLayoutKey = null;
    });
    _pagination.resetForSettings();
    _paginationError = null;
    _controller.applySettings(settings);
    _syncWakelock();
  }

  void _registerManualNavigation() {
    _pagination.registerManualNavigation();
    _pendingScrollOffset = null;
  }

  void _invalidateQueuedNavigation() {
    _pagination.registerManualNavigation();
  }

  void _flushInBackground() {
    _controller.flush().catchError((Object error, StackTrace stackTrace) {
      debugPrint(AppStrings.readingStateSaveDiagnostic(error, stackTrace));
    });
  }

  Future<void> _popAfterFlush(Object? result) async {
    try {
      await _controller.flush();
    } catch (_) {
      if (mounted) _showMessage(AppStrings.saveReadingPositionFailed);
      return;
    }
    if (!mounted) return;
    setState(() => _allowPop = true);
    Navigator.of(context).pop(result);
  }

  Future<void> _exitApp() async {
    try {
      await _controller.flush();
    } catch (_) {
      if (mounted) _showMessage(AppStrings.saveReadingPositionFailed);
      return;
    }
    await SystemNavigator.pop();
  }

  Future<void> _syncWakelock() =>
      WakelockPlus.toggle(enable: _settings.keepAwake);

  Future<void> _showFileInfo() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(AppStrings.fileInfo),
        content: SelectableText(
          AppStrings.fileDetails(
            widget.path,
            _formatBytes(widget.fileSize),
            _encodingLabel(widget.encoding),
          ),
        ),
        actions: [
          if (widget.onEncodingChanged != null)
            PopupMenuButton<TextEncoding>(
              onSelected: (encoding) {
                Navigator.pop(dialogContext);
                widget.onEncodingChanged!(encoding);
              },
              itemBuilder: _encodingItems,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text(AppStrings.changeEncoding),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(AppStrings.close),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  int? _pageNumberForOffset(int offset) =>
      _pagination.pageNumberForOffset(offset);
}

List<PopupMenuEntry<TextEncoding>> _encodingItems(BuildContext context) {
  return TextEncoding.values
      .map(
        (encoding) => PopupMenuItem(
          value: encoding,
          child: Text(_encodingLabel(encoding)),
        ),
      )
      .toList();
}

TextEncoding? _encodingByName(String? name) {
  for (final encoding in TextEncoding.values) {
    if (encoding.name == name) return encoding;
  }
  return null;
}

String _encodingLabel(TextEncoding encoding) => switch (encoding) {
  TextEncoding.utf8 => 'UTF-8',
  TextEncoding.utf16le => 'UTF-16 LE',
  TextEncoding.utf16be => 'UTF-16 BE',
  TextEncoding.cp949 => 'CP949 / EUC-KR',
};

String _fileName(String path) => path.split(Platform.pathSeparator).last;

String _formatBytes(int? bytes) {
  if (bytes == null) return AppStrings.unknown;
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
