# Reader Navigation UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make page navigation and bookmarks work in both reading modes while simplifying reader chrome, color templates, and display controls.

**Architecture:** Keep `Bookmark.offset` and the existing `TextPainter` paginator. Calculate the same page map from the reader body's current viewport in both modes, then derive page movement and bookmark labels from that map. Keep all UI changes in `ReaderView`; add no package or persistence migration.

**Tech Stack:** Dart 3.12, Flutter 3.44, Material widgets, `flutter_test`

## Global Constraints

- Page input accepts integer page numbers only; percent input is removed.
- Reader app bar height is 48px while its icon touch targets remain 48px.
- Page mode has no persistent bottom page/slider bar.
- Font size uses `14~36` in steps of `1`; horizontal padding uses `8~40` in steps of `1`; line height uses `1.2~2.2` in steps of `0.1`.
- Default background remains `R196 G236 B187`.
- Existing saved offsets, bookmarks, settings JSON, dependencies, and Korean encodings remain compatible.

---

### Task 1: Shared Page Map, Page Navigation, Bookmarks, and Reader Chrome

**Files:**
- Modify: `lib/reader_screen.dart:1-640`
- Modify: `test/reader_screen_test.dart`

**Interfaces:**
- Consumes: `paginateText(...)`, `pageForOffset(List<TextPage>, int)`, `Bookmark.offset`
- Produces: shared body `LayoutBuilder`, page-only `_showGoToDialog()`, page-labelled `_showBookmarks()`, 48px `AppBar`, and `앱 종료` drawer action

- [ ] **Step 1: Add failing widget tests for page-only movement in scroll mode**

Add to `test/reader_screen_test.dart`:

```dart
final _longText = List.filled(300, '가나다라마바사아자차카타파하\n').join();

Future<void> _pumpReader(
  WidgetTester tester,
  _MemoryStore store,
  String text,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ReaderView(
        path: '/book.txt',
        title: 'book.txt',
        text: text,
        encoding: TextEncoding.utf8,
        store: store,
      ),
    ),
  );
  await tester.pump();
}

testWidgets('스크롤 모드에서도 페이지 번호로 이동한다', (tester) async {
  final store = _MemoryStore();
  await tester.binding.setSurfaceSize(const Size(320, 568));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await _pumpReader(tester, store, _longText);
  await tester.pumpAndSettle();

  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.tap(find.text('위치 이동'));
  await tester.pumpAndSettle();

  expect(find.widgetWithText(TextField, '페이지'), findsOneWidget);
  expect(find.textContaining('퍼센트'), findsNothing);
  await tester.enterText(find.byType(TextField), '2');
  await tester.tap(find.text('이동'));
  await tester.pumpAndSettle();

  expect(store.document('/book.txt').offset, greaterThan(0));
});

testWidgets('퍼센트와 범위 밖 페이지를 거부한다', (tester) async {
  final store = _MemoryStore();
  await _pumpReader(tester, store, _longText);
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.tap(find.text('위치 이동'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), '50%');
  await tester.tap(find.text('이동'));
  await tester.pumpAndSettle();

  expect(find.textMatching(RegExp(r'^1~\d+ 사이 페이지를 입력해 주세요\.$')), findsOneWidget);
});
```

- [ ] **Step 2: Run the movement test and verify the root-cause failure**

Run: `flutter test test/reader_screen_test.dart --plain-name "스크롤 모드에서도 페이지 번호로 이동한다"`

Expected: FAIL because the dialog still says `페이지 또는 퍼센트` and `_pages` is null in scroll mode.

- [ ] **Step 3: Add failing widget tests for chrome, exit, and page bookmarks**

Add tests that assert the requested visible behavior:

```dart
testWidgets('읽기 화면은 작은 상단바와 종료 메뉴를 사용하고 하단바가 없다', (tester) async {
  final store = _MemoryStore()
    ..updateSettings(const ReaderSettings(mode: ReadingMode.page));
  await _pumpReader(tester, store, _longText);
  await tester.pumpAndSettle();

  expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, 48);
  expect(find.byType(Slider), findsNothing);
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  expect(find.text('앱 종료'), findsOneWidget);
});

testWidgets('종료 메뉴는 플랫폼 앱 종료를 요청한다', (tester) async {
  final calls = <MethodCall>[];
  final messenger = TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    calls.add(call);
    return null;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
  await _pumpReader(tester, _MemoryStore(), '본문');
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.tap(find.text('앱 종료'));
  await tester.pumpAndSettle();

  expect(calls.any((call) => call.method == 'SystemNavigator.pop'), isTrue);
});

testWidgets('북마크를 페이지 번호로 안내하고 표시한다', (tester) async {
  final store = _MemoryStore();
  await _pumpReader(tester, store, _longText);
  await tester.pumpAndSettle();

  await tester.tap(find.byIcon(Icons.bookmark_add_outlined));
  await tester.pump();
  expect(find.textMatching(RegExp(r'^\d+페이지에 북마크를 저장했습니다\.$')), findsOneWidget);

  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.tap(find.text('북마크'));
  await tester.pumpAndSettle();
  expect(find.textMatching(RegExp(r'^\d+페이지$')), findsOneWidget);
});
```

- [ ] **Step 4: Run the new chrome and bookmark tests and verify they fail**

Run: `flutter test test/reader_screen_test.dart --reporter expanded`

Expected: FAIL on the 56px app bar, existing `Slider`, missing `앱 종료`, percent bookmark label, and percent snackbar.

- [ ] **Step 5: Calculate pages for both reading modes and accept pages only**

In `ReaderView.build`, set `toolbarHeight: 48` and route non-empty content through one viewport builder:

```dart
body: widget.text.isEmpty
    ? Center(child: Text('빈 파일입니다.', style: TextStyle(color: foreground)))
    : LayoutBuilder(
        builder: (context, constraints) {
          final pageSize = Size(
            math.max(1, constraints.maxWidth - _settings.horizontalPadding * 2),
            math.max(1, constraints.maxHeight),
          );
          _ensurePages(pageSize);
          return _settings.mode == ReadingMode.scroll
              ? _buildScrollReader()
              : _buildPageReader();
        },
      ),
```

Remove the nested `LayoutBuilder` and bottom `Column`/`Slider` from `_buildPageReader`; return only its loading state or `PageView.builder`.

Replace `_showGoToDialog` percent parsing with:

```dart
final pages = _pages;
if (pages == null) {
  _showMessage('페이지를 계산하고 있습니다.');
  return;
}
// TextField decoration: labelText: '페이지', hintText: '1~${pages.length}'
final page = int.tryParse(input.trim());
if (page == null || page < 1 || page > pages.length) {
  _showMessage('1~${pages.length} 사이 페이지를 입력해 주세요.');
  return;
}
_jumpToOffset(pages[page - 1].start);
```

- [ ] **Step 6: Show bookmark pages and add the native exit action**

Import `package:flutter/services.dart`, add this drawer item, and keep native Android handling:

```dart
_drawerItem(Icons.exit_to_app, '앱 종료', () => SystemNavigator.pop()),
```

Use the existing page map for bookmark feedback and list subtitles:

```dart
int? _pageNumberForOffset(int offset) {
  final pages = _pages;
  return pages == null || pages.isEmpty ? null : pageForOffset(pages, offset) + 1;
}
```

At the start of `_addBookmark`, return with `페이지를 계산하고 있습니다.` when `_pageNumberForOffset(_offset)` is null. Otherwise show `$page페이지에 북마크를 저장했습니다.`. `_showBookmarks` also returns with the same calculation message when `_pages` is null; after that guard its subtitle uses `${_pageNumberForOffset(bookmark.offset)}페이지` instead of percent.

- [ ] **Step 7: Run Task 1 tests and commit**

Run: `dart format lib/reader_screen.dart test/reader_screen_test.dart`

Run: `flutter test test/reader_screen_test.dart test/text_paginator_test.dart --reporter expanded`

Expected: all tests pass.

Commit:

```bash
git add lib/reader_screen.dart test/reader_screen_test.dart
git commit -m "fix: make reader navigation page based"
```

---

### Task 2: Step Buttons and Visual Color Templates

**Files:**
- Modify: `lib/reader_screen.dart:660-1035`
- Modify: `test/reader_screen_test.dart`
- Modify: `test/qa_ui_test.dart`

**Interfaces:**
- Consumes: `ReaderSettings.copyWith(...)`, `_colorTemplates`, `_showSettings()`
- Produces: `_SettingStepper`, normalized settings draft, keyed visual template buttons

- [ ] **Step 1: Add failing tests for exact settings steps and normalization**

Add to `test/reader_screen_test.dart`:

```dart
testWidgets('표시 설정은 단계 버튼으로 값과 과거 소수값을 조절한다', (tester) async {
  final store = _MemoryStore()
    ..updateSettings(const ReaderSettings(
      fontSize: 20.4,
      lineHeight: 1.66,
      horizontalPadding: 20.4,
    ));
  await _pumpReader(tester, store, '본문');
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.tap(find.text('표시 설정'));
  await tester.pumpAndSettle();

  await tester.ensureVisible(find.byKey(const Key('font-size-increase')));
  await tester.tap(find.byKey(const Key('font-size-increase')));
  await tester.tap(find.byKey(const Key('line-height-decrease')));
  await tester.tap(find.byKey(const Key('horizontal-padding-increase')));
  await tester.ensureVisible(find.text('적용'));
  await tester.tap(find.text('적용'));
  await tester.pumpAndSettle();

  expect(store.data.settings.fontSize, 21);
  expect(store.data.settings.lineHeight, 1.6);
  expect(store.data.settings.horizontalPadding, 21);
});

testWidgets('단계 버튼은 최솟값과 최댓값을 넘지 않는다', (tester) async {
  final store = _MemoryStore()
    ..updateSettings(const ReaderSettings(
      fontSize: 36,
      lineHeight: 1.2,
      horizontalPadding: 40,
    ));
  await _pumpReader(tester, store, '본문');
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.tap(find.text('표시 설정'));
  await tester.pumpAndSettle();

  expect(tester.widget<IconButton>(find.byKey(const Key('font-size-increase'))).onPressed, isNull);
  expect(tester.widget<IconButton>(find.byKey(const Key('line-height-decrease'))).onPressed, isNull);
  expect(tester.widget<IconButton>(find.byKey(const Key('horizontal-padding-increase'))).onPressed, isNull);
});
```

- [ ] **Step 2: Add a failing test for visible color swatches**

Replace text-template expectations in `test/qa_ui_test.dart` with:

```dart
for (final name in ['기본 연두', '종이', '밤', '세피아']) {
  expect(find.byKey(Key('color-template-$name')), findsOneWidget);
  expect(find.byTooltip(name), findsOneWidget);
  expect(find.text(name), findsNothing);
}
final button = tester.widget<IconButton>(
  find.byKey(const Key('color-template-기본 연두')),
);
final swatch = button.icon! as Container;
expect((swatch.decoration! as BoxDecoration).color, const Color(0xffc4ecbb));
```

- [ ] **Step 3: Run the settings tests and verify they fail**

Run: `flutter test test/reader_screen_test.dart test/qa_ui_test.dart --reporter expanded`

Expected: FAIL because slider controls and text template buttons are still present.

- [ ] **Step 4: Normalize the draft and replace sliders with steppers**

At the start of `_showSettings`, normalize old persisted values:

```dart
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
```

Replace `_SettingSlider` with `_SettingStepper`:

```dart
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
  Widget build(BuildContext context) => Row(
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
        child: Text(value.toStringAsFixed(fractionDigits), textAlign: TextAlign.center),
      ),
      IconButton(
        key: Key('$settingKey-increase'),
        tooltip: '$label 늘리기',
        onPressed: value >= max ? null : () => onChanged(_next(step)),
        icon: const Icon(Icons.add),
      ),
    ],
  );

  double _next(double delta) => double.parse(
    (value + delta).clamp(min, max).toStringAsFixed(fractionDigits),
  );
}
```

Instantiate it three times with `(step: 1, fractionDigits: 0)` for font/padding and `(step: .1, fractionDigits: 1)` for line height.

- [ ] **Step 5: Replace template labels with keyed color swatches**

Use the existing template list and no new widget class:

```dart
IconButton(
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
    child: Text('가', style: TextStyle(color: Color(template.foreground.value))),
  ),
),
```

- [ ] **Step 6: Run Task 2 tests and commit**

Run: `dart format lib/reader_screen.dart test/reader_screen_test.dart test/qa_ui_test.dart`

Run: `flutter test test/reader_screen_test.dart test/qa_ui_test.dart --reporter expanded`

Expected: all tests pass.

Commit:

```bash
git add lib/reader_screen.dart test/reader_screen_test.dart test/qa_ui_test.dart
git commit -m "feat: simplify reader display controls"
```

---

## Final Verification

- [ ] Run `dart format --output=none --set-exit-if-changed lib test`; expect zero changed files.
- [ ] Run `flutter analyze`; expect `No issues found!`.
- [ ] Run `flutter test --reporter expanded`; expect the full suite to pass.
- [ ] Run `flutter build apk --release`; expect `app-release.apk` to build.
- [ ] Record APK size and SHA-256 with `Get-FileHash -Algorithm SHA256 build/app/outputs/flutter-apk/app-release.apk`.
- [ ] Confirm `git status --short` is empty and `master` is the active branch.
