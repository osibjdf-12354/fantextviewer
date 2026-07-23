import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app_store.dart';
import 'file_browser.dart';
import 'font_library.dart';
import 'models.dart';
import 'reader_screen.dart';
import 'recovery_file_exporter.dart';
import 'strings.dart';
import 'text_file_importer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final directory = await getApplicationSupportDirectory();
  final store = AppStore(
    File('${directory.path}${Platform.pathSeparator}state.json'),
  );
  await store.load();
  try {
    await promoteLegacyTextImports(store);
  } catch (error, stackTrace) {
    debugPrint('Failed to promote a legacy imported text file: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
  final fontLibrary = FontLibrary(
    Directory('${directory.path}${Platform.pathSeparator}fonts'),
  );
  await restoreSelectedFont(store, fontLibrary);
  runApp(FanTextViewerApp(store: store, fontLibrary: fontLibrary));
}

Future<void> restoreSelectedFont(
  AppStore store,
  FontLibrary fontLibrary,
) async {
  final selected = store.data.settings.fontFileName;
  if (selected == null || await fontLibrary.loadSelected(selected)) return;
  store.updateSettings(store.data.settings.copyWith(fontFileName: null));
  try {
    await store.save();
  } catch (error, stackTrace) {
    debugPrint('Failed to persist the recovered font setting: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

class FanTextViewerApp extends StatelessWidget {
  const FanTextViewerApp({super.key, required this.store, this.fontLibrary});

  final AppStore store;
  final FontLibrary? fontLibrary;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 77, 130, 68),
        ),
        useMaterial3: true,
      ),
      home: HomeScreen(store: store, fontLibrary: fontLibrary),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store, this.fontLibrary});

  final AppStore store;
  final FontLibrary? fontLibrary;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<void> _importState() async {
    final selected = await openFile();
    if (selected == null) return;
    try {
      await widget.store.importState(File(selected.path));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.stateImportSucceeded)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.stateImportFailed(error))),
      );
    }
  }

  Future<void> _exportRecovery() async {
    final recovery = widget.store.recoveryFile;
    if (recovery == null) return;
    try {
      final exported = await RecoveryFileExporter().export(recovery);
      if (!mounted || !exported) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.stateExportSucceeded)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.stateExportFailed(error))),
      );
    }
  }

  Future<void> _openReader(String path) async {
    if (!await File(path).exists()) {
      if (!mounted) return;
      final remove = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text(AppStrings.missingFileTitle),
          content: const Text(AppStrings.missingFileBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text(AppStrings.keep),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text(AppStrings.removeFromList),
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
        builder: (context) => ReaderScreen(
          path: path,
          store: widget.store,
          fontLibrary: widget.fontLibrary,
        ),
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
        final recoveryFile = widget.store.recoveryFile;
        final content = recent.isEmpty
            ? const _EmptyHome()
            : ListView(
                padding: const EdgeInsets.only(bottom: 88),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Text(
                      AppStrings.recentFiles,
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
              );
        return Scaffold(
          appBar: AppBar(
            title: const Text(AppStrings.appName),
            actions: [
              IconButton(
                tooltip: AppStrings.systemFilePicker,
                onPressed: _openSystemPicker,
                icon: const Icon(Icons.file_open),
              ),
            ],
          ),
          body: Column(
            children: [
              if (recoveryFile != null)
                MaterialBanner(
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        AppStrings.stateRecoveryTitle,
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${AppStrings.stateRecoveryBody}\n'
                        '${recoveryFile?.path ?? AppStrings.unknown}',
                      ),
                    ],
                  ),
                  leading: const Icon(Icons.restore_page_outlined),
                  actions: [
                    TextButton(
                      onPressed: _exportRecovery,
                      child: const Text(AppStrings.exportRecoveryFile),
                    ),
                    TextButton(
                      onPressed: _importState,
                      child: const Text(AppStrings.importStateFile),
                    ),
                  ],
                ),
              Expanded(child: content),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _openBrowser,
            icon: const Icon(Icons.folder_open),
            label: const Text(AppStrings.browseFiles),
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
            Text(AppStrings.noRecentFiles),
            SizedBox(height: 8),
            Text(AppStrings.browseFilesHint),
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
        tooltip: AppStrings.removeRecent,
        onPressed: onRemove,
        icon: const Icon(Icons.close),
      ),
    );
  }
}

String _fileName(String path) => path.split(Platform.pathSeparator).last;
