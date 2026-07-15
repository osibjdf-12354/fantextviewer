import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app_store.dart';
import 'file_browser.dart';
import 'models.dart';
import 'reader_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final directory = await getApplicationSupportDirectory();
  final store = AppStore(
    File('${directory.path}${Platform.pathSeparator}state.json'),
  );
  await store.load();
  runApp(GeulbomApp(store: store));
}

class GeulbomApp extends StatelessWidget {
  const GeulbomApp({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '글봄',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 77, 130, 68),
        ),
        useMaterial3: true,
      ),
      home: HomeScreen(store: store),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store});

  final AppStore store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<void> _openReader(String path) async {
    if (!await File(path).exists()) {
      if (!mounted) return;
      final remove = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('파일을 찾을 수 없습니다'),
          content: const Text('파일이 이동되거나 삭제되었습니다. 최근 목록에서 지울까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('유지'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('목록에서 삭제'),
            ),
          ],
        ),
      );
      if (remove == true) {
        widget.store.removeDocument(path);
        await widget.store.save();
      }
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => ReaderScreen(path: path, store: widget.store),
      ),
    );
  }

  Future<void> _openBrowser() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => FileBrowserScreen(onOpenFile: _openReader),
      ),
    );
  }

  Future<void> _openSystemPicker() async {
    final path = await pickTextFile();
    if (path != null) await _openReader(path);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final recent = widget.store.recentDocuments;
        return Scaffold(
          appBar: AppBar(
            title: const Text('글봄'),
            actions: [
              IconButton(
                tooltip: '시스템 파일 선택기',
                onPressed: _openSystemPicker,
                icon: const Icon(Icons.file_open),
              ),
            ],
          ),
          body: recent.isEmpty
              ? const _EmptyHome()
              : ListView(
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Text(
                        '최근 파일',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    for (final document in recent)
                      _RecentTile(
                        document: document,
                        onTap: () => _openReader(document.path),
                        onRemove: () async {
                          widget.store.removeDocument(document.path);
                          await widget.store.save();
                        },
                      ),
                  ],
                ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _openBrowser,
            icon: const Icon(Icons.folder_open),
            label: const Text('파일 탐색'),
          ),
        );
      },
    );
  }
}

class _EmptyHome extends StatelessWidget {
  const _EmptyHome();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined, size: 64),
            SizedBox(height: 16),
            Text('최근에 읽은 파일이 없습니다.'),
            SizedBox(height: 8),
            Text('파일 탐색 버튼으로 TXT 파일을 열어 보세요.'),
          ],
        ),
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({
    required this.document,
    required this.onTap,
    required this.onRemove,
  });

  final DocumentState document;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.description_outlined),
      title: Text(_fileName(document.path)),
      subtitle: Text(
        document.path,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onTap,
      trailing: IconButton(
        tooltip: '최근 목록에서 삭제',
        onPressed: onRemove,
        icon: const Icon(Icons.close),
      ),
    );
  }
}

String _fileName(String path) => path.split(Platform.pathSeparator).last;
