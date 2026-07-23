# Project Hardening Implementation Plan

> **For Codex:** Execute each task in order. For every behavior change, add or change a test first, observe the intended failure, implement the smallest fix, and rerun the focused test before the full suite.

**Goal:** Remove the reported data-loss, Android permission, performance, architecture, accessibility, release, and verification risks while preserving the reader's current behavior.

**Architecture:** Keep `AppStore` as the persisted state owner and introduce one built-in `ChangeNotifier` `ReaderController` for reader session state and side effects. `ReaderScreen`, `ReaderView`, and `ReaderSettingsSheet` become thin UI layers. Existing pure text and pagination modules remain independent.

**Tech Stack:** Flutter/Dart, `ChangeNotifier`, `file_selector`, Android Gradle/Kotlin, Flutter test, GitHub Actions.

---

## Task 1: Make persisted state versioned, validated, and crash-safe

**Files:**
- Modify: `lib/models.dart`
- Modify: `lib/app_store.dart`
- Test: `test/models_test.dart`
- Test: `test/app_store_test.dart`

1. Add failing tests for schema migration, invalid numeric settings, duplicate corrupted backups, overlapping saves, immutable save snapshots, and propagated write failures.
2. Add a schema version and tolerant migrations in `AppData.fromJson`.
3. Clamp settings and document offsets/alignment while parsing.
4. Encapsulate mutable store state and expose explicit read/update operations.
5. Serialize saves, write to a sibling temporary file with flush, and atomically replace the state file while retaining the last good file until replacement succeeds.
6. Give corrupted backups unique UTC timestamp names and retain recovery diagnostics.
7. Run focused tests, formatting, analysis, and the full suite.

## Task 2: Detect file replacement and bound decoding memory

**Files:**
- Modify: `lib/models.dart`
- Modify: `lib/text_document.dart`
- Modify: `lib/reader_screen.dart`
- Modify: `lib/page_cache.dart`
- Test: `test/text_document_test.dart`
- Test: `test/reader_screen_test.dart`
- Test: `test/page_cache_test.dart`

1. Add failing tests for pre-read size rejection, UTF-8 streaming decode, changed-file state invalidation, and cache invalidation by file fingerprint/schema.
2. Store document size and modification time as a fingerprint.
3. Stat the file before reading; reject unsupported sizes before allocation.
4. Stream UTF-8 decoding and keep bounded whole-file decoding only for UTF-16/CP949.
5. Remove the duplicate test-only encoding detection API and test the production decode path.
6. Invalidate encoding, progress, bookmarks, and page cache when the fingerprint changes.
7. Surface cache read/write failures as diagnostics while treating cache absence as normal.
8. Run focused and full verification.

## Task 3: Replace broad Android storage access with the system picker

**Files:**
- Modify: `lib/file_browser_screen.dart`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `pubspec.yaml`
- Test: `test/file_browser_screen_test.dart`

1. Add failing widget/unit tests for directory selection, stale async load suppression, and one broken directory entry not aborting the list.
2. Replace hardcoded shared-storage roots and permission prompts with `getDirectoryPath()`.
3. Add request generations so stale results are ignored.
4. Isolate per-entry `stat` failures.
5. Remove `permission_handler` and all broad/legacy storage permissions.
6. Run dependency resolution, focused tests, manifest checks, analysis, and the full suite.

## Task 4: Split reader state and side effects from the view

**Files:**
- Create: `lib/reader_controller.dart`
- Create: `lib/reader_settings_sheet.dart`
- Modify: `lib/reader_screen.dart`
- Modify: `lib/app.dart`
- Create: `test/reader_controller_test.dart`
- Modify: `test/reader_screen_test.dart`

1. Characterize current navigation, settings, search, auto-turn, lifecycle, and persistence behaviors with tests.
2. Move mutable reader session fields and commands into `ReaderController extends ChangeNotifier`.
3. Make delayed progress/settings saves controller-owned and awaitable through `flush()`.
4. Route lifecycle and explicit exit through controller flush; remove unawaited persistence.
5. Extract the settings sheet as a focused widget driven by controller commands.
6. Make `ReaderView` subscribe to narrow controller values and remove state mutation during build.
7. Replace production constructors containing test-only callbacks with controller/service injection in tests.
8. Keep the controller API no larger than the UI needs.
9. Run controller tests, reader widget tests, analysis, and the full suite.

## Task 5: Correct chunking, selection, and precise scroll restoration

**Files:**
- Modify: `lib/text_document.dart`
- Modify: `lib/reader_controller.dart`
- Modify: `lib/reader_screen.dart`
- Modify: `lib/models.dart`
- Test: `test/text_document_test.dart`
- Test: `test/reader_controller_test.dart`
- Modify: `test/reader_screen_test.dart`

1. Add a real text fixture larger than 64 KiB with no newline and tests for surrogate/combining-sequence boundaries.
2. Split at visual line or grapheme-safe boundaries without inserting visible line breaks.
3. Put scroll chunks under a common selection container.
4. Record and restore character offset plus within-chunk alignment.
5. Add widget tests that scroll within a large chunk, persist, rebuild, and verify the restored viewport.
6. Run focused and full verification.

## Task 6: Make pagination and search incremental

**Files:**
- Modify: `lib/text_paginator.dart`
- Modify: `lib/reader_controller.dart`
- Modify: `lib/reader_screen.dart`
- Test: `test/text_paginator_test.dart`
- Test: `test/reader_controller_test.dart`
- Modify: `test/reader_screen_test.dart`

1. Add tests that scroll mode initially computes only a bounded prefix, distant navigation extends on demand, and obsolete pagination generations cannot publish.
2. Add a cancellable pagination budget and publish progress through a narrow listenable.
3. Compute current-position pages first; finish totals only when the UI requests them.
4. Move search into the controller with next/previous traversal and active-result highlighting.
5. Ensure progress updates do not rebuild the whole reader.
6. Replace one-frame large-file tests with full load/navigation/search/teardown paths.
7. Run performance-sensitive focused tests and the full suite.

## Task 7: Harden fonts and accessibility

**Files:**
- Modify: `lib/font_library.dart`
- Modify: `lib/reader_settings_sheet.dart`
- Modify: `lib/page_turn_view.dart`
- Modify: `lib/reader_controller.dart`
- Test: `test/font_library_test.dart`
- Test: `test/page_turn_view_test.dart`
- Modify: `test/reader_screen_test.dart`

1. Add failing tests for oversized/corrupt fonts, loaded-font deletion semantics, reduced motion, and low-contrast recovery.
2. Validate font size and SFNT signatures before copying/loading.
3. Track session-loaded fonts and explain deletion/restart behavior without presenting stale choices.
4. Disable page animation and automatic motion when the platform requests reduced motion.
5. Add a one-action reset to accessible default colors.
6. Run focused accessibility/font tests and the full suite.

## Task 8: Fix local release signing and Android build warnings

**Files:**
- Modify: `.gitignore`
- Modify: `android/app/build.gradle.kts`
- Modify: `android/settings.gradle.kts`
- Modify: `android/gradle.properties`
- Create: `tool/create_local_keystore.ps1`
- Modify: `README.md`
- Modify: `pubspec.yaml`

1. Document and script generation of an ignored local keystore and `key.properties`.
2. Make release signing read local properties and fail clearly when absent; do not fall back to the debug key.
3. Remove obsolete Kotlin opt-out flags and migrate to Flutter's built-in Kotlin Gradle configuration.
4. Update direct dependencies that emit future-incompatibility warnings and remove `cupertino_icons`.
5. Generate an ephemeral local key, build a release APK, inspect signing, and delete only generated test secrets.
6. Run analysis, tests, and release build again.

## Task 9: Add CI and reduce repository noise

**Files:**
- Create: `.github/workflows/ci.yml`
- Create: `lib/strings.dart`
- Modify: user-facing Dart files
- Modify: `README.md`
- Delete: completed files under `docs/superpowers/plans/`

1. Centralize Korean user strings without adding a localization dependency and document the Korean-only scope.
2. Add CI for formatting, analysis, tests, ephemeral release signing, and release APK build.
3. Delete completed historical implementation plans while retaining design records and the active hardening plan until completion.
4. Validate workflow YAML, references, and ignored secret paths.
5. Run repository-wide formatting, analysis, tests, and release build.

## Task 10: Final audit and close-out

**Files:**
- Review: all changed files
- Modify: `README.md`
- Delete: `docs/superpowers/plans/2026-07-23-project-hardening.md`

1. Re-audit every original finding against code and tests, including storage, races, Reader ownership, large files, permissions, signing, accessibility, and CI.
2. Search for `unawaited`, swallowed catches, state mutations in `build`, broad Android permissions, debug signing, stale dependencies, TODOs, and test-only production seams.
3. Run `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, `flutter test`, and signed `flutter build apk --release`.
4. Inspect the final APK size and signature.
5. Update README only with verified behavior and limitations.
6. Remove this completed execution plan, run `git diff --check`, inspect status/diff, and commit the verified result.
