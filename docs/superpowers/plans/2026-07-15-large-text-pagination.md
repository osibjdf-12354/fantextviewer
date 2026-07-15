# Large TXT Pagination Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make large TXT page calculation responsive and reusable without changing exact screen-page semantics.

**Architecture:** Keep the existing `TextPainter` paginator, replace its fixed probe with a previous-page-sized adaptive probe, publish incremental page batches, and persist only completed page starts in a validated bounded cache. `ReaderView` consumes progressive batches in page mode and swaps to cached or completed maps through its existing generation guard.

**Tech Stack:** Dart 3.12, Flutter 3.44, `dart:io`, `dart:convert`, `path_provider`, `flutter_test`, GitHub CLI

## Global Constraints

- Existing saved offsets, bookmarks, Korean encodings, scroll mode, and exact screen-page numbering remain compatible.
- Cache failures must never prevent opening or reading a file.
- No new dependency is added.
- Release version becomes `1.1.0+2` and tag `v1.1.0`.

---

### Task 1: Adaptive progressive paginator

**Files:**
- Modify: `lib/text_paginator.dart`
- Modify: `test/text_paginator_test.dart`

**Interfaces:**
- Consumes: existing `paginateText`, `TextPage`, `TextPainter`
- Produces: `PaginationBatchCallback`, `onBatch`, and adaptive probe calculation

- [ ] Add a test that calls `paginateText(..., onBatch: ...)`, requires multiple non-empty delta batches, and verifies their concatenation equals the returned page list.
- [ ] Run `flutter test test/text_paginator_test.dart`; expect a compile failure because `onBatch` does not exist.
- [ ] Add a test-visible `TextLayoutCallback` parameter and assert a long document lays out substantially less than 4,096 characters per page after its first probe.
- [ ] Run the focused test; expect a compile failure because the callback does not exist.
- [ ] Implement adaptive probing, eight-page batch emission, cancellation checks, and zero-duration yielding. Preserve the existing page-boundary calculation.
- [ ] Run `flutter test test/text_paginator_test.dart`; expect all paginator tests to pass.

### Task 2: Validated bounded page-index cache

**Files:**
- Create: `lib/page_index_cache.dart`
- Create: `test/page_index_cache_test.dart`

**Interfaces:**
- Produces: `PageIndexCache.load(signature:, textLength:)` and `PageIndexCache.save(signature:, textLength:, pages:)`
- Persists: JSON `{signature, textLength, starts}` under an injected or application-support directory

- [ ] Add round-trip and stale-signature tests using a temporary directory.
- [ ] Run `flutter test test/page_index_cache_test.dart`; expect a compile failure because `PageIndexCache` does not exist.
- [ ] Implement stable cache filenames, strict offset validation, atomic replacement, non-fatal errors, and eight-record retention.
- [ ] Add malformed-offset and retention tests.
- [ ] Run `flutter test test/page_index_cache_test.dart`; expect all cache tests to pass.

### Task 3: Progressive reader integration

**Files:**
- Modify: `lib/reader_screen.dart`
- Modify: `test/reader_screen_test.dart`

**Interfaces:**
- Consumes: `PaginationBatchCallback`, `PageIndexCache`, `FileStat.modified`, existing pagination generation
- Produces: progressive `_pages`, completed-map cache load/save, `_paginationComplete`

- [ ] Add a widget test that injects a batch-emitting paginator and verifies page text appears before the returned pagination future completes.
- [ ] Run the focused reader test; expect failure because progressive paginator injection is absent.
- [ ] Pass file modification time into `ReaderView`, build the complete cache signature, load a valid cache before calculating, and save only complete uncancelled results.
- [ ] Append batches only when the current generation is active. Initialize `PageController` once the progressive map covers the saved offset; keep scroll mode on chunks until completion.
- [ ] Run `flutter test test/reader_screen_test.dart test/page_index_cache_test.dart test/text_paginator_test.dart`; expect all focused tests to pass.

### Task 4: Release verification and publishing

**Files:**
- Modify: `pubspec.yaml`
- Build: `build/app/outputs/flutter-apk/app-release.apk`

- [ ] Set `version: 1.1.0+2`.
- [ ] Run `dart format --output=none --set-exit-if-changed lib test`; expect exit 0.
- [ ] Run `flutter analyze`; expect `No issues found!`.
- [ ] Run `flutter test --reporter expanded`; expect the entire suite to pass.
- [ ] Run `flutter build apk --release`; expect `app-release.apk`.
- [ ] Record APK size and SHA-256.
- [ ] Request code review against the pre-change SHA and resolve all Critical or Important findings.
- [ ] Commit the verified change on `master`, push to `origin/master`, create GitHub Release `v1.1.0`, and attach the APK as `fantextviewer-v1.1.0.apk`.
- [ ] Verify the remote commit, public release URL, and downloadable APK asset.

