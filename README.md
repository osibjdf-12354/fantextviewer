# 판갤텍뷰

`fantextviewer`는 개인 사용을 위한 Android 한국어 TXT 소설 뷰어입니다. 세로 스크롤, 페이지 스와이프, 화면 터치 넘김, 자동 넘김을 지원하고 문서별 읽기 위치·인코딩·북마크를 기기 안에 저장합니다.

## 주요 기능

- UTF-8, UTF-16 LE/BE, CP949/EUC-KR 자동 감지 및 수동 인코딩 선택
- 세로 스크롤, 스와이프, 터치 넘김, 자동 넘김
- 읽던 위치 자동 복원, 본문 검색, 위치·페이지 이동, 북마크
- 글자 크기·줄 간격·좌우 여백·문단 들여쓰기·배경색·글자색 설정
- 로컬 TTF/OTF 글꼴 가져오기
- 페이지 계산 캐시와 점진적 페이지 계산
- 손상된 읽기 상태 백업의 내보내기 및 복구 파일 가져오기
- 모션 줄이기 설정과 화면 켜짐 유지 설정 지원

## 파일 열기와 저장소 권한

두 가지 파일 열기 방식을 제공합니다.

1. 기기 기본 공유 저장소의 폴더 탐색
   - 사용자가 선택한 폴더 안의 TXT 파일을 목록으로 탐색합니다.
   - Android의 일반 파일 경로를 직접 읽기 때문에 `모든 파일에 대한 접근` 권한을 요청합니다.
   - 이 앱은 개인 사이드로드 용도이며 Google Play 배포 정책을 목표로 하지 않습니다.
2. 시스템 파일 선택기로 파일 하나 열기
   - SD 카드, USB 저장장치, 파일 제공자, 클라우드 앱의 TXT 파일을 하나씩 선택할 수 있습니다.
   - Android에서는 선택한 파일을 최대 64MiB까지 스트리밍하여 앱 내부 `imported_texts` 영역에 영구 복사합니다.
   - 같은 원본을 다시 선택하면 안정된 내부 경로의 복사본을 교체합니다.

SD 카드·USB·클라우드의 폴더 전체를 앱 자체 탐색기로 탐색하는 기능은 제공하지 않습니다. 해당 저장소는 시스템 파일 선택기에서 파일 하나를 가져오는 방식으로 사용합니다.

## 지원 범위와 제한

- TXT 파일 최대 크기: 64MiB
- UTF-8 및 UTF-16 LE/BE: 최대 64MiB 스트리밍 디코딩
- CP949/EUC-KR: 최대 32MiB 전체 파일 디코딩
- 가져오는 TTF/OTF 글꼴: 최대 32MiB
- Android 최소 버전: API 24

파일 내용 해시를 저장하므로 크기와 수정 시각이 같은 교체 파일도 감지합니다. 내용이 바뀌면 이전 진행률·북마크를 초기화하고 인코딩을 다시 확인합니다. 디코딩에 실패하거나 파일이 읽는 도중 바뀌면 기존 저장 상태를 덮어쓰지 않습니다.

## 로컬 데이터와 개인정보

- 읽기 설정과 문서 상태는 앱 지원 디렉터리의 `state.json`에 저장합니다.
- 시스템 선택기로 가져온 TXT와 로컬 글꼴은 앱 내부 파일 영역에 저장합니다.
- 페이지 인덱스는 운영체제가 정리할 수 있는 임시 캐시에 저장합니다.
- Android Auto Backup은 비활성화되어 있습니다.
- 앱은 네트워크 권한을 요청하지 않으며 문서 내용과 읽기 상태를 외부로 전송하지 않습니다.

상태 파일이 손상되면 원본을 `state.json.broken.*`로 보존하고 기본 상태로 시작합니다. 홈 화면의 복구 배너에서 손상 파일을 외부로 내보내 수정하거나, 수정한 JSON 상태 파일을 다시 가져올 수 있습니다. 복구 가져오기가 성공하면 내부 손상 사본은 삭제됩니다.

## 개발

필요 환경:

- Flutter 3.44.6 이상
- Dart 3.12.2 이상
- JDK 17
- Android SDK

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```

CI는 포맷, 정적 분석, 전체 테스트, 서명된 릴리스 APK 빌드와 APK 서명 검증을 수행합니다.

## 개인용 릴리스 APK

새 설치용 개인 키가 없다면 한 번만 생성합니다.

```powershell
powershell -ExecutionPolicy Bypass -File tool/create_local_keystore.ps1
flutter build apk --release
```

생성 파일:

- `android/app/fantextviewer-local.jks`
- `android/key.properties`
- `build/app/outputs/flutter-apk/app-release.apk`

키 저장소와 `key.properties`는 Git에서 제외됩니다. 둘을 함께 안전하게 백업하세요. 서명 키를 잃으면 같은 앱 위에 업데이트할 수 없습니다.

### 기존 설치 업데이트 호환성

제품명과 소스 네임스페이스는 `fantextviewer`/`com.songs.fantextviewer`로 바뀌었지만, 기존 설치의 앱 데이터와 업데이트 호환성을 위해 Android `applicationId`는 의도적으로 `com.songs.geulbom`을 유지합니다.

이미 배포하거나 설치한 APK를 업데이트하려면 반드시 그 APK에 사용한 기존 키와 기존 `android/key.properties`를 그대로 사용해야 합니다. 새 키 생성 스크립트로 만든 키는 기존에 다른 키로 서명한 설치를 업데이트할 수 없습니다. 빌드 설정은 기존 `key.properties`에 기록된 키 파일명과 별칭을 강제로 변경하지 않습니다.

릴리스 서명 설정이 없거나 불완전하면 릴리스 빌드는 안내 메시지와 함께 중단되며 디버그 빌드는 영향을 받지 않습니다.
