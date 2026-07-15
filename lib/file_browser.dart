import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

enum BrowserSort { name, modified }

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
  BrowserSort sort,
) async {
  final entries = <BrowserEntry>[];
  await for (final entity in directory.list(followLinks: false)) {
    final name = entity.path.split(Platform.pathSeparator).last;
    if (name.startsWith('.')) continue;
    final isDirectory = entity is Directory;
    if (!isDirectory && !name.toLowerCase().endsWith('.txt')) continue;
    final stat = await entity.stat();
    entries.add(
      BrowserEntry(
        path: entity.path,
        name: name,
        isDirectory: isDirectory,
        modified: stat.modified,
        size: stat.size,
      ),
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

class FileBrowserScreen extends StatefulWidget {
  const FileBrowserScreen({
    super.key,
    required this.onOpenFile,
    this.initialDirectory,
  });

  final ValueChanged<String> onOpenFile;
  final Directory? initialDirectory;

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen>
    with WidgetsBindingObserver {
  final _searchController = TextEditingController();
  BrowserSort _sort = BrowserSort.name;
  Directory? _directory;
  List<BrowserEntry> _entries = const [];
  String? _error;
  bool _checkingPermission = true;
  bool _hasPermission = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_hasPermission) _initialize();
  }

  Future<void> _initialize() async {
    final granted = await _storageGranted();
    if (!mounted) return;
    setState(() {
      _checkingPermission = false;
      _hasPermission = granted;
    });
    if (!granted) return;
    final requested =
        widget.initialDirectory ?? Directory('/storage/emulated/0');
    _directory = await requested.exists() ? requested : Directory.current;
    await _load();
  }

  Future<bool> _storageGranted() async {
    if (!Platform.isAndroid) return true;
    return await Permission.manageExternalStorage.isGranted ||
        await Permission.storage.isGranted;
  }

  Future<void> _requestPermission() async {
    if (!Platform.isAndroid) return _initialize();
    await Permission.manageExternalStorage.request();
    if (!await Permission.manageExternalStorage.isGranted) {
      await Permission.storage.request();
    }
    await _initialize();
  }

  Future<void> _load() async {
    final directory = _directory;
    if (directory == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await listTextEntries(directory, _sort);
      if (!mounted) return;
      setState(() => _entries = entries);
    } on FileSystemException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
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
    if (directory == null) return;
    final parent = directory.parent;
    if (parent.path == directory.path) return;
    await _openDirectory(parent.path);
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingPermission) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_hasPermission) return _buildPermissionRequest();

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
      body: Column(
        children: [
          ListTile(
            dense: true,
            leading: IconButton(
              tooltip: '상위 폴더',
              onPressed: _goUp,
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

  Widget _buildPermissionRequest() {
    return Scaffold(
      appBar: AppBar(title: const Text('파일 탐색기')),
      body: _Message(
        icon: Icons.folder_off_outlined,
        text: '기기의 TXT 파일을 탐색하려면\n모든 파일 접근 권한이 필요합니다.',
        actionLabel: '권한 설정 열기',
        onAction: _requestPermission,
        secondaryLabel: '시스템 파일 선택기',
        onSecondary: _openPicker,
      ),
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
