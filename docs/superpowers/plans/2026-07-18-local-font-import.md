# Local Font Import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let Android users import, select, persist, and delete local TTF/OTF fonts from the reader display settings.

**Architecture:** Keep the application-support `fonts` directory as the font catalog and persist only the selected copied filename in `ReaderSettings`. A small `FontLibrary` performs file validation, collision-safe copies, runtime `FontLoader` registration, listing, and deletion; `ReaderView` reuses its existing display-settings draft and pagination invalidation path.

**Tech Stack:** Dart 3.12.2, Flutter 3.44.6, Material 3, `file_selector` 1.1.0, `path_provider` 2.1.6, `flutter_test`

## Global Constraints

- Accept exactly one local `.ttf` or `.otf` file per import.
- Copy imports into the application-support `fonts` directory; never modify or delete the source file.
- Keep multiple imported fonts and preserve collisions by adding ` (2)`, ` (3)`, and so on before the extension.
- Use the copied filename without its extension as the visible label; do not parse font metadata.
- Persist only the selected copied filename; `null` means `시스템 기본 글꼴`.
- Add no dependency, network permission, internet font source, weight/style grouping, or database.
- A missing or unloadable saved font resets to the system default.
- Font selection must affect the body, preview, and pagination cache signature.

---

### Task 1: Persist the Selected Font

**Files:**
- Modify: `lib/models.dart:50-116`
- Modify: `test/app_store_test.dart`

**Interfaces:**
- Consumes: existing `ReaderSettings`, `ReaderSettings.copyWith`, and JSON storage through `AppStore`
- Produces: `ReaderSettings.fontFileName: String?` and a `copyWith(fontFileName: ...)` argument that can explicitly clear the value with `null`

- [ ] **Step 1: Write the failing persistence and clearing test**

Add to `test/app_store_test.dart`:

```dart
test('선택한 글꼴을 저장하고 시스템 기본 글꼴로 되돌릴 수 있다', () {
  final imported = const ReaderSettings().copyWith(
    fontFileName: '나눔명조.otf',
  );

  expect(imported.fontFileName, '나눔명조.otf');
  expect(
    ReaderSettings.fromJson(imported.toJson()).fontFileName,
    '나눔명조.otf',
  );
  expect(imported.copyWith(fontFileName: null).fontFileName, isNull);
  expect(const ReaderSettings().fontFileName, isNull);
});
```

- [ ] **Step 2: Run the test and verify RED**

Run: `flutter test test/app_store_test.dart --plain-name "선택한 글꼴을 저장하고 시스템 기본 글꼴로 되돌릴 수 있다"`

Expected: compilation fails because `ReaderSettings` has no `fontFileName` field or copy argument.

- [ ] **Step 3: Add the nullable persisted setting with an explicit-null sentinel**

Add above `ReaderSettings` in `lib/models.dart`:

```dart
const _unchangedFontFileName = Object();
```

Extend `ReaderSettings` with the following exact constructor field, property, copy argument, assignment, and JSON entries:

```dart
class ReaderSettings {
  const ReaderSettings({
    this.mode = ReadingMode.scroll,
    this.background = const RgbColor(196, 236, 187),
    this.foreground = const RgbColor(32, 48, 32),
    this.fontFileName,
    this.fontSize = 20,
    this.lineHeight = 1.65,
    this.horizontalPadding = 20,
    this.keepAwake = false,
  });

  final ReadingMode mode;
  final RgbColor background;
  final RgbColor foreground;
  final String? fontFileName;
  final double fontSize;
  final double lineHeight;
  final double horizontalPadding;
  final bool keepAwake;

  ReaderSettings copyWith({
    ReadingMode? mode,
    RgbColor? background,
    RgbColor? foreground,
    Object? fontFileName = _unchangedFontFileName,
    double? fontSize,
    double? lineHeight,
    double? horizontalPadding,
    bool? keepAwake,
  }) {
    return ReaderSettings(
      mode: mode ?? this.mode,
      background: background ?? this.background,
      foreground: foreground ?? this.foreground,
      fontFileName: identical(fontFileName, _unchangedFontFileName)
          ? this.fontFileName
          : fontFileName as String?,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      horizontalPadding: horizontalPadding ?? this.horizontalPadding,
      keepAwake: keepAwake ?? this.keepAwake,
    );
  }

  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'background': background.toJson(),
    'foreground': foreground.toJson(),
    'fontFileName': fontFileName,
    'fontSize': fontSize,
    'lineHeight': lineHeight,
    'horizontalPadding': horizontalPadding,
    'keepAwake': keepAwake,
  };

  factory ReaderSettings.fromJson(Map<String, dynamic> json) {
    return ReaderSettings(
      mode: ReadingMode.values.firstWhere(
        (mode) => mode.name == json['mode'],
        orElse: () => ReadingMode.scroll,
      ),
      background: json['background'] == null
          ? const RgbColor(196, 236, 187)
          : RgbColor.fromJson(json['background'] as Map<String, dynamic>),
      foreground: json['foreground'] == null
          ? const RgbColor(32, 48, 32)
          : RgbColor.fromJson(json['foreground'] as Map<String, dynamic>),
      fontFileName: json['fontFileName'] as String?,
      fontSize: (json['fontSize'] as num? ?? 20).toDouble(),
      lineHeight: (json['lineHeight'] as num? ?? 1.65).toDouble(),
      horizontalPadding: (json['horizontalPadding'] as num? ?? 20).toDouble(),
      keepAwake: json['keepAwake'] as bool? ?? false,
    );
  }
}
```

- [ ] **Step 4: Run Task 1 tests and verify GREEN**

Run: `dart format lib/models.dart test/app_store_test.dart`

Run: `flutter test test/app_store_test.dart --reporter expanded`

Expected: all `app_store_test.dart` tests pass, including old JSON without `fontFileName`.

- [ ] **Step 5: Commit Task 1**

```powershell
git add -- lib/models.dart test/app_store_test.dart
git commit -m "feat: persist reader font selection"
```

---

### Task 2: Copy, Load, List, and Delete Font Files

**Files:**
- Create: `lib/font_library.dart`
- Create: `test/font_library_test.dart`

**Interfaces:**
- Consumes: `Directory`, `File`, Flutter `FontLoader`, and existing `file_selector`
- Produces: `ImportedFont`, `FontLibrary.listFonts()`, `findFont(String)`, `importFont(String)`, `loadFont(ImportedFont)`, `loadSelected(String)`, `deleteFont(ImportedFont)`, `fontFamilyFor(String?)`, and `pickFontFile()`

- [ ] **Step 1: Write failing tests for persistent copies, collisions, filtering, and deletion**

Create `test/font_library_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geulbom/font_library.dart';

void main() {
  test('TTF와 OTF를 복사하고 중복 이름을 보존하며 원본과 별도로 삭제한다', () async {
    final root = await Directory.systemTemp.createTemp('geulbom_fonts');
    addTearDown(() => root.delete(recursive: true));
    final source = File(
      '${root.path}${Platform.pathSeparator}나눔명조.ttf',
    );
    await source.writeAsBytes([1, 2, 3]);
    final registered = <String>[];
    final library = FontLibrary(
      Directory('${root.path}${Platform.pathSeparator}app-fonts'),
      registerFont: (family, bytes) async {
        registered.add('$family:${bytes.length}');
      },
    );

    final first = await library.importFont(source.path);
    final second = await library.importFont(source.path);
    await File(
      '${library.directory.path}${Platform.pathSeparator}무시.txt',
    ).writeAsString('not a font');
    await source.delete();

    expect(first.fileName, '나눔명조.ttf');
    expect(second.fileName, '나눔명조 (2).ttf');
    expect((await library.listFonts()).map((font) => font.fileName), [
      '나눔명조.ttf',
      '나눔명조 (2).ttf',
    ]);
    expect(await first.file.exists(), isTrue);
    expect(registered, hasLength(2));

    await library.deleteFont(first);

    expect(await first.file.exists(), isFalse);
  });

  test('지원하지 않는 확장자와 등록 실패는 복사본을 남기지 않는다', () async {
    final root = await Directory.systemTemp.createTemp('geulbom_bad_font');
    addTearDown(() => root.delete(recursive: true));
    final fonts = Directory('${root.path}${Platform.pathSeparator}fonts');
    final text = File('${root.path}${Platform.pathSeparator}font.txt');
    final broken = File('${root.path}${Platform.pathSeparator}broken.otf');
    await text.writeAsString('text');
    await broken.writeAsBytes([0]);
    final library = FontLibrary(
      fonts,
      registerFont: (_, _) async => throw const FormatException('broken'),
    );

    await expectLater(
      library.importFont(text.path),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      library.importFont(broken.path),
      throwsA(isA<FormatException>()),
    );

    expect(await library.listFonts(), isEmpty);
  });

  test('저장된 글꼴이 없거나 등록에 실패하면 복원하지 않는다', () async {
    final root = await Directory.systemTemp.createTemp('geulbom_restore_font');
    addTearDown(() => root.delete(recursive: true));
    final library = FontLibrary(
      Directory('${root.path}${Platform.pathSeparator}fonts'),
      registerFont: (_, _) async => throw const FormatException('broken'),
    );

    expect(await library.loadSelected('missing.ttf'), isFalse);
    final font = File(
      '${library.directory.path}${Platform.pathSeparator}broken.ttf',
    );
    await font.parent.create(recursive: true);
    await font.writeAsBytes([0]);
    expect(await library.loadSelected('broken.ttf'), isFalse);
  });
}
```

- [ ] **Step 2: Run the tests and verify RED**

Run: `flutter test test/font_library_test.dart --reporter expanded`

Expected: compilation fails because `lib/font_library.dart` and its interfaces do not exist.

- [ ] **Step 3: Implement the minimal filesystem-backed font library**

Create `lib/font_library.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

typedef FontRegistrar = Future<void> Function(
  String family,
  Uint8List bytes,
);

class ImportedFont {
  const ImportedFont(this.file);

  final File file;

  String get fileName => file.path.split(Platform.pathSeparator).last;
  String get label {
    final dot = fileName.lastIndexOf('.');
    return dot < 1 ? fileName : fileName.substring(0, dot);
  }

  String get family => fontFamilyFor(fileName)!;
}

String? fontFamilyFor(String? fileName) =>
    fileName == null ? null : 'geulbom::$fileName';

Future<String?> pickFontFile() async {
  const fonts = XTypeGroup(
    label: '글꼴 파일',
    extensions: ['ttf', 'otf'],
    mimeTypes: ['font/ttf', 'font/otf'],
  );
  return (await openFile(acceptedTypeGroups: const [fonts]))?.path;
}

class FontLibrary {
  FontLibrary(this.directory, {FontRegistrar registerFont = _loadFontBytes})
    : _registerFont = registerFont;

  final Directory directory;
  final FontRegistrar _registerFont;
  final Set<String> _loadedFileNames = {};

  Future<List<ImportedFont>> listFonts() async {
    if (!await directory.exists()) return [];
    final fonts = <ImportedFont>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && _isFontPath(entity.path)) {
        fonts.add(ImportedFont(entity));
      }
    }
    fonts.sort(
      (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
    );
    return fonts;
  }

  Future<ImportedFont?> findFont(String fileName) async {
    for (final font in await listFonts()) {
      if (font.fileName == fileName) return font;
    }
    return null;
  }

  Future<ImportedFont> importFont(String sourcePath) async {
    if (!_isFontPath(sourcePath)) {
      throw const FormatException('지원하는 글꼴은 TTF 또는 OTF 파일입니다.');
    }
    await directory.create(recursive: true);
    final source = File(sourcePath);
    final target = await _availableTarget(
      source.path.split(Platform.pathSeparator).last,
    );
    await source.copy(target.path);
    final imported = ImportedFont(target);
    try {
      await loadFont(imported);
      return imported;
    } catch (_) {
      if (await target.exists()) await target.delete();
      rethrow;
    }
  }

  Future<void> loadFont(ImportedFont font) async {
    if (_loadedFileNames.contains(font.fileName)) return;
    await _registerFont(font.family, await font.file.readAsBytes());
    _loadedFileNames.add(font.fileName);
  }

  Future<bool> loadSelected(String fileName) async {
    final font = await findFont(fileName);
    if (font == null) return false;
    try {
      await loadFont(font);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> deleteFont(ImportedFont font) async {
    if (await font.file.exists()) await font.file.delete();
  }

  Future<File> _availableTarget(String fileName) async {
    final dot = fileName.lastIndexOf('.');
    final stem = dot < 1 ? fileName : fileName.substring(0, dot);
    final extension = dot < 1 ? '' : fileName.substring(dot);
    var candidate = fileName;
    var suffix = 2;
    while (_loadedFileNames.contains(candidate) ||
        await File(
          '${directory.path}${Platform.pathSeparator}$candidate',
        ).exists()) {
      candidate = '$stem ($suffix)$extension';
      suffix++;
    }
    return File('${directory.path}${Platform.pathSeparator}$candidate');
  }

  static bool _isFontPath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.ttf') || lower.endsWith('.otf');
  }
}

Future<void> _loadFontBytes(String family, Uint8List bytes) async {
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}
```

The `_loadedFileNames` set deliberately remains populated after deletion because Flutter cannot unload a runtime font. It also forces a same-session re-import of the same basename to receive a new family name instead of reusing stale engine state.

- [ ] **Step 4: Run Task 2 tests and verify GREEN**

Run: `dart format lib/font_library.dart test/font_library_test.dart`

Run: `flutter test test/font_library_test.dart --reporter expanded`

Expected: all three font-library tests pass.

- [ ] **Step 5: Commit Task 2**

```powershell
git add -- lib/font_library.dart test/font_library_test.dart
git commit -m "feat: add local font library"
```

---

### Task 3: Restore and Apply Fonts to Reader Layout

**Files:**
- Modify: `lib/main.dart:1-82`
- Modify: `lib/reader_screen.dart:1-280, 530-538`
- Modify: `test/widget_test.dart`
- Modify: `test/reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 1 `ReaderSettings.fontFileName`, Task 2 `FontLibrary` and `fontFamilyFor`
- Produces: `restoreSelectedFont(AppStore, FontLibrary)`, optional `fontLibrary` propagation from app root to `ReaderView`, `ReaderView.pickFont`, and font-aware body/pagination styles

- [ ] **Step 1: Write the failing startup recovery test**

Add imports and this test to `test/widget_test.dart`:

```dart
import 'package:geulbom/font_library.dart';
import 'package:geulbom/models.dart';

test('저장된 글꼴 파일이 없으면 시스템 기본 글꼴로 복구한다', () async {
  final root = await Directory.systemTemp.createTemp('geulbom_missing_font');
  addTearDown(() => root.delete(recursive: true));
  final store = _MemoryStore()
    ..updateSettings(const ReaderSettings(fontFileName: 'missing.ttf'));

  await restoreSelectedFont(
    store,
    FontLibrary(Directory('${root.path}${Platform.pathSeparator}fonts')),
  );

  expect(store.data.settings.fontFileName, isNull);
});
```

- [ ] **Step 2: Write the failing body-style and pagination-signature test**

Add to `test/reader_screen_test.dart`:

```dart
testWidgets('선택 글꼴을 본문에 적용하고 글꼴별 페이지 캐시를 사용한다', (tester) async {
  const text = '본문';
  final cache = _MemoryPageIndexCache();

  Future<void> pumpFont(String fileName) async {
    final store = _MemoryStore()
      ..updateSettings(ReaderSettings(fontFileName: fileName));
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderView(
          key: ValueKey(fileName),
          path: '/book.txt',
          title: 'book.txt',
          text: text,
          encoding: TextEncoding.utf8,
          store: store,
          pageIndexCache: cache,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.text(text)).style?.fontFamily,
      fontFamilyFor(fileName),
    );
  }

  await pumpFont('명조.ttf');
  await pumpFont('고딕.otf');

  expect(cache.loadSignatures.toSet(), hasLength(2));
});
```

Also import `package:geulbom/font_library.dart` at the top of the test.

- [ ] **Step 3: Run both tests and verify RED**

Run: `flutter test test/widget_test.dart test/reader_screen_test.dart --plain-name "글꼴"`

Expected: compilation fails because startup restoration, font-aware style, and font-aware cache signatures do not exist.

- [ ] **Step 4: Restore the saved font before the app starts and propagate the library**

In `lib/main.dart`, import `font_library.dart`, create the library beside `state.json`, restore the saved selection, and pass it into the app:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final directory = await getApplicationSupportDirectory();
  final store = AppStore(
    File('${directory.path}${Platform.pathSeparator}state.json'),
  );
  await store.load();
  final fontLibrary = FontLibrary(
    Directory('${directory.path}${Platform.pathSeparator}fonts'),
  );
  await restoreSelectedFont(store, fontLibrary);
  runApp(GeulbomApp(store: store, fontLibrary: fontLibrary));
}

Future<void> restoreSelectedFont(AppStore store, FontLibrary fontLibrary) async {
  final selected = store.data.settings.fontFileName;
  if (selected == null || await fontLibrary.loadSelected(selected)) return;
  store.updateSettings(store.data.settings.copyWith(fontFileName: null));
  await store.save();
}
```

Add optional `FontLibrary? fontLibrary` fields to `GeulbomApp` and `HomeScreen`, pass it through `HomeScreen` and `_openReader`, and preserve the existing parameter defaults for tests:

```dart
class GeulbomApp extends StatelessWidget {
  const GeulbomApp({super.key, required this.store, this.fontLibrary});

  final AppStore store;
  final FontLibrary? fontLibrary;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store, this.fontLibrary});

  final AppStore store;
  final FontLibrary? fontLibrary;
}
```

Replace `MaterialApp`'s home with:

```dart
home: HomeScreen(store: store, fontLibrary: fontLibrary),
```

Replace `_openReader`'s route builder with:

```dart
builder: (context) => ReaderScreen(
  path: path,
  store: widget.store,
  fontLibrary: widget.fontLibrary,
),
```

- [ ] **Step 5: Propagate the library into the reader and include the selected family in layout**

In `lib/reader_screen.dart`, import `font_library.dart`, add nullable library fields, and keep direct `ReaderView` tests working:

```dart
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
}
```

Add this argument to the `ReaderView` returned from `ReaderScreen.build`:

```dart
fontLibrary: widget.fontLibrary,
```

Update the body style getter:

```dart
TextStyle get _textStyle => TextStyle(
  color: Color(_settings.foreground.value),
  fontFamily: fontFamilyFor(_settings.fontFileName),
  fontSize: _settings.fontSize,
  height: _settings.lineHeight,
);
```

Add the font filename to `_ensurePages`'s existing JSON signature map:

```dart
'fontFileName': _settings.fontFileName,
```

- [ ] **Step 6: Run Task 3 tests and verify GREEN**

Run: `dart format lib/main.dart lib/reader_screen.dart test/widget_test.dart test/reader_screen_test.dart`

Run: `flutter test test/widget_test.dart test/reader_screen_test.dart --reporter expanded`

Expected: both new tests and all existing tests in those files pass.

- [ ] **Step 7: Commit Task 3**

```powershell
git add -- lib/main.dart lib/reader_screen.dart test/widget_test.dart test/reader_screen_test.dart
git commit -m "feat: apply imported fonts to reader"
```

---

### Task 4: Manage Fonts in Display Settings

**Files:**
- Modify: `lib/reader_screen.dart:1042-1217`
- Modify: `test/reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 2 `FontLibrary`, `ImportedFont`, `fontFamilyFor`, and `pickFontFile`; existing `_showSettings`, `_applySettings`, and `_showMessage`
- Produces: `시스템 기본 글꼴`, imported font choices, `로컬 글꼴 가져오기`, accessible delete actions, font-aware preview, and Korean failure messages

- [ ] **Step 1: Extend the reader test helper for injected font I/O**

Replace the test helper at the end of `test/reader_screen_test.dart` with:

```dart
Future<void> _pumpReader(
  WidgetTester tester,
  _MemoryStore store,
  String text, {
  FontLibrary? fontLibrary,
  Future<String?> Function()? pickFont,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ReaderView(
        path: '/book.txt',
        title: 'book.txt',
        text: text,
        encoding: TextEncoding.utf8,
        store: store,
        fontLibrary: fontLibrary,
        pickFont: pickFont ?? pickFontFile,
      ),
    ),
  );
  await tester.pump();
}
```

- [ ] **Step 2: Write failing widget tests for import, preview, apply, and invalid files**

Add to `test/reader_screen_test.dart`:

```dart
testWidgets('표시 설정에서 로컬 글꼴을 가져와 미리보기와 본문에 적용한다', (tester) async {
  final root = await Directory.systemTemp.createTemp('geulbom_font_ui');
  addTearDown(() => root.delete(recursive: true));
  final source = File('${root.path}${Platform.pathSeparator}나눔명조.ttf');
  await source.writeAsBytes([1, 2, 3]);
  final library = FontLibrary(
    Directory('${root.path}${Platform.pathSeparator}fonts'),
    registerFont: (_, _) async {},
  );
  final store = _MemoryStore();
  await _pumpReader(
    tester,
    store,
    '본문',
    fontLibrary: library,
    pickFont: () async => source.path,
  );

  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.tap(find.text('표시 설정'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('로컬 글꼴 가져오기'));
  await tester.pumpAndSettle();

  expect(find.text('나눔명조'), findsOneWidget);
  expect(
    tester.widget<Text>(find.byKey(const Key('font-preview'))).style?.fontFamily,
    fontFamilyFor('나눔명조.ttf'),
  );
  expect(await source.exists(), isTrue);
  expect(await library.findFont('나눔명조.ttf'), isNotNull);

  await tester.ensureVisible(find.text('적용'));
  await tester.tap(find.text('적용'));
  await tester.pumpAndSettle();

  expect(store.data.settings.fontFileName, '나눔명조.ttf');
  expect(
    tester.widget<Text>(find.text('본문')).style?.fontFamily,
    fontFamilyFor('나눔명조.ttf'),
  );
});

testWidgets('지원하지 않는 글꼴 파일은 한국어 오류를 표시한다', (tester) async {
  final root = await Directory.systemTemp.createTemp('geulbom_bad_font_ui');
  addTearDown(() => root.delete(recursive: true));
  final source = File('${root.path}${Platform.pathSeparator}font.txt');
  await source.writeAsString('text');
  final library = FontLibrary(
    Directory('${root.path}${Platform.pathSeparator}fonts'),
    registerFont: (_, _) async {},
  );
  await _pumpReader(
    tester,
    _MemoryStore(),
    '본문',
    fontLibrary: library,
    pickFont: () async => source.path,
  );

  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.tap(find.text('표시 설정'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('로컬 글꼴 가져오기'));
  await tester.pumpAndSettle();

  expect(find.text('지원하는 글꼴은 TTF 또는 OTF 파일입니다.'), findsOneWidget);
  expect(await library.listFonts(), isEmpty);
});
```

- [ ] **Step 3: Write the failing deletion test**

Add to `test/reader_screen_test.dart`:

```dart
testWidgets('가져온 글꼴을 확인 후 삭제하고 시스템 기본값으로 복구한다', (tester) async {
  final root = await Directory.systemTemp.createTemp('geulbom_delete_font_ui');
  addTearDown(() => root.delete(recursive: true));
  final source = File('${root.path}${Platform.pathSeparator}고딕.otf');
  await source.writeAsBytes([1]);
  final library = FontLibrary(
    Directory('${root.path}${Platform.pathSeparator}fonts'),
    registerFont: (_, _) async {},
  );
  final imported = await library.importFont(source.path);
  final store = _MemoryStore()
    ..updateSettings(ReaderSettings(fontFileName: imported.fileName));
  await _pumpReader(tester, store, '본문', fontLibrary: library);

  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.tap(find.text('표시 설정'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('delete-font-${imported.fileName}')));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, '삭제'));
  await tester.pumpAndSettle();

  expect(await imported.file.exists(), isFalse);
  expect(store.data.settings.fontFileName, isNull);
  expect(find.text('고딕'), findsNothing);
});
```

- [ ] **Step 4: Run the widget tests and verify RED**

Run: `flutter test test/reader_screen_test.dart --plain-name "글꼴" --reporter expanded`

Expected: the new tests fail because the display settings contain no font controls, preview family, import action, or delete action.

- [ ] **Step 5: Load the catalog when display settings opens**

At the start of `_showSettings` in `lib/reader_screen.dart`, load the current catalog before constructing the existing draft and sheet:

```dart
Future<void> _showSettings() async {
  final fontLibrary = widget.fontLibrary;
  var fonts = fontLibrary == null
      ? <ImportedFont>[]
      : await fontLibrary.listFonts();
  if (!mounted) return;
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
  // Keep the existing showModalBottomSheet body below.
```

- [ ] **Step 6: Add system/imported choices and the import action**

Insert this `글꼴` section after the existing reading-mode `Wrap` and before the font-size stepper:

```dart
const SizedBox(height: 12),
const Text('글꼴'),
Align(
  alignment: Alignment.centerLeft,
  child: ChoiceChip(
    key: const Key('font-option-system'),
    label: const Text('시스템 기본 글꼴'),
    selected: draft.fontFileName == null,
    onSelected: (_) => setSheetState(() {
      draft = draft.copyWith(fontFileName: null);
    }),
  ),
),
for (final font in fonts)
  Row(
    children: [
      Expanded(
        child: Align(
          alignment: Alignment.centerLeft,
          child: ChoiceChip(
            key: Key('font-option-${font.fileName}'),
            label: Text(font.label),
            selected: draft.fontFileName == font.fileName,
            onSelected: (_) async {
              try {
                await fontLibrary!.loadFont(font);
                if (!sheetContext.mounted) return;
                setSheetState(() {
                  draft = draft.copyWith(fontFileName: font.fileName);
                });
              } catch (_) {
                _showMessage('글꼴을 불러오지 못했습니다.');
              }
            },
          ),
        ),
      ),
      IconButton(
        key: Key('delete-font-${font.fileName}'),
        tooltip: '${font.label} 삭제',
        icon: const Icon(Icons.delete_outline),
        onPressed: () async {
          final confirmed = await showDialog<bool>(
            context: sheetContext,
            builder: (dialogContext) => AlertDialog(
              title: const Text('글꼴 삭제'),
              content: Text('${font.label} 글꼴의 앱 내부 복사본을 삭제할까요?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('삭제'),
                ),
              ],
            ),
          );
          if (confirmed != true) return;
          try {
            await fontLibrary!.deleteFont(font);
            if (!sheetContext.mounted) return;
            final reset = draft.fontFileName == font.fileName ||
                _settings.fontFileName == font.fileName;
            setSheetState(() {
              fonts.removeWhere((item) => item.fileName == font.fileName);
              if (reset) draft = draft.copyWith(fontFileName: null);
            });
            if (reset) {
              _applySettings(_settings.copyWith(fontFileName: null));
              await widget.store.save();
            }
          } catch (_) {
            _showMessage('글꼴을 삭제하지 못했습니다.');
          }
        },
      ),
    ],
  ),
const SizedBox(height: 4),
OutlinedButton.icon(
  onPressed: fontLibrary == null
      ? null
      : () async {
          final path = await widget.pickFont();
          if (path == null) return;
          try {
            final font = await fontLibrary.importFont(path);
            if (!sheetContext.mounted) return;
            setSheetState(() {
              fonts = [...fonts, font]
                ..sort(
                  (a, b) =>
                      a.label.toLowerCase().compareTo(b.label.toLowerCase()),
                );
              draft = draft.copyWith(fontFileName: font.fileName);
            });
          } on FormatException catch (error) {
            _showMessage(error.message.toString());
          } catch (_) {
            _showMessage('글꼴을 가져오지 못했습니다.');
          }
        },
  icon: const Icon(Icons.add),
  label: const Text('로컬 글꼴 가져오기'),
),
```

- [ ] **Step 7: Apply the draft font to the preview**

Give the existing preview `Text` a key and family:

```dart
Text(
  '한글 미리보기 가나다라',
  key: const Key('font-preview'),
  style: TextStyle(
    color: Color(draft.foreground.value),
    fontFamily: fontFamilyFor(draft.fontFileName),
    fontSize: 18,
  ),
),
```

- [ ] **Step 8: Run Task 4 tests and verify GREEN**

Run: `dart format lib/reader_screen.dart test/reader_screen_test.dart`

Run: `flutter test test/reader_screen_test.dart --reporter expanded`

Expected: all reader tests pass, including import, Korean validation feedback, preview/body selection, and confirmed deletion.

- [ ] **Step 9: Commit Task 4**

```powershell
git add -- lib/reader_screen.dart test/reader_screen_test.dart
git commit -m "feat: manage fonts in display settings"
```

---

## Final Verification

- [ ] Run `dart format --output=none --set-exit-if-changed lib test`; expect zero changed files.
- [ ] Run `flutter analyze`; expect `No issues found!`.
- [ ] Run `flutter test --reporter expanded`; expect the full suite to pass with zero failures.
- [ ] Run `flutter build apk --release`; expect `build/app/outputs/flutter-apk/app-release.apk` to be produced.
- [ ] Run `Get-FileHash -Algorithm SHA256 build/app/outputs/flutter-apk/app-release.apk`; record the APK SHA-256.
- [ ] Run `git status --short`; expect no uncommitted files after the task commits.
