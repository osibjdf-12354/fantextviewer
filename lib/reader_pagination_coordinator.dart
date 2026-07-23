import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models.dart';
import 'page_index_cache.dart';
import 'reader_controller.dart';
import 'strings.dart';
import 'text_document.dart';
import 'text_paginator.dart';

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

class ReaderPageWindow {
  const ReaderPageWindow({required this.pages, required this.firstPage});

  final List<TextPage> pages;
  final int firstPage;
}

class ReaderPaginationCoordinator {
  ReaderPaginationCoordinator({
    required this.text,
    required this.path,
    required this.encoding,
    required this.fileSize,
    required this.modified,
    required this.pageIndexCache,
    required this.paginator,
    required this.windowPaginator,
    required this.readerController,
    required this.settings,
    required this.currentOffset,
    required this.activeMode,
    required this.fallbackCharactersPerPage,
    required this.onViewChanged,
    required this.onJumpToOffset,
    required this.onSetOffset,
    required this.onMessage,
    required this.onRestartAuto,
    required this.isActive,
  });

  static const eagerTextLimit = 256 * 1024;

  final String text;
  final String path;
  final TextEncoding encoding;
  final int? fileSize;
  final DateTime? modified;
  final PageIndexCache? pageIndexCache;
  final ReaderPaginator paginator;
  final ReaderWindowPaginator windowPaginator;
  final ReaderController readerController;
  final ReaderSettings Function() settings;
  final int Function() currentOffset;
  final ReadingMode Function() activeMode;
  final int Function() fallbackCharactersPerPage;
  final VoidCallback onViewChanged;
  final ValueChanged<int> onJumpToOffset;
  final ValueChanged<int> onSetOffset;
  final ValueChanged<String> onMessage;
  final VoidCallback onRestartAuto;
  final bool Function() isActive;

  List<TextPage>? _pages;
  int? _pageIndex;
  int? _pendingTargetPage;
  ReaderPageWindow? _pageWindow;
  int _pageWindowGeneration = 0;
  int _navigationGeneration = 0;
  int _displayPageNumber = 1;
  String? _paginationKey;
  int _paginationGeneration = 0;
  bool _paginationComplete = false;
  Size? _pageSize;
  TextStyle? _textStyle;
  bool _disposed = false;

  List<TextPage>? get pages => _pages;
  int? get pageIndex => _pageIndex;
  ReaderPageWindow? get pageWindow => _pageWindow;
  int get displayPageNumber => _displayPageNumber;
  bool get complete => _paginationComplete;
  List<TextPage>? get completePages => complete ? pages : null;

  int get displayTotalPages {
    final exactPages = completePages;
    if (exactPages != null) return exactPages.length;
    return estimatedPageCount(
      text.length,
      pages ?? const [],
      fallbackCharactersPerPage: fallbackCharactersPerPage(),
    );
  }

  int get currentPageNumber {
    if (pageWindow != null) return displayPageNumber;
    final indexedPages = pages;
    final offset = currentOffset();
    if (indexedPages != null &&
        indexedPages.isNotEmpty &&
        (complete || offset < indexedPages.last.end)) {
      return pageForOffset(indexedPages, offset) + 1;
    }
    return estimatedPageForOffset(
      offset,
      textLength: text.length,
      totalPages: displayTotalPages,
    );
  }

  bool get hasIndexedCurrentPage {
    final indexedPages = pages;
    final offset = currentOffset();
    return pageWindow == null &&
        indexedPages != null &&
        indexedPages.isNotEmpty &&
        (complete || offset < indexedPages.last.end);
  }

  String pageIndicatorLabel({required bool showTotalPages}) {
    if (!hasIndexedCurrentPage || (showTotalPages && !complete)) {
      return AppStrings.calculating;
    }
    return showTotalPages
        ? '$currentPageNumber/${completePages!.length}'
        : '$currentPageNumber';
  }

  bool matchesActivePages(List<TextPage> candidate) =>
      identical(pageWindow?.pages ?? pages, candidate);

  void updateCurrentPage(int index) {
    final activePages = pageWindow?.pages ?? pages;
    if (activePages == null || index < 0 || index >= activePages.length) return;
    registerManualNavigation();
    _pageIndex = index;
    _displayPageNumber = pageWindow == null
        ? index + 1
        : pageWindow!.firstPage + index;
    onViewChanged();
    onSetOffset(activePages[index].start);
    onRestartAuto();
  }

  Future<void> ensurePages({
    required Size size,
    required TextStyle style,
    required String? fontFileName,
    required String? fontFileVersion,
  }) async {
    _pageSize = size;
    _textStyle = style;
    final currentSettings = settings();
    final key = jsonEncode({
      'algorithm': 6,
      'path': path,
      'fileSize': fileSize,
      'modified': modified?.toUtc().toIso8601String(),
      'textLength': text.length,
      'encoding': encoding.name,
      'width': size.width,
      'height': size.height,
      'fontSize': style.fontSize,
      'fontFileName': fontFileName,
      'fontFileVersion': fontFileVersion,
      'lineHeight': currentSettings.lineHeight,
      'horizontalPadding': currentSettings.horizontalPadding,
      'paragraphIndent': currentSettings.paragraphIndent,
    });
    if (_paginationKey == key || _disposed) return;
    _paginationKey = key;
    _pageWindowGeneration++;
    _pageWindow = null;
    _pages = null;
    _paginationComplete = false;
    _pageIndex = null;
    final generation = ++_paginationGeneration;
    readerController.resetPaginationActivity();

    final cache = pageIndexCache;
    if (cache != null) {
      final cached = await cache.load(signature: key, textLength: text.length);
      if (!_isCurrent(generation)) return;
      if (cached != null) {
        _setPaginationPages(cached, complete: true);
        readerController.updatePaginationProgress(1);
        return;
      }
    }
    if (_isPaged && text.length > eagerTextLimit && currentOffset() > 0) {
      await jumpToPageNumber(currentPageNumber, sourceOffset: currentOffset());
      if (!_isCurrent(generation)) return;
    }
    final progressivePages = <TextPage>[];
    final calculatedPages = await paginator(
      text: text,
      size: size,
      style: style,
      paragraphIndent: currentSettings.paragraphIndent,
      onProgress: (progress) {
        if (_isCurrent(generation)) {
          readerController.updatePaginationProgress(progress);
        }
      },
      onBatch: (batch) {
        if (!_isCurrent(generation) || batch.isEmpty) return;
        progressivePages.addAll(batch);
        _setPaginationPages(progressivePages, complete: false);
      },
      isCancelled: () => !_isCurrent(generation),
    );
    if (!_isCurrent(generation)) return;
    final isComplete =
        calculatedPages.isNotEmpty &&
        calculatedPages.first.start == 0 &&
        calculatedPages.last.end == text.length;
    _setPaginationPages(calculatedPages, complete: isComplete);
    if (isComplete) readerController.updatePaginationProgress(1);
    if (isComplete && cache != null) {
      await cache.save(
        signature: key,
        textLength: text.length,
        pages: calculatedPages,
      );
    }
  }

  void navigateToOffset(int offset) {
    _navigationGeneration++;
    _pendingTargetPage = null;
    if (!_isPaged) return;
    final indexedPages = pages;
    if (indexedPages != null &&
        indexedPages.isNotEmpty &&
        (complete || offset < indexedPages.last.end)) {
      _pageWindowGeneration++;
      _pageWindow = null;
      final page = pageForOffset(indexedPages, offset);
      _pageIndex = page;
      _displayPageNumber = page + 1;
      onViewChanged();
      return;
    }
    final window = pageWindow;
    if (window != null) {
      if (offset >= window.pages.first.start &&
          offset < window.pages.last.end) {
        final page = pageForOffset(window.pages, offset);
        _pageIndex = page;
        _displayPageNumber = window.firstPage + page;
        onViewChanged();
      } else {
        _pageIndex = null;
        onViewChanged();
        unawaited(
          jumpToPageNumber(
            estimatedPageForOffset(
              offset,
              textLength: text.length,
              totalPages: displayTotalPages,
            ),
            sourceOffset: offset,
          ),
        );
      }
      return;
    }
    _pageIndex = null;
    onViewChanged();
    unawaited(
      jumpToPageNumber(
        estimatedPageForOffset(
          offset,
          textLength: text.length,
          totalPages: displayTotalPages,
        ),
        sourceOffset: offset,
      ),
    );
  }

  Future<void> jumpToPageNumber(int page, {int? sourceOffset}) async {
    if (page < 1) {
      onMessage(AppStrings.enterPositivePage);
      return;
    }
    final exactPages = completePages;
    if (exactPages != null) {
      if (sourceOffset == null && page > exactPages.length) {
        onMessage(AppStrings.pageRange(exactPages.length));
        return;
      }
      final exactPage = sourceOffset == null
          ? page - 1
          : pageForOffset(exactPages, sourceOffset);
      onJumpToOffset(exactPages[exactPage].start);
      return;
    }
    final indexedPages = pages;
    if (sourceOffset == null &&
        indexedPages != null &&
        page <= indexedPages.length) {
      onJumpToOffset(indexedPages[page - 1].start);
      return;
    }
    if (sourceOffset == null) {
      _navigationGeneration++;
      _pendingTargetPage = page;
      if (page > displayTotalPages) {
        onMessage(AppStrings.calculatingThroughPage(page));
        return;
      }
      final measuredPages = pages;
      final charactersPerPage = measuredPages == null || measuredPages.isEmpty
          ? math.max(1, fallbackCharactersPerPage()).toInt()
          : math
                .max(1, (measuredPages.last.end / measuredPages.length).round())
                .toInt();
      final estimatedOffset = ((page - 1) * charactersPerPage)
          .clamp(0, math.max(0, text.length - 1))
          .toInt();
      await jumpToPageNumber(page, sourceOffset: estimatedOffset);
      return;
    }

    final size = _pageSize;
    final style = _textStyle;
    if (size == null || style == null) return;
    if (!_isPaged) {
      onJumpToOffset(sourceOffset);
      return;
    }
    final measuredPages = pages;
    final charactersPerPage = measuredPages == null || measuredPages.isEmpty
        ? fallbackCharactersPerPage()
        : math
              .max(1, (measuredPages.last.end / measuredPages.length).round())
              .toInt();
    final startOffset = math
        .max(0, sourceOffset - charactersPerPage * math.min(4, page - 1))
        .toInt();
    final paginationGeneration = _paginationGeneration;
    final windowGeneration = ++_pageWindowGeneration;
    final navigationGeneration = _navigationGeneration;
    bool cancelled() =>
        _disposed ||
        paginationGeneration != _paginationGeneration ||
        windowGeneration != _pageWindowGeneration ||
        navigationGeneration != _navigationGeneration;

    final currentSettings = settings();
    var windowPages = await windowPaginator(
      text: text,
      startOffset: startOffset,
      size: size,
      style: style,
      paragraphIndent: currentSettings.paragraphIndent,
      isCancelled: cancelled,
    );
    if (cancelled()) return;
    if (windowPages.isNotEmpty &&
        sourceOffset >= windowPages.last.end &&
        windowPages.last.end < text.length) {
      windowPages = await windowPaginator(
        text: text,
        startOffset: sourceOffset,
        size: size,
        style: style,
        paragraphIndent: currentSettings.paragraphIndent,
        isCancelled: cancelled,
      );
    }
    if (cancelled() || windowPages.isEmpty) return;

    var localPage = pageForOffset(windowPages, sourceOffset);
    if (localPage >= page) {
      final drop = localPage - (page - 1);
      windowPages = windowPages.sublist(drop);
      localPage -= drop;
    }
    final firstPage = page - localPage;
    final remainingPages = displayTotalPages - firstPage + 1;
    if (windowPages.length > remainingPages) {
      windowPages = windowPages.sublist(0, remainingPages);
    }

    _pageWindow = ReaderPageWindow(pages: windowPages, firstPage: firstPage);
    _pageIndex = localPage;
    _displayPageNumber = page;
    onSetOffset(sourceOffset);
    onViewChanged();
    onRestartAuto();
  }

  void resetForSettings() {
    _paginationGeneration++;
    _pageWindowGeneration++;
    _paginationKey = null;
    _pages = null;
    _pageWindow = null;
    _pageIndex = null;
    _paginationComplete = false;
  }

  void registerManualNavigation() {
    _navigationGeneration++;
    _pendingTargetPage = null;
  }

  int? pageNumberForOffset(int offset) {
    if (text.isEmpty) return null;
    if (pageWindow != null && offset == currentOffset()) {
      return displayPageNumber;
    }
    final indexedPages = pages;
    if (indexedPages != null &&
        indexedPages.isNotEmpty &&
        (complete || offset < indexedPages.last.end)) {
      return pageForOffset(indexedPages, offset) + 1;
    }
    return estimatedPageForOffset(
      offset,
      textLength: text.length,
      totalPages: displayTotalPages,
    );
  }

  void dispose() {
    _disposed = true;
    _paginationGeneration++;
    _pageWindowGeneration++;
    _navigationGeneration++;
  }

  bool get _isPaged => activeMode() != ReadingMode.scroll;

  bool _isCurrent(int generation) =>
      !_disposed && isActive() && generation == _paginationGeneration;

  void _setPaginationPages(
    List<TextPage> calculatedPages, {
    required bool complete,
  }) {
    final initialPage = calculatedPages.isEmpty
        ? 0
        : pageForOffset(calculatedPages, currentOffset());
    if (complete) {
      _pageWindowGeneration++;
      _pageWindow = null;
      _pageIndex = calculatedPages.isEmpty ? null : initialPage;
      _displayPageNumber = initialPage + 1;
    } else if (pageWindow != null &&
        calculatedPages.isNotEmpty &&
        calculatedPages.last.end > currentOffset()) {
      _pageWindowGeneration++;
      _pageWindow = null;
      _pageIndex = initialPage;
      _displayPageNumber = initialPage + 1;
    } else if (pageWindow == null &&
        pageIndex == null &&
        calculatedPages.isNotEmpty &&
        calculatedPages.last.end > currentOffset()) {
      _pageIndex = initialPage;
    }
    _pages = calculatedPages;
    _paginationComplete = complete;
    if (activeMode() == ReadingMode.scroll) {
      readerController.notifyPaginationChanged();
    } else {
      onViewChanged();
    }

    final targetPage = _pendingTargetPage;
    if (targetPage != null) {
      if (targetPage <= calculatedPages.length) {
        final targetOffset = calculatedPages[targetPage - 1].start;
        final generation = _paginationGeneration;
        final navigationGeneration = _navigationGeneration;
        _pendingTargetPage = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_isCurrent(generation) ||
              navigationGeneration != _navigationGeneration) {
            return;
          }
          onJumpToOffset(targetOffset);
        });
      } else if (complete) {
        _pendingTargetPage = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (isActive()) {
            onMessage(AppStrings.pageRange(calculatedPages.length));
          }
        });
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isActive()) onRestartAuto();
    });
  }
}
