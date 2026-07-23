# 글봄

Android용 로컬 TXT 뷰어입니다. 세로 스크롤과 화면 단위 페이지 넘김, 읽던 위치 자동 저장, 북마크, 본문 검색, 페이지 이동을 지원합니다.

한글 파일은 UTF-8, UTF-16 LE/BE, CP949/EUC-KR을 자동 판별하며 파일별로 인코딩을 직접 바꿀 수 있습니다. 배경색과 글자색은 RGB 값을 직접 입력하거나 기본 연두, 종이, 밤, 세피아 템플릿에서 고를 수 있습니다. 최초 배경색은 RGB(196, 236, 187)입니다.

## 개발 환경

- Flutter 3.44.6 이상
- Dart 3.12.2 이상
- Android API 24 이상

```powershell
flutter pub get
flutter analyze
flutter test
```

개인 사이드로드용 릴리스 키는 처음 한 번만 생성합니다.

```powershell
powershell -ExecutionPolicy Bypass -File tool/create_local_keystore.ps1
flutter build apk --release
```

생성된 개인 설치용 APK:

```text
build/app/outputs/flutter-apk/app-release.apk
```

생성되는 `android/app/geulbom-local.jks`와 `android/key.properties`는 Git에서 제외됩니다. 두 파일을 함께 안전한 위치에 백업하세요. 키를 잃으면 기존에 설치한 앱 위에 같은 서명으로 업데이트할 수 없습니다. 서명 파일이 없거나 불완전하면 릴리스 빌드는 생성 방법을 안내하며 중단되고, 디버그 빌드는 영향을 받지 않습니다.

## 파일 접근

앱은 Android의 시스템 파일·폴더 선택기를 사용하며 `모든 파일에 대한 접근` 권한을 요청하지 않습니다. 사용자가 직접 선택한 TXT 파일이나 폴더만 엽니다.

## 개인정보

파일 내용, 읽기 위치, 북마크와 설정은 기기 안에만 저장됩니다. 앱은 네트워크 권한을 요청하지 않으며 파일을 외부로 전송하지 않습니다.
