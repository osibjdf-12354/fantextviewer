# 글봄 Android 텍스트 뷰어 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Android 저장소의 한국어 `.txt` 파일을 탐색하고 스크롤·페이지 방식으로 읽으며 위치와 북마크를 보존하는 개인용 APK를 만든다.

**Architecture:** Flutter 기본 `ChangeNotifier` 상태와 화면 세 개(홈, 파일 탐색기, 읽기)를 사용한다. 텍스트 디코딩·분할·페이지 계산은 UI 밖의 작은 함수로 두고, 설정과 문서별 상태는 앱 지원 디렉터리의 JSON 파일 하나에 저장한다.

**Tech Stack:** Flutter 3.44.6, Dart 3.12.2, Android API 24+, `permission_handler`, `file_picker`, `charset_converter`, `path_provider`, `scrollable_positioned_list`, `wakelock_plus`

## Global Constraints

- 앱 표시 이름은 `글봄`, 프로젝트 이름은 `geulbom`, Android application id는 `com.songs.geulbom`이다.
- Android 전용 개인 APK이며 네트워크 권한을 요청하지 않는다.
- UTF-8, UTF-16 LE/BE, CP949/EUC-KR 자동 판별과 수동 선택을 지원한다.
- 읽기 위치의 정본은 디코딩된 문자열의 문자 오프셋이다.
- 최초 배경색은 RGB(196, 236, 187), 최초 글자색은 RGB(32, 48, 32)이며 두 색 모두 채널별 직접 입력과 템플릿 선택을 지원한다.
- 전체 파일 접근 권한이 없으면 시스템 파일 선택기로 `.txt` 하나를 열 수 있어야 한다.
- 새 동작은 실패하는 테스트를 먼저 실행한 뒤 최소 구현으로 통과시킨다.
- 별도 데이터베이스, 상태 관리 패키지, 클라우드 기능은 추가하지 않는다.

---

## File Map

- `lib/main.dart`: 앱 초기화, 테마, 홈 화면 연결
- `lib/models.dart`: 표시 설정, 읽기 위치, 북마크, 최근 파일의 JSON 모델
- `lib/app_store.dart`: JSON 파일 로드·저장과 문서 상태 변경
- `lib/text_document.dart`: 인코딩 판별·디코딩·줄바꿈 정규화·구간 분할
- `lib/file_browser.dart`: 저장소 권한, 파일 선택기, 폴더 목록과 탐색 화면
- `lib/text_paginator.dart`: 화면 크기에 맞는 페이지 경계 계산
- `lib/reader_screen.dart`: 파일 로드, 두 읽기 모드, 메뉴, 검색, 이동, 북마크, 설정
- `test/*_test.dart`: 위 파일의 핵심 동작과 화면 상호작용 검증

---

### Task 1: Flutter 골격과 한국어 텍스트 디코더

**Files:**
- Create: Flutter Android scaffold under repository root
- Create: `lib/text_document.dart`
- Create: `test/text_document_test.dart`
- Modify: `pubspec.yaml`
- Modify: `android/app/src/main/AndroidManifest.xml`

**Interfaces:**
- Produces: `TextEncoding`, `DecodedText`, `TextChunk`, `detectTextEncoding`, `decodeText`, `splitText`

- [ ] **Step 1: Generate the Android-only Flutter scaffold**

Run:

```powershell
flutter create --platforms=android --project-name=geulbom --org=com.songs .
```

Expected: project generation succeeds without deleting `docs/`.

- [ ] **Step 2: Add only the required packages**

Run:

```powershell
flutter pub add permission_handler file_picker charset_converter path_provider scrollable_positioned_list wakelock_plus
```

Expected: dependency resolution succeeds on Flutter 3.44.6.

- [ ] **Step 3: Write the failing decoder tests**

Create `test/text_document_test.dart`:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:geulbom/text_document.dart';

void main() {
  test('BOM, strict UTF-8, and invalid UTF-8 select the expected encoding', () {
    expect(detectTextEncoding(Uint8List.fromList([0xef, 0xbb, 0xbf, 0x61])), TextEncoding.utf8);
    expect(detectTextEncoding(Uint8List.fromList([0xff, 0xfe, 0x61, 0])), TextEncoding.utf16le);
    expect(detectTextEncoding(Uint8List.fromList([0xfe, 0xff, 0, 0x61])), TextEncoding.utf16be);
    expect(detectTextEncoding(Uint8List.fromList([0xb0, 0xa1])), TextEncoding.cp949);
  });

  test('decoding removes BOM and normalizes all newline styles', () async {
    final bytes = Uint8List.fromList([0xef, 0xbb, 0xbf, ...utf8.encode('가\r\n나\r다')]);
    final decoded = await decodeText(bytes);
    expect(decoded.encoding, TextEncoding.utf8);
    expect(decoded.text, '가\n나\n다');
  });

  test('CP949 decoding uses the platform boundary passed to the decoder', () async {
    final decoded = await decodeText(
      Uint8List.fromList([0xb0, 0xa1]),
      cp949Decoder: (_) async => '가',
    );
    expect(decoded.text, '가');
  });

  test('splitText preserves every character and reports source offsets', () {
    final chunks = splitText('가나다\n라마바\n사아자', maxChars: 5);
    expect(chunks.map((chunk) => chunk.text).join(), '가나다\n라마바\n사아자');
    expect(chunks.first.start, 0);
    expect(chunks.last.end, '가나다\n라마바\n사아자'.length);
  });
}
```

- [ ] **Step 4: Run the decoder tests and verify RED**

Run: `flutter test test/text_document_test.dart`

Expected: FAIL because `package:geulbom/text_document.dart` does not exist.

- [ ] **Step 5: Implement the decoder and chunker**

Create `lib/text_document.dart` with these public declarations and behavior:

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:charset_converter/charset_converter.dart';

enum TextEncoding { utf8, utf16le, utf16be, cp949 }

class DecodedText {
  const DecodedText(this.text, this.encoding);
  final String text;
  final TextEncoding encoding;
}

class TextChunk {
  const TextChunk({required this.start, required this.end, required this.text});
  final int start;
  final int end;
  final String text;
}

TextEncoding detectTextEncoding(Uint8List bytes) {
  if (bytes.length >= 3 && bytes[0] == 0xef && bytes[1] == 0xbb && bytes[2] == 0xbf) return TextEncoding.utf8;
  if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe) return TextEncoding.utf16le;
  if (bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff) return TextEncoding.utf16be;
  try {
    utf8.decode(bytes, allowMalformed: false);
    return TextEncoding.utf8;
  } on FormatException {
    return TextEncoding.cp949;
  }
}

Future<DecodedText> decodeText(
  Uint8List bytes, {
  TextEncoding? forced,
  Future<String> Function(Uint8List)? cp949Decoder,
}) async {
  final encoding = forced ?? detectTextEncoding(bytes);
  final String value;
  switch (encoding) {
    case TextEncoding.utf8:
      final start = bytes.length >= 3 && bytes[0] == 0xef && bytes[1] == 0xbb && bytes[2] == 0xbf ? 3 : 0;
      value = utf8.decode(bytes.sublist(start), allowMalformed: false);
    case TextEncoding.utf16le:
      value = _decodeUtf16(bytes, Endian.little);
    case TextEncoding.utf16be:
      value = _decodeUtf16(bytes, Endian.big);
    case TextEncoding.cp949:
      value = await (cp949Decoder ?? _decodeCp949)(bytes);
  }
  return DecodedText(value.replaceAll('\r\n', '\n').replaceAll('\r', '\n'), encoding);
}

String _decodeUtf16(Uint8List bytes, Endian endian) {
  var start = bytes.length >= 2 && ((bytes[0] == 0xff && bytes[1] == 0xfe) || (bytes[0] == 0xfe && bytes[1] == 0xff)) ? 2 : 0;
  final codes = <int>[];
  for (; start + 1 < bytes.length; start += 2) {
    codes.add(endian == Endian.little ? bytes[start] | bytes[start + 1] << 8 : bytes[start] << 8 | bytes[start + 1]);
  }
  return String.fromCharCodes(codes);
}

Future<String> _decodeCp949(Uint8List bytes) async {
  try {
    return await CharsetConverter.decode('MS949', bytes);
  } catch (_) {
    return CharsetConverter.decode('EUC-KR', bytes);
  }
}

List<TextChunk> splitText(String text, {int maxChars = 1200}) {
  if (text.isEmpty) return const [];
  final result = <TextChunk>[];
  var start = 0;
  while (start < text.length) {
    var end = (start + maxChars).clamp(0, text.length);
    if (end < text.length) {
      final newline = text.lastIndexOf('\n', end);
      if (newline >= start + maxChars ~/ 2) end = newline + 1;
    }
    result.add(TextChunk(start: start, end: end, text: text.substring(start, end)));
    start = end;
  }
  return result;
}
```

- [ ] **Step 6: Add Android storage declarations and Korean app label**

In `android/app/src/main/AndroidManifest.xml`, add before `<application>`:

```xml
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />
<uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE" />
```

Set the application fields to:

```xml
<application
    android:label="글봄"
    android:name="${applicationName}"
    android:icon="@mipmap/ic_launcher"
    android:requestLegacyExternalStorage="true">
```

- [ ] **Step 7: Verify GREEN and commit**

Run: `dart format lib test && flutter test test/text_document_test.dart`

Expected: 4 tests PASS.

Commit:

```powershell
git add .
git commit -m "feat: decode Korean text files"
```

---

### Task 2: 읽기 설정·위치·북마크 영속 저장

**Files:**
- Create: `lib/models.dart`
- Create: `lib/app_store.dart`
- Create: `test/app_store_test.dart`

**Interfaces:**
- Produces: `ReadingMode`, `RgbColor`, `ReaderSettings`, `Bookmark`, `DocumentState`, `AppData`, `AppStore`

- [ ] **Step 1: Write failing model and store tests**

Create `test/app_store_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geulbom/app_store.dart';
import 'package:geulbom/models.dart';

void main() {
  test('settings and document state survive a JSON file round trip', () async {
    final dir = await Directory.systemTemp.createTemp('geulbom_store');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}${Platform.pathSeparator}state.json');
    final store = AppStore(file);
    store.data.settings = const ReaderSettings(mode: ReadingMode.page, fontSize: 24);
    store.updateProgress('/books/a.txt', offset: 42, scrollAlignment: .25);
    store.addBookmark('/books/a.txt', const Bookmark(offset: 42, excerpt: '본문', createdAt: '2026-07-15T00:00:00.000Z'));
    await store.save();

    final restored = AppStore(file);
    await restored.load();
    expect(restored.data.settings.fontSize, 24);
    expect(restored.data.settings.background, const RgbColor(196, 236, 187));
    expect(restored.data.settings.foreground, const RgbColor(32, 48, 32));
    expect(restored.document('/books/a.txt').offset, 42);
    expect(restored.document('/books/a.txt').bookmarks.single.excerpt, '본문');
  });

  test('duplicate bookmark offsets are ignored and offsets are clamped', () {
    final store = AppStore(File('unused'));
    const bookmark = Bookmark(offset: 9, excerpt: '가나다', createdAt: '2026-07-15T00:00:00.000Z');
    store.addBookmark('/a.txt', bookmark);
    store.addBookmark('/a.txt', bookmark);
    store.updateProgress('/a.txt', offset: 99, documentLength: 10);
    expect(store.document('/a.txt').bookmarks, hasLength(1));
    expect(store.document('/a.txt').offset, 10);
  });
}
```

- [ ] **Step 2: Run store tests and verify RED**

Run: `flutter test test/app_store_test.dart`

Expected: FAIL because the model and store libraries do not exist.

- [ ] **Step 3: Implement JSON models and one-file store**

Implement immutable value conversion in `lib/models.dart` with these exact defaults:

```dart
enum ReadingMode { scroll, page }

class RgbColor {
  const RgbColor(this.red, this.green, this.blue)
      : assert(red >= 0 && red <= 255),
        assert(green >= 0 && green <= 255),
        assert(blue >= 0 && blue <= 255);
  final int red;
  final int green;
  final int blue;
  Map<String, int> toJson() => {'red': red, 'green': green, 'blue': blue};
  factory RgbColor.fromJson(Map<String, dynamic> json) => RgbColor(
    (json['red'] as num).toInt(),
    (json['green'] as num).toInt(),
    (json['blue'] as num).toInt(),
  );
  @override
  bool operator ==(Object other) =>
      other is RgbColor && red == other.red && green == other.green && blue == other.blue;
  @override
  int get hashCode => Object.hash(red, green, blue);
}

class ReaderSettings {
  const ReaderSettings({
    this.mode = ReadingMode.scroll,
    this.background = const RgbColor(196, 236, 187),
    this.foreground = const RgbColor(32, 48, 32),
    this.fontSize = 20,
    this.lineHeight = 1.65,
    this.horizontalPadding = 20,
    this.keepAwake = false,
  });
  final ReadingMode mode;
  final RgbColor background;
  final RgbColor foreground;
  final double fontSize;
  final double lineHeight;
  final double horizontalPadding;
  final bool keepAwake;
  Map<String, Object> toJson() => {
    'mode': mode.name,
    'background': background.toJson(),
    'foreground': foreground.toJson(),
    'fontSize': fontSize,
    'lineHeight': lineHeight, 'horizontalPadding': horizontalPadding, 'keepAwake': keepAwake,
  };
  factory ReaderSettings.fromJson(Map<String, dynamic> json) => ReaderSettings(
    mode: ReadingMode.values.byName(json['mode'] as String? ?? 'scroll'),
    background: json['background'] == null
        ? const RgbColor(196, 236, 187)
        : RgbColor.fromJson(json['background'] as Map<String, dynamic>),
    foreground: json['foreground'] == null
        ? const RgbColor(32, 48, 32)
        : RgbColor.fromJson(json['foreground'] as Map<String, dynamic>),
    fontSize: (json['fontSize'] as num? ?? 20).toDouble(),
    lineHeight: (json['lineHeight'] as num? ?? 1.65).toDouble(),
    horizontalPadding: (json['horizontalPadding'] as num? ?? 20).toDouble(),
    keepAwake: json['keepAwake'] as bool? ?? false,
  );
}

class Bookmark {
  const Bookmark({required this.offset, required this.excerpt, required this.createdAt});
  final int offset;
  final String excerpt;
  final String createdAt;
  Map<String, Object> toJson() => {'offset': offset, 'excerpt': excerpt, 'createdAt': createdAt};
  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
    offset: json['offset'] as int, excerpt: json['excerpt'] as String, createdAt: json['createdAt'] as String,
  );
}
```

Add `DocumentState` with `path`, `offset`, `scrollAlignment`, nullable `encoding`, `lastOpened`, and `List<Bookmark> bookmarks`; add `AppData` with `ReaderSettings settings` and `Map<String, DocumentState> documents`. Both classes must round-trip all fields through `toJson` and `fromJson`.

Implement `lib/app_store.dart` as a `ChangeNotifier` over one `File`: `load`, `save`, `document`, `updateSettings`, `touchRecent`, `updateProgress`, `addBookmark`, `removeBookmark`. `save` creates the parent directory and writes `jsonEncode(data.toJson())` with `flush: true`. `load` uses defaults when the file is absent and preserves a malformed file as `state.json.broken` before falling back to defaults.

- [ ] **Step 4: Verify GREEN and commit**

Run: `dart format lib test && flutter test test/app_store_test.dart`

Expected: 2 tests PASS.

Commit:

```powershell
git add lib/models.dart lib/app_store.dart test/app_store_test.dart
git commit -m "feat: persist reading state"
```

---

### Task 3: 폴더 목록과 `.txt` 파일 탐색

**Files:**
- Create: `lib/file_browser.dart`
- Create: `test/file_browser_test.dart`

**Interfaces:**
- Consumes: `AppStore`
- Produces: `BrowserEntry`, `BrowserSort`, `listTextEntries`, `FileBrowserScreen`, `pickTextFile`

- [ ] **Step 1: Write failing filesystem tests**

Create `test/file_browser_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geulbom/file_browser.dart';

void main() {
  test('directories come first and only visible txt files remain', () async {
    final dir = await Directory.systemTemp.createTemp('geulbom_files');
    addTearDown(() => dir.delete(recursive: true));
    await Directory('${dir.path}/folder').create();
    await File('${dir.path}/b.TXT').writeAsString('b');
    await File('${dir.path}/a.txt').writeAsString('a');
    await File('${dir.path}/skip.pdf').writeAsString('x');
    await File('${dir.path}/.hidden.txt').writeAsString('x');

    final entries = await listTextEntries(dir, BrowserSort.name);
    expect(entries.map((entry) => entry.name), ['folder', 'a.txt', 'b.TXT']);
    expect(entries.first.isDirectory, isTrue);
  });
}
```

- [ ] **Step 2: Run and verify RED**

Run: `flutter test test/file_browser_test.dart`

Expected: FAIL because `file_browser.dart` does not exist.

- [ ] **Step 3: Implement listing, permission fallback, and browser screen**

Implement `BrowserEntry` with `path`, `name`, `isDirectory`, `modified`; `BrowserSort` with `name` and `modified`; and:

```dart
Future<List<BrowserEntry>> listTextEntries(Directory directory, BrowserSort sort) async {
  final entries = <BrowserEntry>[];
  await for (final entity in directory.list(followLinks: false)) {
    final name = entity.path.split(Platform.pathSeparator).last;
    if (name.startsWith('.')) continue;
    final isDirectory = entity is Directory;
    if (!isDirectory && !name.toLowerCase().endsWith('.txt')) continue;
    entries.add(BrowserEntry(
      path: entity.path,
      name: name,
      isDirectory: isDirectory,
      modified: (await entity.stat()).modified,
    ));
  }
  entries.sort((a, b) {
    if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
    return sort == BrowserSort.name
        ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
        : b.modified.compareTo(a.modified);
  });
  return entries;
}
```

Add `Future<String?> pickTextFile()` using `FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['txt'])`. Add `FileBrowserScreen` that starts at `/storage/emulated/0`, displays breadcrumb/current path, search and sort actions, enters directories, opens a selected file through `ValueChanged<String> onOpenFile`, and shows Korean empty/error states. Before direct browsing, accept either `Permission.manageExternalStorage.isGranted` or `Permission.storage.isGranted`; request both paths as applicable and expose the system picker when denied.

- [ ] **Step 4: Verify GREEN and commit**

Run: `dart format lib test && flutter test test/file_browser_test.dart`

Expected: 1 test PASS.

Commit:

```powershell
git add lib/file_browser.dart test/file_browser_test.dart android/app/src/main/AndroidManifest.xml
git commit -m "feat: browse text files"
```

---

### Task 4: 화면 크기 기반 페이지 계산

**Files:**
- Create: `lib/text_paginator.dart`
- Create: `test/text_paginator_test.dart`

**Interfaces:**
- Produces: `TextPage`, `paginateText`, `pageForOffset`

- [ ] **Step 1: Write failing paginator tests**

Create `test/text_paginator_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geulbom/text_paginator.dart';

void main() {
  testWidgets('page ranges cover text once and locate a saved offset', (tester) async {
    final text = List.filled(200, '가나다라마바사아자차카타파하 ').join();
    final pages = await paginateText(
      text: text,
      size: const Size(240, 320),
      style: const TextStyle(fontSize: 20, height: 1.5),
    );
    expect(pages, isNotEmpty);
    expect(pages.first.start, 0);
    expect(pages.last.end, text.length);
    for (var i = 1; i < pages.length; i++) expect(pages[i - 1].end, pages[i].start);
    expect(pageForOffset(pages, pages[1].start), 1);
  });
}
```

- [ ] **Step 2: Run and verify RED**

Run: `flutter test test/text_paginator_test.dart`

Expected: FAIL because `text_paginator.dart` does not exist.

- [ ] **Step 3: Implement `TextPainter` pagination**

Create `TextPage { int start; int end; }`. Implement `paginateText` to repeatedly lay out at most 4096 characters from the current offset, grow the candidate when it entirely fits, and use `TextPainter.getPositionForOffset(Offset(size.width, size.height))` to choose the next boundary. Guarantee at least one UTF-16 code unit per page, yield with `await Future<void>.delayed(Duration.zero)` every 25 pages, and report optional `ValueChanged<double> onProgress`. Implement binary search in `pageForOffset(List<TextPage>, int)` and clamp offsets outside the document.

- [ ] **Step 4: Verify GREEN and commit**

Run: `dart format lib test && flutter test test/text_paginator_test.dart`

Expected: 1 test PASS.

Commit:

```powershell
git add lib/text_paginator.dart test/text_paginator_test.dart
git commit -m "feat: paginate text for the viewport"
```

---

### Task 5: 스크롤·페이지 읽기 화면과 메뉴

**Files:**
- Create: `lib/reader_screen.dart`
- Create: `test/reader_screen_test.dart`

**Interfaces:**
- Consumes: `AppStore`, `decodeText`, `splitText`, `paginateText`, `pageForOffset`
- Produces: `ReaderScreen`, `ReaderView`

- [ ] **Step 1: Write failing reader interaction tests**

Create `test/reader_screen_test.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geulbom/app_store.dart';
import 'package:geulbom/models.dart';
import 'package:geulbom/reader_screen.dart';

void main() {
  testWidgets('reader exposes drawer actions and switches reading mode', (tester) async {
    final dir = await Directory.systemTemp.createTemp('geulbom_reader');
    addTearDown(() => dir.delete(recursive: true));
    final store = AppStore(File('${dir.path}/state.json'));
    await tester.pumpWidget(MaterialApp(
      home: ReaderView(path: '/book.txt', title: 'book.txt', text: '가나다라마바사', store: store),
    ));

    await tester.tap(find.byTooltip('메뉴 열기'));
    await tester.pumpAndSettle();
    expect(find.text('위치 이동'), findsOneWidget);
    expect(find.text('본문 검색'), findsOneWidget);
    expect(find.text('북마크'), findsOneWidget);
    expect(find.text('표시 설정'), findsOneWidget);

    await tester.tap(find.text('표시 설정'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('페이지 넘김'));
    await tester.pumpAndSettle();
    expect(store.data.settings.mode, ReadingMode.page);
  });
}
```

- [ ] **Step 2: Run and verify RED**

Run: `flutter test test/reader_screen_test.dart`

Expected: FAIL because `reader_screen.dart` does not exist.

- [ ] **Step 3: Implement loading and the two reader bodies**

`ReaderScreen` reads `File(path).readAsBytes()`, applies the file's saved encoding through `decodeText`, calls `touchRecent`, and shows Korean loading/error/empty-file states. It passes decoded content to `ReaderView`.

`ReaderView` is a stateful `Scaffold` with an always-visible `AppBar`, automatic hamburger button, title, and bookmark icon. Its drawer has these exact labels: `파일 열기`, `위치 이동`, `본문 검색`, `북마크`, `표시 설정`, `파일 정보`.

For scroll mode, use `ScrollablePositionedList.builder` over `splitText(text)` with the saved chunk index and alignment. Observe `ItemPositionsListener.itemPositions`; choose the smallest visible index with `itemTrailingEdge > 0`, store its chunk start as the character offset, and display `offset / text.length` as a percentage.

For page mode, compute pages after `LayoutBuilder` supplies the usable size, show calculation progress, then use `PageView.builder(initialPage: pageForOffset(pages, savedOffset))`. On page change, save `pages[index].start`. Render `SelectableText(text.substring(page.start, page.end))` and show `현재 / 전체` with a slider.

- [ ] **Step 4: Implement drawer actions without extra routes**

- `위치 이동`: one dialog accepting page number or percent, validating bounds before moving.
- `본문 검색`: one dialog and `text.indexOf`; move to the match and report no result with a `SnackBar`.
- `북마크`: bottom sheet listing excerpt/time/delete; tapping moves to the offset.
- Bookmark icon: save the current offset once with a 40-character surrounding excerpt.
- `표시 설정`: bottom sheet for mode, font size 14–36, line height 1.2–2.2, margin 8–40, background/text RGB inputs, color templates, and keep-awake. RGB inputs accept integers 0–255 only, update a live preview, and show a warning below WCAG 4.5:1 contrast. Changes call `AppStore.updateSettings` and invalidate page ranges.
- `파일 정보`: show path, size, detected encoding, and UTF-8/UTF-16 LE/UTF-16 BE/CP949 manual choices; a change reloads the file.
- `파일 열기`: pop the reader back to the file browser.

Provide four buttons with exact background/text pairs: `기본 연두` RGB(196,236,187)/RGB(32,48,32), `종이` RGB(255,253,248)/RGB(32,32,32), `밤` RGB(18,18,18)/RGB(232,232,232), and `세피아` RGB(244,236,216)/RGB(59,49,38). Apply the stored RGB values directly to the reader background and text. Call `WakelockPlus.toggle(enable: settings.keepAwake)` while the reader is mounted and disable it on dispose.

- [ ] **Step 5: Verify GREEN and commit**

Run: `dart format lib test && flutter test test/reader_screen_test.dart`

Expected: interaction test PASS with no framework exceptions.

Commit:

```powershell
git add lib/reader_screen.dart test/reader_screen_test.dart
git commit -m "feat: add scroll and page reading"
```

---

### Task 6: 앱 연결, 최근 파일, 전체 검증과 APK

**Files:**
- Replace: `lib/main.dart`
- Replace: `test/widget_test.dart`
- Modify: `README.md`

**Interfaces:**
- Consumes: `AppStore`, `FileBrowserScreen`, `ReaderScreen`

- [ ] **Step 1: Write the failing app smoke test**

Replace `test/widget_test.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geulbom/app_store.dart';
import 'package:geulbom/main.dart';

void main() {
  testWidgets('app starts with Korean title and file actions', (tester) async {
    final dir = await Directory.systemTemp.createTemp('geulbom_app');
    addTearDown(() => dir.delete(recursive: true));
    final store = AppStore(File('${dir.path}/state.json'));
    await tester.pumpWidget(GeulbomApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('글봄'), findsOneWidget);
    expect(find.byIcon(Icons.folder_open), findsWidgets);
  });
}
```

- [ ] **Step 2: Run and verify RED**

Run: `flutter test test/widget_test.dart`

Expected: FAIL because `GeulbomApp` is not implemented.

- [ ] **Step 3: Wire initialization and navigation**

Implement `main` as:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final directory = await getApplicationSupportDirectory();
  final store = AppStore(File('${directory.path}${Platform.pathSeparator}state.json'));
  await store.load();
  runApp(GeulbomApp(store: store));
}
```

`GeulbomApp` builds a Korean Material 3 `MaterialApp` titled `글봄`. Its home shows recent files sorted by `lastOpened`, removes dead entries after confirmation, and opens `FileBrowserScreen`. Both recent rows and file-browser selections push `ReaderScreen`; returning refreshes the recent list through `AppStore` notifications.

- [ ] **Step 4: Document local build and permission behavior**

Replace `README.md` with the app purpose, Flutter requirement, commands `flutter pub get`, `flutter test`, `flutter build apk --release`, release APK path, and the Android `모든 파일에 대한 접근` settings step. State that no network permission or file upload exists.

- [ ] **Step 5: Run full verification**

Run in order:

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
flutter build apk --release
```

Expected: every command exits 0; all tests pass; APKs exist at `build/app/outputs/flutter-apk/app-debug.apk` and `build/app/outputs/flutter-apk/app-release.apk`.

- [ ] **Step 6: Check the final diff and commit**

Run:

```powershell
git status --short
git diff --check
```

Expected: only planned app files are changed and `git diff --check` prints nothing.

Commit:

```powershell
git add lib test android pubspec.yaml pubspec.lock README.md
git commit -m "feat: ship geulbom Android viewer"
```

---

## Manual Android Check

- Install the release APK and grant `모든 파일에 대한 접근`.
- Open UTF-8, UTF-16 LE, UTF-16 BE, and CP949 Korean samples.
- Switch scroll/page modes and confirm the same passage remains visible.
- Close and relaunch; confirm the last passage returns.
- Add, open, and delete multiple bookmarks.
- Search Korean text and move by page and percentage.
- Deny full access and confirm the system file picker still opens a `.txt` file.
