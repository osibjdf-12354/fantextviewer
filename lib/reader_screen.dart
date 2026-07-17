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
import 'models.dart';
import 'page_index_cache.dart';
import 'text_document.dart';
import 'text_paginator.dart';

typedef ReaderPaginator =
    Future<List<TextPage>> Function({
      required String text,
      required Size size,
      required TextStyle style,
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
      TextLayoutCallback? onLayout,
      bool Function()? isCancelled,
    });

const _eagerScrollPaginationLimit = 256 * 1024;

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.path, required this.store});

  final String path;
  final AppStore store;

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
      final saved = widget.store.document(widget.path).encoding;
      final encoding = forced ?? _encodingByName(saved);
      final document = await loadTextFile(widget.path, forced: encoding);
      final stat = await file.stat();
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
      if (stat.size > 50 * 1024 * 1024) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('파일이 매우 커서 처음 여는 데 시간이 걸릴 수 있습니다.')),
          );
        });
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

  @override
  State<ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends State<ReaderView> {
  late ReaderSettings _settings;
  late List<TextChunk> _chunks;
  late int _offset;
  final _itemScrollController = ItemScrollController();
  final _itemPositionsListener = ItemPositionsListener.create();
  Timer? _saveTimer;
  List<TextPage>? _pages;
  PageController? _pageController;
  int? _pageControllerInitialOffset;
  int? _pendingTargetPage;
  int? _pendingPageOffset;
  int? _pendingScrollOffset;
  Size? _pageSize;
  ({List<TextPage> pages, int firstPage})? _pageWindow;
  int _pageWindowGeneration = 0;
  int _navigationGeneration = 0;
  int _displayPageNumber = 1;
  String? _paginationKey;
  double _paginationProgress = 0;
  int _paginationGeneration = 0;
  bool _paginationComplete = false;

  List<TextPage>? get _completePages => _paginationComplete ? _pages : null;

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

  TextStyle get _textStyle => TextStyle(
    color: Color(_settings.foreground.value),
    fontSize: _settings.fontSize,
    height: _settings.lineHeight,
  );

  @override
  void initState() {
    super.initState();
    _settings = widget.store.data.settings;
    _chunks = splitText(widget.text, maxChars: 700);
    _offset = widget.store
        .document(widget.path)
        .offset
        .clamp(0, widget.text.length);
    _itemPositionsListener.itemPositions.addListener(_recordScrollPosition);
    if (_settings.keepAwake) _syncWakelock();
  }

  @override
  void dispose() {
    _itemPositionsListener.itemPositions.removeListener(_recordScrollPosition);
    _saveTimer?.cancel();
    _pageController?.dispose();
    unawaited(widget.store.save());
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final background = Color(_settings.background.value);
    final foreground = Color(_settings.foreground.value);
    return Scaffold(
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
      body: widget.text.isEmpty
          ? Center(
              child: Text('빈 파일입니다.', style: TextStyle(color: foreground)),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final pageSize = Size(
                  math.max(
                    1,
                    constraints.maxWidth - _settings.horizontalPadding * 2,
                  ),
                  math.max(1, constraints.maxHeight),
                );
                _pageSize = pageSize;
                if (_settings.mode == ReadingMode.page ||
                    widget.text.length <= _eagerScrollPaginationLimit ||
                    _paginationKey != null) {
                  _ensurePages(pageSize);
                }
                return _settings.mode == ReadingMode.scroll
                    ? _buildScrollReader()
                    : _buildPageReader();
              },
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
            const Divider(),
            _drawerItem(Icons.folder_open, '파일 열기', widget.onOpenFile),
            _drawerItem(Icons.pin_drop_outlined, '위치 이동', _showGoToDialog),
            _drawerItem(Icons.search, '본문 검색', _showSearchDialog),
            _drawerItem(Icons.bookmarks_outlined, '북마크', _showBookmarks),
            _drawerItem(Icons.tune, '표시 설정', _showSettings),
            _drawerItem(Icons.info_outline, '파일 정보', _showFileInfo),
            _drawerItem(Icons.exit_to_app, '앱 종료', () => SystemNavigator.pop()),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem(IconData icon, String label, VoidCallback? action) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      enabled: action != null,
      onTap: action == null
          ? null
          : () {
              Navigator.of(context).pop();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) action();
              });
            },
    );
  }

  Widget _buildScrollReader() {
    return Stack(
      children: [
        Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) _invalidateQueuedNavigation();
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollUpdateNotification ||
                  (notification is ScrollStartNotification &&
                      notification.dragDetails != null) ||
                  (notification is UserScrollNotification &&
                      notification.direction != ScrollDirection.idle)) {
                _invalidateQueuedNavigation();
              }
              return false;
            },
            child: ScrollablePositionedList.builder(
              itemCount: _chunks.length,
              itemScrollController: _itemScrollController,
              itemPositionsListener: _itemPositionsListener,
              initialScrollIndex: _chunkForOffset(_offset),
              initialAlignment: widget.store
                  .document(widget.path)
                  .scrollAlignment
                  .clamp(0, 1),
              padding: EdgeInsets.fromLTRB(
                _settings.horizontalPadding,
                16,
                _settings.horizontalPadding,
                56,
              ),
              itemBuilder: (context, index) {
                return SelectableText(_chunks[index].text, style: _textStyle);
              },
            ),
          ),
        ),
        _buildPageIndicator(),
      ],
    );
  }

  Widget _buildPageReader() {
    final window = _pageWindow;
    final pages = window?.pages ?? _pages;
    final controller = _pageController;
    if (pages == null || controller == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              value: _paginationProgress == 0 ? null : _paginationProgress,
            ),
            const SizedBox(height: 12),
            const Text('페이지를 계산하고 있습니다.'),
          ],
        ),
      );
    }
    return Stack(
      children: [
        NotificationListener<UserScrollNotification>(
          onNotification: (notification) {
            if (notification.direction != ScrollDirection.idle) {
              _registerManualNavigation();
            }
            return false;
          },
          child: PageView.builder(
            key: ObjectKey(controller),
            controller: controller,
            itemCount: pages.length,
            onPageChanged: (index) {
              if (!identical(controller, _pageController)) return;
              final initialOffset = _pageControllerInitialOffset;
              _pageControllerInitialOffset = null;
              final nextOffset =
                  initialOffset != null &&
                      pageForOffset(pages, initialOffset) == index
                  ? initialOffset
                  : pages[index].start;
              _pendingPageOffset = null;
              _pendingScrollOffset = null;
              setState(() {
                _displayPageNumber = window == null
                    ? index + 1
                    : window.firstPage + index;
                _setOffset(nextOffset);
              });
            },
            itemBuilder: (context, index) {
              final page = pages[index];
              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: _settings.horizontalPadding,
                ),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SelectableText(
                    widget.text.substring(page.start, page.end),
                    style: _textStyle,
                  ),
                ),
              );
            },
          ),
        ),
        _buildPageIndicator(),
      ],
    );
  }

  Widget _buildPageIndicator() {
    return Positioned(
      right: 12,
      bottom: 8,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color(_settings.background.value).withValues(alpha: .85),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            '$_currentPageNumber페이지',
            style: TextStyle(color: Color(_settings.foreground.value)),
          ),
        ),
      ),
    );
  }

  void _ensurePages(Size size) {
    final key = jsonEncode({
      'algorithm': 2,
      'path': widget.path,
      'fileSize': widget.fileSize,
      'modified': widget.modified?.toUtc().toIso8601String(),
      'textLength': widget.text.length,
      'encoding': widget.encoding.name,
      'width': size.width,
      'height': size.height,
      'fontSize': _settings.fontSize,
      'lineHeight': _settings.lineHeight,
      'horizontalPadding': _settings.horizontalPadding,
    });
    if (_paginationKey == key) return;
    _paginationKey = key;
    _pageWindowGeneration++;
    _pageWindow = null;
    _pages = null;
    _paginationProgress = 0;
    _paginationComplete = false;
    _pageController?.dispose();
    _pageController = null;
    _pageControllerInitialOffset = null;
    final generation = ++_paginationGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final cache = widget.pageIndexCache;
      if (cache != null) {
        final cached = await cache.load(
          signature: key,
          textLength: widget.text.length,
        );
        if (!mounted || generation != _paginationGeneration) return;
        if (cached != null) {
          _setPaginationPages(cached, complete: true);
          return;
        }
      }
      if (_settings.mode == ReadingMode.page &&
          widget.text.length > _eagerScrollPaginationLimit &&
          _offset > 0) {
        await _jumpToPageNumber(_currentPageNumber, sourceOffset: _offset);
        if (!mounted || generation != _paginationGeneration) return;
      }
      final progressivePages = <TextPage>[];
      final pages = await widget.paginator(
        text: widget.text,
        size: size,
        style: _textStyle,
        onProgress: (progress) {
          if (!mounted || generation != _paginationGeneration) return;
          setState(() => _paginationProgress = progress);
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
        isCancelled: () => !mounted || generation != _paginationGeneration,
      );
      if (!mounted || generation != _paginationGeneration) return;
      final complete =
          pages.isNotEmpty &&
          pages.first.start == 0 &&
          pages.last.end == widget.text.length;
      _setPaginationPages(pages, complete: complete);
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
      _pageController?.dispose();
      _pageController = pages.isEmpty
          ? null
          : PageController(initialPage: initialPage);
      _pageControllerInitialOffset = pages.isEmpty ? null : _offset;
      _displayPageNumber = initialPage + 1;
    } else if (_pageWindow == null &&
        _pageController == null &&
        pages.isNotEmpty &&
        pages.last.end > _offset) {
      _pageController = PageController(initialPage: initialPage);
      _pageControllerInitialOffset = _offset;
    }
    setState(() {
      _pages = pages;
      _paginationComplete = complete;
    });
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
    if (_settings.mode == ReadingMode.page &&
        _pageWindow == null &&
        pendingOffset != null &&
        pages.isNotEmpty &&
        (complete || pendingOffset < pages.last.end)) {
      final controller = _pageController;
      final page = pageForOffset(pages, pendingOffset);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            _pendingPageOffset != pendingOffset ||
            !identical(controller, _pageController) ||
            controller?.hasClients != true) {
          return;
        }
        _pendingPageOffset = null;
        controller!.jumpToPage(page);
      });
    }
  }

  void _recordScrollPosition() {
    if (_settings.mode != ReadingMode.scroll) return;
    final visible =
        _itemPositionsListener.itemPositions.value
            .where((position) => position.itemTrailingEdge > 0)
            .toList()
          ..sort((a, b) => a.index.compareTo(b.index));
    if (visible.isEmpty) return;
    final index = visible.first.index;
    if (index >= _chunks.length) return;
    final pendingScrollOffset = _pendingScrollOffset;
    if (pendingScrollOffset != null) {
      if (index == _chunkForOffset(pendingScrollOffset)) return;
      _registerManualNavigation();
    }
    final offset = _chunks[index].start;
    if (offset == _offset) return;
    _invalidateQueuedNavigation();
    _pendingPageOffset = null;
    setState(() => _offset = offset);
    widget.store.updateProgress(
      widget.path,
      offset: _offset,
      documentLength: widget.text.length,
    );
    _scheduleSave();
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
    _offset = offset.clamp(0, widget.text.length);
    widget.store.updateProgress(
      widget.path,
      offset: _offset,
      documentLength: widget.text.length,
    );
    _scheduleSave();
  }

  void _jumpToOffset(int offset) {
    _navigationGeneration++;
    _pendingTargetPage = null;
    _pendingPageOffset = null;
    setState(() => _setOffset(offset));
    if (_settings.mode == ReadingMode.scroll) {
      _pendingScrollOffset = _offset;
      if (_itemScrollController.isAttached) {
        _itemScrollController.jumpTo(index: _chunkForOffset(_offset));
      }
      return;
    }
    final window = _pageWindow;
    if (window != null) {
      if (_offset >= window.pages.first.start &&
          _offset < window.pages.last.end &&
          _pageController?.hasClients == true) {
        _pageController!.jumpToPage(pageForOffset(window.pages, _offset));
      } else {
        final total = _displayTotalPages;
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
        (_paginationComplete || _offset < pages.last.end) &&
        _pageController != null) {
      final page = pageForOffset(pages, _offset);
      _pageController?.dispose();
      _pageController = PageController(initialPage: page);
      _pageControllerInitialOffset = _offset;
      _displayPageNumber = page + 1;
    } else {
      final totalPages = _displayTotalPages;
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
      final size = _pageSize;
      if (_paginationKey == null && size != null) _ensurePages(size);
      _navigationGeneration++;
      _pendingTargetPage = page;
      _showMessage('$page페이지까지 계산하고 있습니다. 계산되는 즉시 이동합니다.');
      return;
    }

    final totalPages = _displayTotalPages;
    final targetOffset = sourceOffset;
    if (_settings.mode == ReadingMode.scroll) {
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

    _pageController?.dispose();
    _pageController = PageController(initialPage: localPage);
    _pageControllerInitialOffset = sourceOffset;
    setState(() {
      _pageWindow = (pages: pages, firstPage: firstPage);
      _displayPageNumber = page;
      _pendingPageOffset = null;
      _setOffset(sourceOffset);
    });
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), widget.store.save);
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
    _showMessage('$page페이지에 북마크를 저장했습니다.');
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
    var found = widget.text.indexOf(
      query,
      math.min(_offset + 1, widget.text.length),
    );
    if (found < 0) found = widget.text.indexOf(query);
    if (found < 0) {
      _showMessage('검색 결과가 없습니다.');
    } else {
      _jumpToOffset(found);
    }
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
                  subtitle: Text('${_pageNumberForOffset(bookmark.offset)}페이지'),
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
    var draft = _settings.copyWith(
      fontSize: _settings.fontSize.round().clamp(14, 36).toDouble(),
      lineHeight: ((_settings.lineHeight * 10).round() / 10)
          .clamp(1.2, 2.2)
          .toDouble(),
      horizontalPadding: _settings.horizontalPadding
          .round()
          .clamp(8, 40)
          .toDouble(),
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final ratio = contrastRatio(draft.background, draft.foreground);
          return SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                MediaQuery.viewInsetsOf(context).bottom + 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('표시 설정', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  const Text('읽기 방식'),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('세로 스크롤'),
                        selected: draft.mode == ReadingMode.scroll,
                        onSelected: (_) => setSheetState(() {
                          draft = draft.copyWith(mode: ReadingMode.scroll);
                        }),
                      ),
                      ChoiceChip(
                        label: const Text('페이지 넘김'),
                        selected: draft.mode == ReadingMode.page,
                        onSelected: (_) => setSheetState(() {
                          draft = draft.copyWith(mode: ReadingMode.page);
                        }),
                      ),
                    ],
                  ),
                  _SettingStepper(
                    settingKey: 'font-size',
                    label: '글자 크기',
                    value: draft.fontSize,
                    min: 14,
                    max: 36,
                    step: 1,
                    fractionDigits: 0,
                    onChanged: (value) => setSheetState(() {
                      draft = draft.copyWith(fontSize: value);
                    }),
                  ),
                  _SettingStepper(
                    settingKey: 'line-height',
                    label: '줄 간격',
                    value: draft.lineHeight,
                    min: 1.2,
                    max: 2.2,
                    step: .1,
                    fractionDigits: 1,
                    onChanged: (value) => setSheetState(() {
                      draft = draft.copyWith(lineHeight: value);
                    }),
                  ),
                  _SettingStepper(
                    settingKey: 'horizontal-padding',
                    label: '좌우 여백',
                    value: draft.horizontalPadding,
                    min: 8,
                    max: 40,
                    step: 1,
                    fractionDigits: 0,
                    onChanged: (value) => setSheetState(() {
                      draft = draft.copyWith(horizontalPadding: value);
                    }),
                  ),
                  const SizedBox(height: 8),
                  const Text('색상 템플릿'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _colorTemplates
                        .map(
                          (template) => IconButton(
                            key: Key('color-template-${template.name}'),
                            tooltip: template.name,
                            onPressed: () => setSheetState(() {
                              draft = draft.copyWith(
                                background: template.background,
                                foreground: template.foreground,
                              );
                            }),
                            icon: Container(
                              width: 36,
                              height: 36,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Color(template.background.value),
                                border: Border.all(color: Colors.black26),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '가',
                                style: TextStyle(
                                  color: Color(template.foreground.value),
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 8),
                  _RgbEditor(
                    background: draft.background,
                    foreground: draft.foreground,
                    onChanged: (background, foreground) => setSheetState(() {
                      draft = draft.copyWith(
                        background: background,
                        foreground: foreground,
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    color: Color(draft.background.value),
                    child: Text(
                      '한글 미리보기 가나다라',
                      style: TextStyle(
                        color: Color(draft.foreground.value),
                        fontSize: 18,
                      ),
                    ),
                  ),
                  Text('명암비 ${ratio.toStringAsFixed(2)}:1'),
                  if (ratio < 4.5)
                    const Text(
                      '명암비가 낮아 읽기 어려울 수 있습니다.',
                      style: TextStyle(color: Colors.red),
                    ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('읽는 동안 화면 켜짐 유지'),
                    value: draft.keepAwake,
                    onChanged: (value) => setSheetState(() {
                      draft = draft.copyWith(keepAwake: value);
                    }),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _applySettings(draft);
                      },
                      child: const Text('적용'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _applySettings(ReaderSettings settings) {
    _registerManualNavigation();
    _paginationGeneration++;
    _pageWindowGeneration++;
    _pendingPageOffset = null;
    _pendingScrollOffset = null;
    _pageController?.dispose();
    _pageController = null;
    _pageControllerInitialOffset = null;
    setState(() {
      _settings = settings;
      _paginationKey = null;
      _pages = null;
      _pageWindow = null;
      _paginationComplete = false;
    });
    widget.store.updateSettings(settings);
    _scheduleSave();
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

class _SettingStepper extends StatelessWidget {
  const _SettingStepper({
    required this.settingKey,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.fractionDigits,
    required this.onChanged,
  });

  final String settingKey;
  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final int fractionDigits;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          key: Key('$settingKey-decrease'),
          tooltip: '$label 줄이기',
          onPressed: value <= min ? null : () => onChanged(_next(-step)),
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 52,
          child: Text(
            value.toStringAsFixed(fractionDigits),
            textAlign: TextAlign.center,
          ),
        ),
        IconButton(
          key: Key('$settingKey-increase'),
          tooltip: '$label 늘리기',
          onPressed: value >= max ? null : () => onChanged(_next(step)),
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }

  double _next(double delta) => double.parse(
    (value + delta).clamp(min, max).toStringAsFixed(fractionDigits),
  );
}

class _RgbEditor extends StatefulWidget {
  const _RgbEditor({
    required this.background,
    required this.foreground,
    required this.onChanged,
  });

  final RgbColor background;
  final RgbColor foreground;
  final void Function(RgbColor background, RgbColor foreground) onChanged;

  @override
  State<_RgbEditor> createState() => _RgbEditorState();
}

class _RgbEditorState extends State<_RgbEditor> {
  late final List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(6, (_) => TextEditingController());
    _setValues();
  }

  @override
  void didUpdateWidget(_RgbEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.background != widget.background ||
        oldWidget.foreground != widget.foreground) {
      _setValues();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _setValues() {
    final values = [
      widget.background.red,
      widget.background.green,
      widget.background.blue,
      widget.foreground.red,
      widget.foreground.green,
      widget.foreground.blue,
    ];
    for (var index = 0; index < values.length; index++) {
      final text = '${values[index]}';
      if (_controllers[index].text == text) continue;
      _controllers[index].value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  void _emit() {
    final values = _controllers
        .map((controller) => int.tryParse(controller.text))
        .toList();
    if (values.any((value) => value == null)) return;
    final background = RgbColor.tryCreate(values[0]!, values[1]!, values[2]!);
    final foreground = RgbColor.tryCreate(values[3]!, values[4]!, values[5]!);
    if (background != null && foreground != null) {
      widget.onChanged(background, foreground);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('배경색 RGB'),
        _row(0, 'background'),
        const SizedBox(height: 8),
        const Text('글자색 RGB'),
        _row(3, 'foreground'),
      ],
    );
  }

  Widget _row(int start, String prefix) {
    return Row(
      children: List.generate(3, (index) {
        final channel = const ['red', 'green', 'blue'][index];
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index == 2 ? 0 : 8),
            child: TextField(
              key: Key('$prefix-$channel'),
              controller: _controllers[start + index],
              keyboardType: TextInputType.number,
              onChanged: (_) {
                setState(() {});
                _emit();
              },
              decoration: InputDecoration(
                labelText: const ['R', 'G', 'B'][index],
                errorText: _channelError(_controllers[start + index].text),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        );
      }),
    );
  }

  String? _channelError(String text) {
    final value = int.tryParse(text);
    return value == null || value < 0 || value > 255 ? '0~255' : null;
  }
}

class _ColorTemplate {
  const _ColorTemplate(this.name, this.background, this.foreground);

  final String name;
  final RgbColor background;
  final RgbColor foreground;
}

const _colorTemplates = [
  _ColorTemplate('기본 연두', RgbColor(196, 236, 187), RgbColor(32, 48, 32)),
  _ColorTemplate('종이', RgbColor(255, 253, 248), RgbColor(32, 32, 32)),
  _ColorTemplate('밤', RgbColor(18, 18, 18), RgbColor(232, 232, 232)),
  _ColorTemplate('세피아', RgbColor(244, 236, 216), RgbColor(59, 49, 38)),
];

double contrastRatio(RgbColor first, RgbColor second) {
  final firstLuminance = Color(first.value).computeLuminance();
  final secondLuminance = Color(second.value).computeLuminance();
  final light = math.max(firstLuminance, secondLuminance);
  final dark = math.min(firstLuminance, secondLuminance);
  return (light + .05) / (dark + .05);
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
