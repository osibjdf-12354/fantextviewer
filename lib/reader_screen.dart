import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app_store.dart';
import 'models.dart';
import 'text_document.dart';
import 'text_paginator.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.path, required this.store});

  final String path;
  final AppStore store;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
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
      final bytes = await file.readAsBytes();
      final saved = widget.store.document(widget.path).encoding;
      final encoding = forced ?? _encodingByName(saved);
      final document = await decodeText(bytes, forced: encoding);
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
      store: widget.store,
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
    this.onEncodingChanged,
    this.onOpenFile,
  });

  final String path;
  final String title;
  final String text;
  final TextEncoding encoding;
  final AppStore store;
  final int? fileSize;
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
  String? _paginationKey;
  double _paginationProgress = 0;
  int _paginationGeneration = 0;
  int _currentPage = 0;
  bool _wakelockEnabled = false;

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
    if (_wakelockEnabled) unawaited(WakelockPlus.disable());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final background = Color(_settings.background.value);
    final foreground = Color(_settings.foreground.value);
    return Scaffold(
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
                _ensurePages(pageSize);
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
              subtitle: Text('${(_progress * 100).toStringAsFixed(1)}% 읽음'),
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
    final pages = _pages;
    final itemCount = pages?.length ?? _chunks.length;
    final initialIndex = pages == null
        ? _chunkForOffset(_offset)
        : pageForOffset(pages, _offset);
    return Stack(
      children: [
        ScrollablePositionedList.builder(
          itemCount: itemCount,
          itemScrollController: _itemScrollController,
          itemPositionsListener: _itemPositionsListener,
          initialScrollIndex: initialIndex,
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
            final text = pages == null
                ? _chunks[index].text
                : widget.text.substring(pages[index].start, pages[index].end);
            return SelectableText(text, style: _textStyle);
          },
        ),
        Positioned(
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
                '${(_progress * 100).toStringAsFixed(1)}%',
                style: TextStyle(color: Color(_settings.foreground.value)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPageReader() {
    final pages = _pages;
    if (pages == null) {
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
    return PageView.builder(
      controller: _pageController,
      itemCount: pages.length,
      onPageChanged: (index) {
        setState(() => _currentPage = index);
        _setOffset(pages[index].start);
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
    );
  }

  void _ensurePages(Size size) {
    final key =
        '${size.width}:${size.height}:${_settings.fontSize}:'
        '${_settings.lineHeight}:${_settings.horizontalPadding}';
    if (_paginationKey == key) return;
    _paginationKey = key;
    _pages = null;
    _paginationProgress = 0;
    final generation = ++_paginationGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final pages = await paginateText(
        text: widget.text,
        size: size,
        style: _textStyle,
        onProgress: (progress) {
          if (!mounted || generation != _paginationGeneration) return;
          setState(() => _paginationProgress = progress);
        },
        isCancelled: () => !mounted || generation != _paginationGeneration,
      );
      if (!mounted || generation != _paginationGeneration) return;
      final initialPage = pageForOffset(pages, _offset);
      _pageController?.dispose();
      _pageController = PageController(initialPage: initialPage);
      setState(() {
        _pages = pages;
        _currentPage = initialPage;
      });
      if (_settings.mode == ReadingMode.scroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_itemScrollController.isAttached) return;
          _itemScrollController.jumpTo(index: initialPage);
        });
      }
    });
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
    final pages = _pages;
    if (index >= (pages?.length ?? _chunks.length)) return;
    final offset = pages == null ? _chunks[index].start : pages[index].start;
    if (offset == _offset) return;
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
    setState(() => _setOffset(offset));
    if (_settings.mode == ReadingMode.scroll &&
        _itemScrollController.isAttached) {
      final pages = _pages;
      _itemScrollController.jumpTo(
        index: pages == null
            ? _chunkForOffset(_offset)
            : pageForOffset(pages, _offset),
      );
    } else {
      final pages = _pages;
      if (pages != null && _pageController?.hasClients == true) {
        final page = pageForOffset(pages, _offset);
        _pageController!.jumpToPage(page);
        setState(() => _currentPage = page);
      }
    }
  }

  double get _progress =>
      widget.text.isEmpty ? 0 : _offset / widget.text.length;

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
    final pages = _pages;
    if (pages == null) {
      _showMessage('페이지를 계산하고 있습니다.');
      return;
    }
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
            hintText: '1~${pages.length}',
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
    if (page == null || page < 1 || page > pages.length) {
      _showMessage('1~${pages.length} 사이 페이지를 입력해 주세요.');
      return;
    }
    _jumpToOffset(pages[page - 1].start);
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
    if (_pages == null) {
      _showMessage('페이지를 계산하고 있습니다.');
      return;
    }
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
    var draft = _settings;
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
                  _SettingSlider(
                    label: '글자 크기',
                    value: draft.fontSize,
                    min: 14,
                    max: 36,
                    onChanged: (value) => setSheetState(() {
                      draft = draft.copyWith(fontSize: value);
                    }),
                  ),
                  _SettingSlider(
                    label: '줄 간격',
                    value: draft.lineHeight,
                    min: 1.2,
                    max: 2.2,
                    onChanged: (value) => setSheetState(() {
                      draft = draft.copyWith(lineHeight: value);
                    }),
                  ),
                  _SettingSlider(
                    label: '좌우 여백',
                    value: draft.horizontalPadding,
                    min: 8,
                    max: 40,
                    onChanged: (value) => setSheetState(() {
                      draft = draft.copyWith(horizontalPadding: value);
                    }),
                  ),
                  const SizedBox(height: 8),
                  const Text('색상 템플릿'),
                  Wrap(
                    spacing: 8,
                    children: _colorTemplates
                        .map(
                          (template) => OutlinedButton(
                            onPressed: () => setSheetState(() {
                              draft = draft.copyWith(
                                background: template.background,
                                foreground: template.foreground,
                              );
                            }),
                            child: Text(template.name),
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
    _paginationGeneration++;
    _pageController?.dispose();
    _pageController = null;
    setState(() {
      _settings = settings;
      _paginationKey = null;
      _pages = null;
    });
    widget.store.updateSettings(settings);
    _scheduleSave();
    _syncWakelock();
  }

  Future<void> _syncWakelock() async {
    if (_settings.keepAwake) {
      await WakelockPlus.enable();
      _wakelockEnabled = true;
    } else if (_wakelockEnabled) {
      await WakelockPlus.disable();
      _wakelockEnabled = false;
    }
  }

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
    final pages = _pages;
    if (pages == null || pages.isEmpty) return null;
    return pageForOffset(pages, offset) + 1;
  }
}

class _SettingSlider extends StatelessWidget {
  const _SettingSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 72, child: Text('$label\n${value.toStringAsFixed(1)}')),
        Expanded(
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
      ],
    );
  }
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
