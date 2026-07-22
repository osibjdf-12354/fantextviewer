# Page Indicator Format Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove `페이지` from the bottom indicator and bookmark page labels, while letting users persistently choose between `3` and `3/120` bottom formats.

**Architecture:** Add one backward-compatible `showTotalPages` boolean to the existing `ReaderSettings` JSON model. Reuse the current display-settings draft/apply flow and existing page-number calculations; only the final strings change.

**Tech Stack:** Flutter, Dart, `flutter_test`, existing `AppStore` JSON persistence

## Global Constraints

- `showTotalPages` defaults to `false`; missing saved values restore as `false`.
- Bottom indicator formats are numeric-only: `3` or `3/120`.
- During pagination, `current/total` uses the existing estimated total and updates when the exact total is ready.
- Drawer text remains `현재 3페이지`.
- Bookmark save feedback and bookmark-list page labels contain no `페이지` suffix.
- Page-jump, pagination-status, and error wording remain unchanged.
- Add no dependency, page-calculation change, or formatter abstraction.

---

### Task 1: Persist the page-indicator preference

**Files:**
- Modify: `lib/models.dart:52-125`
- Test: `test/app_store_test.dart:59-76`

**Interfaces:**
- Consumes: existing `ReaderSettings` constructor, `copyWith`, `toJson`, and `fromJson`.
- Produces: `ReaderSettings.showTotalPages` as a non-nullable `bool`, defaulting to `false`.

- [ ] **Step 1: Write the failing model test**

Add this test near the existing font-setting persistence tests in `test/app_store_test.dart`:

```dart
test('persists page indicator format and defaults to current page', () {
  const enabled = ReaderSettings(showTotalPages: true);

  expect(enabled.toJson()['showTotalPages'], true);
  expect(ReaderSettings.fromJson(enabled.toJson()).showTotalPages, isTrue);
  expect(ReaderSettings.fromJson(const {}).showTotalPages, isFalse);
  expect(enabled.copyWith(fontSize: 24).showTotalPages, isTrue);
});
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
flutter test test/app_store_test.dart --plain-name "persists page indicator format and defaults to current page"
```

Expected: compilation fails because `ReaderSettings` has no `showTotalPages` named parameter or getter.

- [ ] **Step 3: Add the minimal model field and JSON mapping**

Update `ReaderSettings` in `lib/models.dart` as follows:

```dart
const ReaderSettings({
  this.mode = ReadingMode.scroll,
  this.background = const RgbColor(196, 236, 187),
  this.foreground = const RgbColor(32, 48, 32),
  this.fontFileName,
  this.fontSize = 20,
  this.lineHeight = 1.65,
  this.horizontalPadding = 20,
  this.keepAwake = false,
  this.showTotalPages = false,
});

final bool showTotalPages;
```

Thread it through `copyWith` without touching the nullable-font sentinel:

```dart
ReaderSettings copyWith({
  ReadingMode? mode,
  RgbColor? background,
  RgbColor? foreground,
  Object? fontFileName = _unchangedFontFileName,
  double? fontSize,
  double? lineHeight,
  double? horizontalPadding,
  bool? keepAwake,
  bool? showTotalPages,
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
    showTotalPages: showTotalPages ?? this.showTotalPages,
  );
}
```

Add the key to `toJson` and restore it in `fromJson`:

```dart
'showTotalPages': showTotalPages,
```

```dart
showTotalPages: json['showTotalPages'] as bool? ?? false,
```

- [ ] **Step 4: Format and verify GREEN**

Run:

```bash
dart format lib/models.dart test/app_store_test.dart
flutter test test/app_store_test.dart --plain-name "persists page indicator format and defaults to current page"
```

Expected: formatting succeeds and the focused test passes.

- [ ] **Step 5: Run the complete model/store test file**

Run:

```bash
flutter test test/app_store_test.dart
```

Expected: all tests in `test/app_store_test.dart` pass.

- [ ] **Step 6: Commit the persistence slice**

```bash
git add lib/models.dart test/app_store_test.dart
git commit -m "feat: persist page indicator format"
```

---

### Task 2: Render and configure numeric page labels

**Files:**
- Modify: `lib/reader_screen.dart:519-537,909-930,1011-1035,1091-1113`
- Test: `test/reader_screen_test.dart:259-273,1273-1290,1292-1320`

**Interfaces:**
- Consumes: `ReaderSettings.showTotalPages`, `_currentPageNumber`, `_displayTotalPages`, `_showSettings`, and `_applySettings`.
- Produces: bottom `Text` keyed `page-indicator`; display-setting chips keyed `page-display-current` and `page-display-current-total`; bookmark subtitle keyed `bookmark-page-<offset>`.

- [ ] **Step 1: Replace the existing indicator test with the failing numeric-only expectation**

Update the test at `test/reader_screen_test.dart:259`:

```dart
testWidgets('하단은 숫자만 표시하고 햄버거 메뉴는 페이지 문구를 유지한다', (tester) async {
  final store = _MemoryStore()
    ..updateSettings(const ReaderSettings(mode: ReadingMode.page));
  await _pumpReader(tester, store, _longText);
  await tester.pumpAndSettle();

  final indicator = tester.widget<Text>(
    find.byKey(const Key('page-indicator')),
  );
  expect(indicator.data, matches(RegExp(r'^\d+$')));
  expect(indicator.data, isNot(contains('페이지')));

  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();

  expect(find.textContaining(RegExp(r'^현재 \d+페이지$')), findsOneWidget);
});
```

- [ ] **Step 2: Add the failing settings-choice test**

Add near the display-settings tests:

```dart
testWidgets('표시 설정에서 현재와 전체 페이지 표시를 선택하고 저장한다', (tester) async {
  final store = _MemoryStore()
    ..updateSettings(const ReaderSettings(mode: ReadingMode.page));
  await _pumpReader(tester, store, _longText);
  await tester.pumpAndSettle();

  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.tap(find.text('표시 설정'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('page-display-current-total')));
  await tester.tap(find.byKey(const Key('page-display-current-total')));
  await tester.ensureVisible(find.text('적용'));
  await tester.tap(find.text('적용'));
  await tester.pumpAndSettle();

  expect(store.data.settings.showTotalPages, isTrue);
  final indicator = tester.widget<Text>(
    find.byKey(const Key('page-indicator')),
  );
  expect(indicator.data, matches(RegExp(r'^\d+/\d+$')));
});
```

- [ ] **Step 3: Change the bookmark test to require numeric-only labels**

Update the existing bookmark test:

```dart
testWidgets('북마크를 숫자 페이지로 안내하고 표시한다', (tester) async {
  final store = _MemoryStore();
  await _pumpReader(tester, store, _longText);
  await tester.pumpAndSettle();

  await tester.tap(find.byIcon(Icons.bookmark_add_outlined));
  await tester.pump();
  expect(
    find.textContaining(RegExp(r'^\d+에 북마크를 저장했습니다\.$')),
    findsOneWidget,
  );

  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
  await tester.tap(find.text('북마크'));
  await tester.pumpAndSettle();
  final bookmarkPage = tester.widget<Text>(
    find.byKey(const Key('bookmark-page-0')),
  );
  expect(bookmarkPage.data, matches(RegExp(r'^\d+$')));
});
```

- [ ] **Step 4: Run the three focused widget tests and verify RED**

Run:

```bash
flutter test test/reader_screen_test.dart --plain-name "하단은 숫자만 표시하고 햄버거 메뉴는 페이지 문구를 유지한다"
flutter test test/reader_screen_test.dart --plain-name "표시 설정에서 현재와 전체 페이지 표시를 선택하고 저장한다"
flutter test test/reader_screen_test.dart --plain-name "북마크를 숫자 페이지로 안내하고 표시한다"
```

Expected: the first fails because `page-indicator` does not exist, the second fails because `page-display-current-total` does not exist, and the third fails because the old bookmark strings include `페이지`.

- [ ] **Step 5: Render the selected bottom format**

Replace `_buildPageIndicator`'s `Text` in `lib/reader_screen.dart` with:

```dart
Text(
  _settings.showTotalPages
      ? '$_currentPageNumber/$_displayTotalPages'
      : '$_currentPageNumber',
  key: const Key('page-indicator'),
  style: TextStyle(color: Color(_settings.foreground.value)),
),
```

- [ ] **Step 6: Add the two display-setting choices**

Insert this block after the reading-mode chips in `_showSettings`:

```dart
const SizedBox(height: 12),
const Text('페이지 표시'),
Wrap(
  spacing: 8,
  children: [
    ChoiceChip(
      key: const Key('page-display-current'),
      label: const Text('현재 페이지만'),
      selected: !draft.showTotalPages,
      onSelected: (_) => setSheetState(() {
        draft = draft.copyWith(showTotalPages: false);
      }),
    ),
    ChoiceChip(
      key: const Key('page-display-current-total'),
      label: const Text('현재/전체 페이지'),
      selected: draft.showTotalPages,
      onSelected: (_) => setSheetState(() {
        draft = draft.copyWith(showTotalPages: true);
      }),
    ),
  ],
),
```

Keep the existing `적용` button and `_applySettings(draft)` call unchanged.

- [ ] **Step 7: Remove `페이지` only from bookmark surfaces**

Change the bookmark save message:

```dart
_showMessage('$page에 북마크를 저장했습니다.');
```

Change the bookmark-list subtitle:

```dart
subtitle: Text(
  '${_pageNumberForOffset(bookmark.offset)}',
  key: Key('bookmark-page-${bookmark.offset}'),
),
```

Do not change drawer, page-jump, pagination-status, bookmark-delete, or validation text.

- [ ] **Step 8: Format and verify the focused widget tests GREEN**

Run:

```bash
dart format lib/reader_screen.dart test/reader_screen_test.dart
flutter test test/reader_screen_test.dart --plain-name "하단은 숫자만 표시하고 햄버거 메뉴는 페이지 문구를 유지한다"
flutter test test/reader_screen_test.dart --plain-name "표시 설정에서 현재와 전체 페이지 표시를 선택하고 저장한다"
flutter test test/reader_screen_test.dart --plain-name "북마크를 숫자 페이지로 안내하고 표시한다"
```

Expected: all three focused widget tests pass.

- [ ] **Step 9: Run the reader regression file**

Run:

```bash
flutter test test/reader_screen_test.dart
```

Expected: all reader tests pass with only the intentionally changed page-label assertions.

- [ ] **Step 10: Run repository-wide verification**

Run:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --reporter expanded --no-pub
flutter build apk --release --no-pub
git diff --check
```

Expected: no formatting changes, no analyzer issues, all tests pass, the release APK builds, and `git diff --check` reports no whitespace errors.

- [ ] **Step 11: Commit the UI slice**

```bash
git add lib/reader_screen.dart test/reader_screen_test.dart
git commit -m "feat: configure page indicator format"
```
