# 판갤텍뷰 잔여 문제 해결 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 확인된 파일 가져오기·상태 무결성·복구·페이지 오류 문제를 해결하고 호환성 식별자를 제외한 제품 명칭을 `fantextviewer`/`판갤텍뷰`로 변경한다.

**Architecture:** 현재 경로 기반 리더 구조를 유지한다. Android 시스템 선택 파일은 네이티브에서 앱 내부로 스트리밍 가져오고, 상태 변경은 디코딩 성공 뒤 한 번에 적용하며, 오류 복구는 기존 `AppStore`와 리더 코디네이터에 최소 상태만 추가한다.

**Tech Stack:** Flutter 3.44.6+, Dart 3.12.2+, Android API 24+, Kotlin, MethodChannel, `ChangeNotifier`, 기존 `file_selector`와 `path_provider`.

## Global Constraints

- Android `applicationId=com.songs.geulbom`은 기존 설치 업데이트를 위해 유지한다.
- 기존 사용자의 `key.properties`와 그 파일이 참조하는 서명 키를 변경하지 않는다.
- 폴더 탐색은 내부 공유 저장소만 지원하고 SD·USB·클라우드는 단일 파일 가져오기로 지원한다.
- Android CP949는 32MiB, UTF-8·스트리밍 UTF-16은 64MiB로 제한한다.
- 새 상태관리·파일 저장 라이브러리는 추가하지 않는다.
- 기존 `README.md`의 작업 트리 변경을 보존하면서 내용을 현재 동작에 맞게 갱신한다.

---

### Task 1: 문서 지문·경로 이동·손상 백업 수명주기

**Files:**
- Modify: `lib/models.dart`
- Modify: `lib/app_store.dart`
- Test: `test/app_store_test.dart`

**Interfaces:**
- Produces: `DocumentState.contentFingerprint`, `AppStore.fileChanged(...)`, `AppStore.moveDocument(...)`, `AppStore.completeRecovery()`.
- Consumes: 기존 `AppStore.save()`, `AppData` 스키마 마이그레이션.

- [ ] **Step 1: 내용 지문과 같은 경로 이동의 실패 테스트 작성**

```dart
test('content fingerprint invalidates state even when metadata matches', () {
  final store = AppStore(file);
  // 기존 지문과 진행 위치를 저장한 뒤 같은 크기·수정일, 다른 SHA-256을 전달한다.
  expect(store.fileChanged(path, fileSize: 4, modified: stamp, contentFingerprint: 'b'), isTrue);
});

test('moving a document preserves its state under the durable path', () {
  store.moveDocument(cachePath, importedPath);
  expect(store.document(importedPath).offset, 42);
  expect(store.data.documents, isNot(contains(cachePath)));
});
```

- [ ] **Step 2: 테스트가 `contentFingerprint`와 새 메서드 부재로 실패하는지 확인**

Run: `flutter test test/app_store_test.dart`
Expected: 컴파일 또는 기대값 실패.

- [ ] **Step 3: 스키마 3과 최소 상태 API 구현**

```dart
bool fileChanged(
  String path, {
  required int fileSize,
  required DateTime modified,
  required String contentFingerprint,
}) {
  final state = document(path);
  if (state.contentFingerprint != null) {
    return state.contentFingerprint != contentFingerprint;
  }
  return metadataChanged(state, fileSize, modified);
}
```

`updateFileFingerprint`는 성공한 SHA-256을 함께 저장하고, 변경 시 기존 진행 위치·북마크·인코딩을 초기화한다. `moveDocument`는 `DocumentState.path`까지 새 경로로 복사한 뒤 이전 키를 제거한다.

- [ ] **Step 4: 재시작 시 가장 최근 손상 백업을 찾는 실패 테스트 작성**

```dart
test('a later store instance rediscovers the latest broken backup', () async {
  await AppStore(file).load();
  final restarted = AppStore(file);
  await restarted.load();
  expect(restarted.recoveryFile, isNotNull);
});
```

- [ ] **Step 5: `load()`의 백업 검색과 `completeRecovery()` 구현 후 테스트 통과 확인**

Run: `flutter test test/app_store_test.dart`
Expected: PASS.

- [ ] **Step 6: 커밋**

```powershell
git add lib/models.dart lib/app_store.dart test/app_store_test.dart
git commit -m "fix: preserve document state integrity"
```

### Task 2: 시스템 파일의 영구 가져오기와 레거시 캐시 승격

**Files:**
- Create: `lib/imported_text_file.dart`
- Modify: `lib/file_browser.dart`
- Modify: `lib/main.dart`
- Modify: `android/app/src/main/kotlin/com/songs/geulbom/MainActivity.kt`
- Test: `test/imported_text_file_test.dart`
- Modify: `android/app/src/androidTest/kotlin/com/songs/geulbom/FolderPickerTest.kt`

**Interfaces:**
- Produces: `pickTextFile()`의 Android 영구 경로, `promoteTemporaryTextFile(path, ...)`.
- Consumes: Task 1의 `AppStore.moveDocument`.

- [ ] **Step 1: 캐시 파일 승격 실패 테스트 작성**

```dart
test('promotes a temporary picker file into imported_texts', () async {
  final result = await promoteTemporaryTextFile(
    source.path,
    temporaryDirectory: cache,
    supportDirectory: support,
  );
  expect(result, startsWith(imported.path));
  expect(await File(result).readAsString(), '본문');
});
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `flutter test test/imported_text_file_test.dart`
Expected: 함수 또는 파일 부재로 FAIL.

- [ ] **Step 3: 임시 경로만 원자적으로 승격하는 Dart 헬퍼 구현**

임시 디렉터리 밖의 경로는 그대로 반환한다. 임시 파일은 SHA-256 경로 키와 원래 파일명 아래의 `.tmp`로 복사한 뒤 rename한다.

- [ ] **Step 4: Android 네이티브 선택기의 실패 계측 조건 추가**

시스템 선택기로 파일을 연 뒤 `state.json`의 문서 경로가 `/files/imported_texts/`를 포함하고 `/cache/`를 포함하지 않는다고 검증한다.

- [ ] **Step 5: `ACTION_OPEN_DOCUMENT` 스트리밍 가져오기 구현**

`MainActivity`의 기존 MethodChannel에 `pickTextFile`을 추가한다. URI 문자열의 UUID 디렉터리, 정제된 표시 파일명, 64MiB 복사 상한, 임시 파일 정리, 내부 파일시스템 rename을 사용하고 Dart에는 경로만 반환한다.

- [ ] **Step 6: 홈에서 레거시 캐시 경로를 승격하고 상태 키 이동**

`_openReader`는 파일 존재 확인 전에 `promoteTemporaryTextFile`을 호출하고 경로가 바뀌면 `moveDocument`와 `save`를 실행한다.

- [ ] **Step 7: 단위 테스트 통과 확인**

Run: `flutter test test/imported_text_file_test.dart test/app_store_test.dart test/file_browser_test.dart`
Expected: PASS.

- [ ] **Step 8: 커밋**

```powershell
git add lib/imported_text_file.dart lib/file_browser.dart lib/main.dart test/imported_text_file_test.dart android/app/src/main/kotlin/com/songs/geulbom/MainActivity.kt android/app/src/androidTest/kotlin/com/songs/geulbom/FolderPickerTest.kt
git commit -m "fix: import selected text files durably"
```

### Task 3: 문서 로드 트랜잭션과 저장 실패 처리

**Files:**
- Modify: `lib/reader_screen.dart`
- Modify: `lib/strings.dart`
- Test: `test/reader_screen_test.dart`

**Interfaces:**
- Consumes: Task 1의 `fileChanged`와 내용 지문 저장.
- Produces: 디코딩 성공 뒤 상태 반영, 실패한 수동 인코딩 비영속화.

- [ ] **Step 1: 저장 실패가 본문 표시를 막지 않는 실패 테스트 작성**

실제 임시 TXT와 `save()`가 실패하는 `AppStore`를 `ReaderScreen`에 전달하고 본문과 저장 실패 메시지가 함께 표시되는지 검증한다.

- [ ] **Step 2: 수동 인코딩 선택 전 저장소가 바뀌지 않는 실패 테스트 작성**

`ReaderView.test`의 `onEncodingChanged`를 기록하고 메뉴에서 UTF-16을 선택한 직후 기존 저장 인코딩이 유지되는지 검증한다.

- [ ] **Step 3: 실패 확인**

Run: `flutter test test/reader_screen_test.dart`
Expected: 본문 미표시 또는 저장 인코딩 변경으로 FAIL.

- [ ] **Step 4: `_load` 순서를 읽기 성공 후 커밋하도록 변경**

메타데이터 변경 시 저장 인코딩을 사용하지 않는다. 기존 내용 지문과 디코딩 결과가 다르고 저장 인코딩을 사용했다면 자동 감지로 한 번 다시 읽는다. 본문 `setState` 뒤 상태 저장 실패만 별도로 잡아 메시지를 표시한다.

- [ ] **Step 5: 뒤로가기·종료 저장 실패 테스트와 최소 수정**

`flush()` 실패 시 `_popAfterFlush`와 `_exitApp`은 pop을 호출하지 않고 메시지만 표시한다.

- [ ] **Step 6: 테스트 통과 확인 및 커밋**

Run: `flutter test test/reader_screen_test.dart test/reader_controller_test.dart`
Expected: PASS.

```powershell
git add lib/reader_screen.dart lib/strings.dart test/reader_screen_test.dart
git commit -m "fix: commit reader state after successful load"
```

### Task 4: CP949 상한, 복구 내보내기와 백업 정책

**Files:**
- Modify: `lib/text_document.dart`
- Modify: `lib/main.dart`
- Modify: `lib/app_store.dart`
- Modify: `lib/page_index_cache.dart`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `android/app/src/main/kotlin/com/songs/geulbom/MainActivity.kt`
- Test: `test/text_document_test.dart`
- Test: `test/app_store_test.dart`
- Test: `test/page_index_cache_test.dart`

**Interfaces:**
- Produces: Android `exportFile`, 재시작 가능한 복구 배너, 임시 페이지 캐시.

- [ ] **Step 1: 모든 플랫폼 CP949 상한 실패 테스트 작성**

플랫폼 분기 없이 `maxWholeFileBytes`보다 큰 CP949 파일이 `TextFileTooLargeException`을 던지는 순수 판정 함수를 테스트한다.

- [ ] **Step 2: 페이지 캐시 기본 디렉터리 선택 테스트 작성**

기본 디렉터리 공급자를 주입해 임시 디렉터리가 사용되는지 검증한다.

- [ ] **Step 3: 실패 확인 후 최소 구현**

CP949 조건의 `!Platform.isAndroid`를 제거하고, `PageIndexCache`의 기본 경로를 `getTemporaryDirectory()`로 바꾼다.

- [ ] **Step 4: 손상 백업 내보내기 구현**

Android `ACTION_CREATE_DOCUMENT` 결과 URI에 내부 백업 파일을 스트리밍 복사한다. 배너는 `recoveryFile != null`일 때 표시하고 내보내기·가져오기 동작을 제공한다. 성공한 상태 가져오기 뒤 `completeRecovery()`가 내부 백업을 삭제한다.

- [ ] **Step 5: Auto Backup 비활성화**

`<application android:allowBackup="false">`를 설정한다.

- [ ] **Step 6: 관련 테스트 통과 및 커밋**

Run: `flutter test test/text_document_test.dart test/app_store_test.dart test/page_index_cache_test.dart test/widget_test.dart`
Expected: PASS.

```powershell
git add lib/text_document.dart lib/main.dart lib/app_store.dart lib/page_index_cache.dart android/app/src/main/AndroidManifest.xml android/app/src/main/kotlin/com/songs/geulbom/MainActivity.kt test/text_document_test.dart test/app_store_test.dart test/page_index_cache_test.dart test/widget_test.dart
git commit -m "fix: harden local recovery and decode limits"
```

### Task 5: 페이지 실패 복구와 진행 중 제스처 유지

**Files:**
- Modify: `lib/reader_screen.dart`
- Modify: `lib/reader_pagination_coordinator.dart`
- Modify: `lib/page_turn_view.dart`
- Modify: `lib/strings.dart`
- Test: `test/reader_screen_test.dart`
- Test: `test/page_turn_view_test.dart`

**Interfaces:**
- Produces: 계산 실패 상태와 재시도, `itemCount` 증가 중 드래그 유지.

- [ ] **Step 1: `itemCount` 증가 중 드래그 실패 테스트 작성**

드래그를 시작하고 같은 index에서 itemCount만 늘린 뒤 드래그를 완료해 `onPageChanged`가 호출되는지 검증한다.

- [ ] **Step 2: 실패하는 paginator 재시도 테스트 작성**

첫 호출은 예외, 두 번째 호출은 페이지를 반환하는 paginator를 주입한다. 오류 문구와 재시도 버튼을 확인한 뒤 본문 페이지가 표시되는지 검증한다.

- [ ] **Step 3: 실패 확인**

Run: `flutter test test/page_turn_view_test.dart test/reader_screen_test.dart`
Expected: 제스처 취소와 비동기 paginator 오류로 FAIL.

- [ ] **Step 4: 최소 구현**

`PageTurnView.didUpdateWidget`에서 `itemCount`만 바뀐 경우 `_resetInteraction()`을 호출하지 않는다. 리더는 페이지 계산을 try/catch하고 실패 시 코디네이터를 초기화한 뒤 오류 UI를 표시한다.

- [ ] **Step 5: 테스트 통과 및 커밋**

Run: `flutter test test/page_turn_view_test.dart test/reader_screen_test.dart test/reader_pagination_coordinator_test.dart`
Expected: PASS.

```powershell
git add lib/reader_screen.dart lib/reader_pagination_coordinator.dart lib/page_turn_view.dart lib/strings.dart test/reader_screen_test.dart test/page_turn_view_test.dart
git commit -m "fix: recover failed pagination safely"
```

### Task 6: fantextviewer·판갤텍뷰 브랜딩과 README 현대화

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/main.dart`
- Modify: `lib/strings.dart`
- Modify: all current `package:geulbom/` imports under `test/`
- Modify: `lib/font_library.dart`
- Modify: `lib/page_index_cache.dart`
- Modify: `lib/text_document.dart`
- Modify: `android/app/build.gradle.kts`
- Move: `android/app/src/main/kotlin/com/songs/geulbom/MainActivity.kt` to `android/app/src/main/kotlin/com/songs/fantextviewer/MainActivity.kt`
- Move: `android/app/src/androidTest/kotlin/com/songs/geulbom/FolderPickerTest.kt` to `android/app/src/androidTest/kotlin/com/songs/fantextviewer/FolderPickerTest.kt`
- Modify: `tool/create_local_keystore.ps1`
- Modify: `tool/android_smoke_test.sh`
- Modify: `README.md`
- Test: `test/widget_test.dart`

**Interfaces:**
- Preserves: `applicationId=com.songs.geulbom`, 기존 `key.properties`.
- Produces: Dart package `fantextviewer`, Android namespace `com.songs.fantextviewer`, 표시명 `판갤텍뷰`.

- [ ] **Step 1: 표시명 실패 테스트 작성**

`AppStrings.appName == '판갤텍뷰'`와 홈 화면 제목을 검증한다.

- [ ] **Step 2: 실패 확인**

Run: `flutter test test/widget_test.dart`
Expected: 기존 `글봄` 값으로 FAIL.

- [ ] **Step 3: 사용자·소스 명칭 일괄 변경**

`pubspec` 이름과 모든 Dart import, 앱 클래스, 내부 로그·글꼴 family·MethodChannel, Kotlin package와 namespace를 변경한다. `applicationId` 옆에는 업데이트 호환성 때문에 유지한다는 주석을 남긴다.

- [ ] **Step 4: 신규 키와 smoke 명칭 변경**

신규 키 파일·별칭·CN과 테스트 폴더명을 `fantextviewer`로 바꾸되, Gradle은 계속 기존 `key.properties` 값을 그대로 읽는다.

- [ ] **Step 5: README를 현재 동작 기준으로 다시 작성**

제품 기능, 저장소 권한, 단일 파일 가져오기, 실제 인코딩 상한, 로컬 백업 정책, 서명 호환성, 개발·검증 명령을 명세대로 기록한다.

- [ ] **Step 6: 레거시 식별자 검사**

Run: `rg -n -i "geulbom|글봄" lib test android tool pubspec.yaml README.md`
Expected: `applicationId`, 호환성 주석, 기존 키 호환 경로 외의 현재 제품 명칭이 없음.

- [ ] **Step 7: 테스트 통과 및 커밋**

Run: `flutter pub get && flutter test test/widget_test.dart`
Expected: PASS.

```powershell
git add pubspec.yaml pubspec.lock lib test android tool README.md
git commit -m "refactor: rename app to fantextviewer"
```

### Task 7: 전체 검증

**Files:**
- Modify only files required by verification failures caused by Tasks 1-6.

**Interfaces:**
- Confirms: 전체 기능, 분석, 포맷, APK 서명 구성, 레거시 applicationId.

- [ ] **Step 1: 포맷 검사**

Run: `dart format .`
Expected: 모든 Dart 파일 포맷 완료.

- [ ] **Step 2: 전체 정적 분석과 테스트**

Run: `flutter analyze`
Expected: `No issues found`.

Run: `flutter test`
Expected: 모든 테스트 PASS.

- [ ] **Step 3: Android 설정과 릴리스 빌드**

Run: `flutter build apk --release`
Expected: `build/app/outputs/flutter-apk/app-release.apk` 생성.

Run: `rg -n 'applicationId = "com.songs.geulbom"' android/app/build.gradle.kts`
Expected: 한 건 일치.

- [ ] **Step 4: 작업 트리와 변경 범위 점검**

Run: `git status --short`
Expected: 계획된 파일만 변경되거나 모두 커밋됨.
