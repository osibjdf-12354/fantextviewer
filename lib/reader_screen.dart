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
import 'reader_settings_sheet.dart';
import 'text_document.dart';
import 'text_paginator.dart';

export 'reader_settings_sheet.dart' show contrastRatio;

typedef ReaderPaginator =
    Future<List<TextPage>> Function({
      required String text,
      required Size size,
      required TextStyle style,
      required int paragraphIndent,
      ValueChanged<double>? onProgress,
      PaginationBatchCallback? onBatch,
      TextLayoutCallback? onLayout,
      bool Function()? isCancelled,
    });

typedef ReaderWindowPaginator =
    Future<List<TextPage>> Function({
      required String text,
      required int startOffset,
      required Size size,
      required TextStyle style,
      required int paragraphIndent,
      TextLayoutCallback? onLayout,
      bool Function()? isCancelled,
    });

const _eagerScrollPaginationLimit = 256 * 1024;
const _initialPaginationPageBudget = 32;

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.path,
    required this.store,
    this.fontLibrary,
  });

  final String path;
  final AppStore store;
  final FontLibrary? fontLibrary;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _pageIndexCache = PageIndexCache();
  DecodedText? _document;
  FileStat? _stat;
  Object? _error;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
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
      widget.store.updateFileFingerprint(
        widget.path,
        fileSize: stat.size,
        modified: stat.modified,
      );
      final saved = widget.store.document(widget.path).encoding;
      final encoding = forced ?? _encodingByName(saved);
      if (stat.size > 32 * 1024 * 1024) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || generation != _generation) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('큰 파일을 여는 중입니다. 잠시 기다려 주세요.')),
          );
        });
      }
      final document = await loadTextFile(widget.path, forced: encoding);
      final decodedStat = await file.stat();
      if (decodedStat.size != stat.size ||
          decodedStat.modified.toUtc() != stat.modified.toUtc()) {
        throw const FileSystemException('읽는 동안 파일이 변경되었습니다. 다시 시도해 주세요.');
      }
      if (!mounted || generation != _generation) return;

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
      await widget.store.save();
      if (!mounted || generation != _generation) return;
      setState(() {
        _document = document;
        _stat = stat;
      });
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
                      const Text('파일을 읽지 못했습니다.'),
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
                            child: const Text('다시 시도'),
                          ),
                          PopupMenuButton<TextEncoding>(
                            onSelected: _load,
                            itemBuilder: _encodingItems,
                            child: const Padding(
                              padding: EdgeInsets.all(12),
                              child: Text('인코딩으로 열기'),
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

    return ReaderView(
      key: ValueKey('${widget.path}:${document.encoding.name}'),
      path: widget.path,
      title: _fileName(widget.path),
      text: document.text,
      encoding: document.encoding,
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
    this.fileSize,
    this.modified,
    this.pageIndexCache,
    this.paginator = paginateText,
    this.windowPaginator = paginateTextWindow,
    this.onEncodingChanged,
    this.onOpenFile,
    this.fontLibrary,
    this.pickFont = pickFontFile,
    this.controller,
  });

  final String path;
  final String title;
  final String text;
  final TextEncoding encoding;
  final AppStore store;
  final int? fileSize;
  final DateTime? modified;
  final PageIndexCache? pageIndexCache;
  final ReaderPaginator paginator;
  final ReaderWindowPaginator windowPaginator;
  final ValueChanged<TextEncoding>? onEncodingChanged;
  final VoidCallback? onOpenFile;
  final FontLibrary? fontLibrary;
  final Future<String?> Function() pickFont;
  final ReaderController? controller;

  @override
  State<ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends State<ReaderView> with WidgetsBindingObserver {
  late final ReaderController _controller;
  late final bool _ownsController;
  late List<TextChunk> _chunks;
  final _itemScrollController = ItemScrollController();
  final _itemPositionsListener = ItemPositionsListener.create();
  final _pageTurnKey = GlobalKey<PageTurnViewState>();
  Timer? _autoTimer;
  bool _autoMode = false;
  int _autoPauseDepth = 0;
  bool _appActive = true;
  List<TextPage>? _pages;
  int? _pageIndex;
  int? _pendingTargetPage;
  int? _pendingPageOffset;
  int? _pendingScrollOffset;
  Size? _pageSize;
  ({List<TextPage> pages, int firstPage})? _pageWindow;
  int _pageWindowGeneration = 0;
  int _navigationGeneration = 0;
  int _displayPageNumber = 1;
  String? _paginationKey;
  int _paginationGeneration = 0;
  bool _paginationComplete = false;
  bool _fullPaginationRequested = false;
  bool _allowPop = false;
  String? _scrollChunkLayoutKey;
  String? _pendingScrollChunkLayoutKey;
  int _scrollChunkGeneration = 0;
  bool _scrollPositionsReady = false;
  bool _scrollPositionChanged = false;

  ReaderSettings get _settings => _controller.settings;
  int get _offset => _controller.offset;
  List<TextPage>? get _completePages => _paginationComplete ? _pages : null;
  ReadingMode get _activeMode => _autoMode ? ReadingMode.page : _settings.mode;
  PageTurnDirection get _activePageTurnDirection =>
      _autoMode ? PageTurnDirection.vertical : _settings.pageTurnDirection;
  bool get _isPaged => _activeMode != ReadingMode.scroll;

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

  int get _displayTotalPages {
    final exactPages = _completePages;
    if (exactPages != null) return exactPages.length;
    return estimatedPageCount(
      widget.text.length,
      _pages ?? const [],
      fallbackCharactersPerPage: _fallbackCharactersPerPage,
    );
  }

  int get _currentPageNumber {
    if (_pageWindow != null) return _displayPageNumber;
    final pages = _pages;
    if (pages != null &&
        pages.isNotEmpty &&
        (_paginationComplete || _offset < pages.last.end)) {
      return pageForOffset(pages, _offset) + 1;
    }
    return estimatedPageForOffset(
      _offset,
      textLength: widget.text.length,
      totalPages: _displayTotalPages,
    );
  }

  bool get _hasIndexedCurrentPage {
    final pages = _pages;
    return _pageWindow == null &&
        pages != null &&
        pages.isNotEmpty &&
        (_paginationComplete || _offset < pages.last.end);
  }

  String get _pageIndicatorLabel {
    if (!_hasIndexedCurrentPage ||
        (_settings.showTotalPages && !_paginationComplete)) {
      return '계산 중';
    }
    return _settings.showTotalPages
        ? '$_currentPageNumber/${_completePages!.length}'
        : '$_currentPageNumber';
  }

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
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ??
        ReaderController(
          store: widget.store,
          path: widget.path,
          textLength: widget.text.length,
          text: widget.text,
        );
    _chunks = splitText(widget.text, maxChars: 700);
    _itemPositionsListener.itemPositions.addListener(_recordScrollPosition);
    if (_settings.keepAwake) _syncWakelock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _itemPositionsListener.itemPositions.removeListener(_recordScrollPosition);
    _autoTimer?.cancel();
    if (_ownsController) _controller.dispose();
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    if (_appActive == active) return;
    _appActive = active;
    if (active) {
      if (_controller.lastSaveError != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showMessage('읽기 위치를 저장하지 못했습니다.');
        });
      }
      _restartAutoTimer();
    } else {
      _autoTimer?.cancel();
      _pageTurnKey.currentState?.cancelTurn();
      _flushInBackground();
    }
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
              tooltip: '북마크 추가',
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
                child: Text('빈 파일입니다.', style: TextStyle(color: foreground)),
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
                            _pageSize = pageSize;
                            if (_activeMode == ReadingMode.scroll) {
                              _ensureScrollChunks(pageSize);
                            }
                            _ensurePages(pageSize);
                            return _activeMode == ReadingMode.scroll
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
              subtitle: Text('현재 $_currentPageNumber페이지'),
            ),
            SwitchListTile(
              key: const Key('auto-mode-switch'),
              secondary: const Icon(Icons.play_circle_outline),
              title: const Text('오토모드'),
              value: _autoMode,
              onChanged: widget.text.isEmpty ? null : _setAutoMode,
            ),
            const Divider(),
            _drawerItem(
              Icons.folder_open,
              '파일 열기',
              widget.onOpenFile == null
                  ? null
                  : () async => widget.onOpenFile!(),
            ),
            _drawerItem(Icons.pin_drop_outlined, '위치 이동', _showGoToDialog),
            _drawerItem(Icons.search, '본문 검색', _showSearchDialog),
            _drawerItem(Icons.bookmarks_outlined, '북마크', _showBookmarks),
            _drawerItem(Icons.tune, '표시 설정', _showSettings),
            _drawerItem(Icons.info_outline, '파일 정보', _showFileInfo),
            _drawerItem(Icons.exit_to_app, '앱 종료', _exitApp),
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
          return false;
        },
        child: SelectionArea(
          key: const Key('scroll-selection-area'),
          child: ScrollablePositionedList.builder(
            key: ValueKey(_scrollChunkLayoutKey),
            itemCount: _chunks.length,
            itemScrollController: _itemScrollController,
            itemPositionsListener: _itemPositionsListener,
            initialScrollIndex: _chunkForOffset(_offset),
            initialAlignment: _controller.scrollAlignment.clamp(0, 1),
            padding: EdgeInsets.fromLTRB(
              _settings.horizontalPadding,
              16,
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
        }
      });
    });
  }

  Widget _buildPageReader() {
    final window = _pageWindow;
    final pages = window?.pages ?? _pages;
    final pageIndex = _pageIndex;
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
              const Text('페이지를 계산하고 있습니다.'),
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
        final activePages = _pageWindow?.pages ?? _pages;
        if (!identical(activePages, pages)) return;
        _registerManualNavigation();
        final nextOffset = pages[index].start;
        setState(() {
          _pageIndex = index;
          _displayPageNumber = window == null
              ? index + 1
              : window.firstPage + index;
          _pendingPageOffset = null;
          _pendingScrollOffset = null;
          _setOffset(nextOffset);
        });
        if (window == null &&
            !_paginationComplete &&
            index >= pages.length - 4) {
          _requestFullPagination();
        }
        _restartAutoTimer();
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
              tooltip: '이전 검색 결과',
              onPressed: () => _moveSearchResult(forward: false),
              icon: const Icon(Icons.keyboard_arrow_up),
            ),
            IconButton(
              key: const Key('search-next'),
              tooltip: '다음 검색 결과',
              onPressed: () => _moveSearchResult(forward: true),
              icon: const Icon(Icons.keyboard_arrow_down),
            ),
            IconButton(
              key: const Key('search-close'),
              tooltip: '검색 종료',
              onPressed: () {
                setState(_controller.clearSearch);
              },
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

  void _requestFullPagination() {
    if (_fullPaginationRequested ||
        widget.text.length <= _eagerScrollPaginationLimit) {
      return;
    }
    final size = _pageSize;
    if (size == null) return;
    _fullPaginationRequested = true;
    _paginationKey = null;
    _ensurePages(size);
    if (_isPaged) setState(() {});
  }

  void _ensurePages(Size size) {
    final textStyle = _textStyle;
    final key = jsonEncode({
      'algorithm': 6,
      'path': widget.path,
      'fileSize': widget.fileSize,
      'modified': widget.modified?.toUtc().toIso8601String(),
      'textLength': widget.text.length,
      'encoding': widget.encoding.name,
      'width': size.width,
      'height': size.height,
      'fontSize': textStyle.fontSize,
      'fontFileName': _settings.fontFileName,
      'fontFileVersion': widget.fontLibrary?.versionFor(_settings.fontFileName),
      'lineHeight': _settings.lineHeight,
      'horizontalPadding': _settings.horizontalPadding,
      'paragraphIndent': _settings.paragraphIndent,
      'fullPagination': _fullPaginationRequested || _settings.showTotalPages,
    });
    if (_paginationKey == key) return;
    _paginationKey = key;
    _pageWindowGeneration++;
    _pageWindow = null;
    _pages = null;
    _paginationComplete = false;
    _pageIndex = null;
    final generation = ++_paginationGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || generation != _paginationGeneration) return;
      _controller.resetPaginationActivity();
      final cache = widget.pageIndexCache;
      if (cache != null) {
        final cached = await cache.load(
          signature: key,
          textLength: widget.text.length,
        );
        if (!mounted || generation != _paginationGeneration) return;
        if (cached != null) {
          _setPaginationPages(cached, complete: true);
          _controller.updatePaginationProgress(1);
          return;
        }
      }
      if (_isPaged &&
          widget.text.length > _eagerScrollPaginationLimit &&
          _offset > 0) {
        await _jumpToPageNumber(_currentPageNumber, sourceOffset: _offset);
        if (!mounted || generation != _paginationGeneration) return;
      }
      final progressivePages = <TextPage>[];
      final bounded =
          widget.text.length > _eagerScrollPaginationLimit &&
          !_fullPaginationRequested &&
          !_settings.showTotalPages;
      final pages = await widget.paginator(
        text: widget.text,
        size: size,
        style: textStyle,
        paragraphIndent: _settings.paragraphIndent,
        onProgress: (progress) {
          if (!mounted || generation != _paginationGeneration) return;
          _controller.updatePaginationProgress(progress);
        },
        onBatch: (batch) {
          if (!mounted ||
              generation != _paginationGeneration ||
              batch.isEmpty) {
            return;
          }
          progressivePages.addAll(batch);
          _setPaginationPages(progressivePages, complete: false);
        },
        isCancelled: () =>
            !mounted ||
            generation != _paginationGeneration ||
            (bounded &&
                progressivePages.length >= _initialPaginationPageBudget),
      );
      if (!mounted || generation != _paginationGeneration) return;
      final complete =
          pages.isNotEmpty &&
          pages.first.start == 0 &&
          pages.last.end == widget.text.length;
      _setPaginationPages(pages, complete: complete);
      if (complete) _controller.updatePaginationProgress(1);
      if (complete && cache != null) {
        await cache.save(
          signature: key,
          textLength: widget.text.length,
          pages: pages,
        );
      }
    });
  }

  void _setPaginationPages(List<TextPage> pages, {required bool complete}) {
    final initialPage = pages.isEmpty ? 0 : pageForOffset(pages, _offset);
    if (complete) {
      _pageWindowGeneration++;
      _pageWindow = null;
      _pageIndex = pages.isEmpty ? null : initialPage;
      _displayPageNumber = initialPage + 1;
    } else if (_pageWindow == null &&
        _pageIndex == null &&
        pages.isNotEmpty &&
        pages.last.end > _offset) {
      _pageIndex = initialPage;
    }
    if (_activeMode == ReadingMode.scroll) {
      _pages = pages;
      _paginationComplete = complete;
      _controller.notifyPaginationChanged();
    } else {
      setState(() {
        _pages = pages;
        _paginationComplete = complete;
      });
    }
    final pendingTargetPage = _pendingTargetPage;
    if (pendingTargetPage != null) {
      if (pendingTargetPage <= pages.length) {
        final targetOffset = pages[pendingTargetPage - 1].start;
        final generation = _paginationGeneration;
        final navigationGeneration = _navigationGeneration;
        _pendingTargetPage = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              generation != _paginationGeneration ||
              navigationGeneration != _navigationGeneration) {
            return;
          }
          _jumpToOffset(targetOffset);
        });
      } else if (complete) {
        _pendingTargetPage = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showMessage('1~${pages.length} 사이 페이지를 입력해 주세요.');
        });
      }
    }
    final pendingOffset = _pendingPageOffset;
    if (_isPaged &&
        _pageWindow == null &&
        pendingOffset != null &&
        pages.isNotEmpty &&
        (complete || pendingOffset < pages.last.end)) {
      final page = pageForOffset(pages, pendingOffset);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _pendingPageOffset != pendingOffset) return;
        setState(() {
          _pendingPageOffset = null;
          _pageIndex = page;
          _displayPageNumber = page + 1;
        });
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _restartAutoTimer();
    });
  }

  void _recordScrollPosition() {
    if (_activeMode != ReadingMode.scroll || !_scrollPositionsReady) {
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
    final anchored = visible.where((position) => position.itemLeadingEdge >= 0);
    final position = anchored.isEmpty ? visible.last : anchored.first;
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
    final offset = _chunks[index].start;
    final alignment = position.itemLeadingEdge.clamp(0, 1).toDouble();
    if (offset == _offset &&
        (_controller.scrollAlignment - alignment).abs() < .001) {
      return;
    }
    _invalidateQueuedNavigation();
    _pendingPageOffset = null;
    setState(
      () => _controller.updateOffset(offset, scrollAlignment: alignment),
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
    _navigationGeneration++;
    _pendingTargetPage = null;
    _pendingPageOffset = null;
    setState(() => _setOffset(offset));
    if (_activeMode == ReadingMode.scroll) {
      _pendingScrollOffset = _offset;
      if (_itemScrollController.isAttached) {
        _itemScrollController.jumpTo(index: _chunkForOffset(_offset));
      }
      return;
    }
    final window = _pageWindow;
    if (window != null) {
      if (_offset >= window.pages.first.start &&
          _offset < window.pages.last.end) {
        final page = pageForOffset(window.pages, _offset);
        setState(() {
          _pageIndex = page;
          _displayPageNumber = window.firstPage + page;
        });
      } else {
        final total = _displayTotalPages;
        setState(() => _pageIndex = null);
        unawaited(
          _jumpToPageNumber(
            estimatedPageForOffset(
              _offset,
              textLength: widget.text.length,
              totalPages: total,
            ),
            sourceOffset: _offset,
          ),
        );
      }
      return;
    }
    final pages = _pages;
    if (pages != null &&
        pages.isNotEmpty &&
        (_paginationComplete || _offset < pages.last.end)) {
      final page = pageForOffset(pages, _offset);
      setState(() {
        _pageIndex = page;
        _displayPageNumber = page + 1;
      });
    } else {
      final totalPages = _displayTotalPages;
      setState(() => _pageIndex = null);
      unawaited(
        _jumpToPageNumber(
          estimatedPageForOffset(
            _offset,
            textLength: widget.text.length,
            totalPages: totalPages,
          ),
          sourceOffset: _offset,
        ),
      );
    }
  }

  Future<void> _jumpToPageNumber(int page, {int? sourceOffset}) async {
    if (page < 1) {
      _showMessage('1 이상의 페이지를 입력해 주세요.');
      return;
    }
    final exactPages = _completePages;
    if (exactPages != null) {
      if (sourceOffset == null && page > exactPages.length) {
        _showMessage('1~${exactPages.length} 사이 페이지를 입력해 주세요.');
        return;
      }
      final exactPage = sourceOffset == null
          ? page - 1
          : pageForOffset(exactPages, sourceOffset);
      _jumpToOffset(exactPages[exactPage].start);
      return;
    }
    final indexedPages = _pages;
    if (sourceOffset == null &&
        indexedPages != null &&
        page <= indexedPages.length) {
      _jumpToOffset(indexedPages[page - 1].start);
      return;
    }
    if (sourceOffset == null) {
      _navigationGeneration++;
      _pendingTargetPage = page;
      _requestFullPagination();
      _showMessage('$page페이지까지 계산하고 있습니다. 계산되는 즉시 이동합니다.');
      return;
    }

    final totalPages = _displayTotalPages;
    final targetOffset = sourceOffset;
    if (_activeMode == ReadingMode.scroll) {
      _jumpToOffset(targetOffset);
      return;
    }

    final size = _pageSize;
    if (size == null) return;
    final measuredPages = _pages;
    final charactersPerPage = measuredPages == null || measuredPages.isEmpty
        ? _fallbackCharactersPerPage
        : math
              .max(1, (measuredPages.last.end / measuredPages.length).round())
              .toInt();
    final startOffset = math
        .max(0, targetOffset - charactersPerPage * math.min(4, page - 1))
        .toInt();
    final paginationGeneration = _paginationGeneration;
    final windowGeneration = ++_pageWindowGeneration;
    final navigationGeneration = _navigationGeneration;
    bool cancelled() =>
        !mounted ||
        paginationGeneration != _paginationGeneration ||
        windowGeneration != _pageWindowGeneration ||
        navigationGeneration != _navigationGeneration;

    var pages = await widget.windowPaginator(
      text: widget.text,
      startOffset: startOffset,
      size: size,
      style: _textStyle,
      paragraphIndent: _settings.paragraphIndent,
      isCancelled: cancelled,
    );
    if (cancelled()) return;
    if (pages.isNotEmpty &&
        targetOffset >= pages.last.end &&
        pages.last.end < widget.text.length) {
      pages = await widget.windowPaginator(
        text: widget.text,
        startOffset: targetOffset,
        size: size,
        style: _textStyle,
        paragraphIndent: _settings.paragraphIndent,
        isCancelled: cancelled,
      );
    }
    if (cancelled() || pages.isEmpty) return;

    var localPage = pageForOffset(pages, targetOffset);
    if (localPage >= page) {
      final drop = localPage - (page - 1);
      pages = pages.sublist(drop);
      localPage -= drop;
    }
    final firstPage = page - localPage;
    final remainingPages = totalPages - firstPage + 1;
    if (pages.length > remainingPages) {
      pages = pages.sublist(0, remainingPages);
    }

    setState(() {
      _pageWindow = (pages: pages, firstPage: firstPage);
      _pageIndex = localPage;
      _displayPageNumber = page;
      _pendingPageOffset = null;
      _setOffset(sourceOffset);
    });
    _restartAutoTimer();
  }

  void _setAutoMode(bool enabled) {
    if (_autoMode == enabled) return;
    _autoTimer?.cancel();
    if (!enabled && _settings.mode == ReadingMode.scroll) {
      _pendingScrollOffset = _offset;
    }
    setState(() => _autoMode = enabled);
    if (enabled) _jumpToOffset(_offset);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _restartAutoTimer();
    });
  }

  void _restartAutoTimer() {
    _autoTimer?.cancel();
    if (!_autoMode || _autoPauseDepth > 0 || !_appActive) return;
    final pages = _pageWindow?.pages ?? _pages;
    final index = _pageIndex;
    if (pages == null || index == null || index >= pages.length) return;
    if (pages[index].end == widget.text.length) {
      _setAutoMode(false);
      _showMessage('마지막 페이지입니다. 오토모드를 종료했습니다.');
      return;
    }
    if (_pageWindow == null &&
        !_paginationComplete &&
        index >= pages.length - 4) {
      _requestFullPagination();
    }
    if (index + 1 >= pages.length) return;
    _autoTimer = Timer(
      Duration(seconds: _settings.autoPageIntervalSeconds),
      () => unawaited(_advanceAutoPage()),
    );
  }

  Future<void> _advanceAutoPage() async {
    if (!_autoMode || _autoPauseDepth > 0 || !_appActive) return;
    final moved =
        await _pageTurnKey.currentState?.animateNext(Axis.vertical) ?? false;
    if (!moved && mounted) _restartAutoTimer();
  }

  void _pauseAuto({bool cancelTurn = false}) {
    _autoPauseDepth++;
    _autoTimer?.cancel();
    if (cancelTurn) _pageTurnKey.currentState?.cancelTurn();
  }

  void _resumeAuto() {
    if (_autoPauseDepth > 0) _autoPauseDepth--;
    if (mounted && _autoPauseDepth == 0) _restartAutoTimer();
  }

  void _scheduleSave() {
    _controller.scheduleSave();
  }

  void _addBookmark() {
    final page = _pageNumberForOffset(_offset);
    if (page == null) {
      _showMessage('페이지를 계산하고 있습니다.');
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
    _showMessage('$page에 북마크를 저장했습니다.');
    _restartAutoTimer();
  }

  Future<void> _showGoToDialog() async {
    final totalPages = _displayTotalPages;
    if (totalPages < 1) {
      _showMessage('페이지를 계산하고 있습니다.');
      return;
    }
    final exactRange = _paginationComplete;
    var value = '';
    final input = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('위치 이동'),
        content: TextField(
          autofocus: true,
          keyboardType: TextInputType.number,
          onChanged: (next) => value = next,
          decoration: InputDecoration(
            labelText: '페이지',
            hintText: exactRange ? '1~$totalPages' : '약 1~$totalPages (추정)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, value),
            child: const Text('이동'),
          ),
        ],
      ),
    );
    if (input == null || !mounted) return;
    final page = int.tryParse(input.trim());
    final latestTotalPages = _displayTotalPages;
    final exactPages = _completePages;
    if (page == null ||
        page < 1 ||
        (exactPages != null && page > exactPages.length)) {
      _showMessage('1~$latestTotalPages 사이 페이지를 입력해 주세요.');
      return;
    }
    await _jumpToPageNumber(page);
  }

  Future<void> _showSearchDialog() async {
    var value = '';
    final query = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('본문 검색'),
        content: TextField(autofocus: true, onChanged: (next) => value = next),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, value),
            child: const Text('검색'),
          ),
        ],
      ),
    );
    if (query == null || query.isEmpty || !mounted) return;
    final match = _controller.startSearch(query);
    if (match == null) {
      _showMessage('검색 결과가 없습니다.');
    } else {
      _jumpToOffset(match.start);
    }
  }

  void _moveSearchResult({required bool forward}) {
    final match = forward
        ? _controller.nextSearchResult()
        : _controller.previousSearchResult();
    if (match == null) {
      _showMessage('검색 결과가 없습니다.');
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
              child: Center(child: Text('저장된 북마크가 없습니다.')),
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
                    bookmark.excerpt.isEmpty ? '빈 줄' : bookmark.excerpt,
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
                    tooltip: '북마크 삭제',
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
        pickFont: widget.pickFont,
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
    _paginationGeneration++;
    _pageWindowGeneration++;
    _pendingPageOffset = null;
    _pendingScrollOffset = null;
    setState(() {
      _controller.applySettings(settings);
      _fullPaginationRequested = settings.showTotalPages;
      _scrollChunkGeneration++;
      _scrollPositionsReady = false;
      _scrollPositionChanged = false;
      _scrollChunkLayoutKey = null;
      _pendingScrollChunkLayoutKey = null;
      _paginationKey = null;
      _pages = null;
      _pageWindow = null;
      _pageIndex = null;
      _paginationComplete = false;
    });
    _syncWakelock();
  }

  void _registerManualNavigation() {
    _invalidateQueuedNavigation();
    _pendingScrollOffset = null;
  }

  void _invalidateQueuedNavigation() {
    _navigationGeneration++;
    _pendingTargetPage = null;
  }

  void _flushInBackground() {
    _controller.flush().catchError((Object error, StackTrace stackTrace) {
      debugPrint('읽기 상태 저장 실패: $error\n$stackTrace');
    });
  }

  Future<void> _popAfterFlush(Object? result) async {
    try {
      await _controller.flush();
    } catch (_) {
      if (mounted) _showMessage('읽기 위치를 저장하지 못했습니다.');
    }
    if (!mounted) return;
    setState(() => _allowPop = true);
    Navigator.of(context).pop(result);
  }

  Future<void> _exitApp() async {
    try {
      await _controller.flush();
    } catch (_) {
      if (mounted) _showMessage('읽기 위치를 저장하지 못했습니다.');
    }
    await SystemNavigator.pop();
  }

  Future<void> _syncWakelock() =>
      WakelockPlus.toggle(enable: _settings.keepAwake);

  Future<void> _showFileInfo() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('파일 정보'),
        content: SelectableText(
          '${widget.path}\n\n크기: ${_formatBytes(widget.fileSize)}\n인코딩: ${_encodingLabel(widget.encoding)}',
        ),
        actions: [
          if (widget.onEncodingChanged != null)
            PopupMenuButton<TextEncoding>(
              onSelected: (encoding) {
                Navigator.pop(dialogContext);
                widget.store.setEncoding(widget.path, encoding.name);
                _scheduleSave();
                widget.onEncodingChanged!(encoding);
              },
              itemBuilder: _encodingItems,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text('인코딩 변경'),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('닫기'),
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

  int? _pageNumberForOffset(int offset) {
    if (widget.text.isEmpty) return null;
    if (_pageWindow != null && offset == _offset) return _displayPageNumber;
    final pages = _pages;
    if (pages != null &&
        pages.isNotEmpty &&
        (_paginationComplete || offset < pages.last.end)) {
      return pageForOffset(pages, offset) + 1;
    }
    return estimatedPageForOffset(
      offset,
      textLength: widget.text.length,
      totalPages: _displayTotalPages,
    );
  }
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
  if (bytes == null) return '알 수 없음';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
