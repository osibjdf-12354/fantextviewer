import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

enum BrowserSort { name, modified }

typedef DirectoryPicker = Future<String?> Function({String? initialDirectory});
typedef BrowserEntryLoader =
    Future<List<BrowserEntry>> Function(Directory directory, BrowserSort sort);

class BrowserEntry {
  const BrowserEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.modified,
    required this.size,
  });

  final String path;
  final String name;
  final bool isDirectory;
  final DateTime modified;
  final int size;
}

Future<List<BrowserEntry>> listTextEntries(
  Directory directory,
  BrowserSort sort, {
  Future<FileStat> Function(FileSystemEntity entity)? readStat,
}) async {
  final candidates =
      <({FileSystemEntity entity, String name, bool isDirectory})>[];
  await for (final entity in directory.list(followLinks: false)) {
    final name = entity.path.split(Platform.pathSeparator).last;
    if (name.startsWith('.')) continue;
    final isDirectory = entity is Directory;
    if (!isDirectory && !name.toLowerCase().endsWith('.txt')) continue;
    candidates.add((entity: entity, name: name, isDirectory: isDirectory));
  }
  final stat = readStat ?? (entity) => entity.stat();
  final entries = <BrowserEntry>[];
  for (var start = 0; start < candidates.length; start += 32) {
    final end = start + 32 < candidates.length ? start + 32 : candidates.length;
    entries.addAll(
      (await Future.wait(
        candidates.sublist(start, end).map((candidate) async {
          try {
            final info = await stat(candidate.entity);
            return BrowserEntry(
              path: candidate.entity.path,
              name: candidate.name,
              isDirectory: candidate.isDirectory,
              modified: info.modified,
              size: info.size,
            );
          } on FileSystemException {
            return null;
          }
        }),
      )).whereType<BrowserEntry>(),
    );
  }
  entries.sort((a, b) {
    if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
    return switch (sort) {
      BrowserSort.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      BrowserSort.modified => b.modified.compareTo(a.modified),
    };
  });
  return entries;
}

Future<String?> pickTextFile() async {
  const textFiles = XTypeGroup(
    label: '텍스트 파일',
    extensions: ['txt'],
    mimeTypes: ['text/plain'],
  );
  return (await openFile(acceptedTypeGroups: const [textFiles]))?.path;
}

Future<String?> pickTextDirectory({String? initialDirectory}) {
  return getDirectoryPath(initialDirectory: initialDirectory);
}

class FileBrowserScreen extends StatefulWidget {
  const FileBrowserScreen({
    super.key,
    required this.onOpenFile,
    this.initialDirectory,
    this.pickDirectory = pickTextDirectory,
    this.loadEntries = listTextEntries,
  });

  final ValueChanged<String> onOpenFile;
  final Directory? initialDirectory;
  final DirectoryPicker pickDirectory;
  final BrowserEntryLoader loadEntries;

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen> {
  final _searchController = TextEditingController();
  BrowserSort _sort = BrowserSort.name;
  Directory? _directory;
  Directory? _rootDirectory;
  List<BrowserEntry> _entries = const [];
  String? _error;
  bool _loading = false;
  var _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDirectory;
    if (initial != null) {
      _directory = initial;
      _rootDirectory = initial;
      _load();
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _chooseDirectory() async {
    try {
      final path = await widget.pickDirectory(
        initialDirectory: _directory?.path,
      );
      if (path == null || !mounted) return;
      final selected = Directory(path);
      _rootDirectory = selected;
      await _openDirectory(path);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _load() async {
    final directory = _directory;
    if (directory == null) return;
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await widget.loadEntries(directory, _sort);
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _entries = entries);
    } on FileSystemException catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _error = error.message);
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openPicker() async {
    final path = await pickTextFile();
    if (path != null) widget.onOpenFile(path);
  }

  Future<void> _openDirectory(String path) async {
    _directory = Directory(path);
    _searchController.clear();
    await _load();
  }

  Future<void> _goUp() async {
    final directory = _directory;
    final root = _rootDirectory;
    if (directory == null || root == null || directory.path == root.path) {
      return;
    }
    final parent = directory.parent;
    await _openDirectory(parent.path);
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final visible = query.isEmpty
        ? _entries
        : _entries
              .where((entry) => entry.name.toLowerCase().contains(query))
              .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('파일 탐색기'),
        actions: [
          IconButton(
            tooltip: '폴더 선택',
            onPressed: _chooseDirectory,
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
          IconButton(
            tooltip: '시스템 파일 선택기',
            onPressed: _openPicker,
            icon: const Icon(Icons.file_open),
          ),
          PopupMenuButton<BrowserSort>(
            tooltip: '정렬',
            initialValue: _sort,
            onSelected: (sort) {
              _sort = sort;
              _load();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: BrowserSort.name, child: Text('이름순')),
              PopupMenuItem(value: BrowserSort.modified, child: Text('수정일순')),
            ],
          ),
        ],
      ),
      body: _directory == null
          ? _buildStart()
          : Column(
              children: [
                ListTile(
                  dense: true,
                  leading: IconButton(
                    tooltip: '상위 폴더',
                    onPressed: _directory?.path == _rootDirectory?.path
                        ? null
                        : _goUp,
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  title: Text(
                    _directory?.path ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: '파일명 검색',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                if (_loading) const LinearProgressIndicator(),
                Expanded(
                  child: _error != null
                      ? _Message(
                          icon: Icons.error_outline,
                          text: '폴더를 읽지 못했습니다.\n$_error',
                          actionLabel: '다시 시도',
                          onAction: _load,
                        )
                      : visible.isEmpty && !_loading
                      ? const _Message(
                          icon: Icons.folder_off_outlined,
                          text: '표시할 폴더나 TXT 파일이 없습니다.',
                        )
                      : ListView.builder(
                          itemCount: visible.length,
                          itemBuilder: (context, index) {
                            final entry = visible[index];
                            return ListTile(
                              leading: Icon(
                                entry.isDirectory
                                    ? Icons.folder
                                    : Icons.description_outlined,
                              ),
                              title: Text(entry.name),
                              subtitle: entry.isDirectory
                                  ? null
                                  : Text(_formatBytes(entry.size)),
                              onTap: () => entry.isDirectory
                                  ? _openDirectory(entry.path)
                                  : widget.onOpenFile(entry.path),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildStart() {
    return _Message(
      icon: Icons.folder_open_outlined,
      text: _error == null
          ? 'TXT 파일이 있는 폴더를 선택하거나\n파일 하나를 바로 여세요.'
          : '폴더를 열지 못했습니다.\n$_error',
      actionLabel: '폴더 선택',
      onAction: _chooseDirectory,
      secondaryLabel: '파일 하나 선택',
      onSecondary: _openPicker,
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
            if (actionLabel != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
            if (secondaryLabel != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
