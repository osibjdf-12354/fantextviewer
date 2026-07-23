abstract final class AppStrings {
  static const pageCacheFailed = '페이지 캐시를 읽지 못해 다시 계산합니다.';
  static const stateRecoveryTitle = '저장 상태 복구';
  static const stateRecoveryBody =
      '손상된 저장 상태를 초기화했습니다. 보존된 백업을 수정한 뒤 다시 가져올 수 있습니다.';
  static const importStateFile = '상태 파일 가져오기';
  static const exportRecoveryFile = '복구 파일 내보내기';
  static const stateExportSucceeded = '복구 파일을 내보냈습니다.';
  static const stateImportSucceeded = '저장 상태를 복구했습니다.';
  static const appName = '글봄';

  static const cancel = '취소';
  static const delete = '삭제';
  static const close = '닫기';
  static const retry = '다시 시도';
  static const move = '이동';
  static const search = '검색';
  static const unknown = '알 수 없음';

  static const textFile = '텍스트 파일';
  static const fontFile = '글꼴 파일';
  static const fileBrowser = '파일 탐색기';
  static const chooseFolder = '폴더 선택';
  static const systemFilePicker = '시스템 파일 선택기';
  static const sort = '정렬';
  static const sortByName = '이름순';
  static const sortByModified = '수정일순';
  static const parentFolder = '상위 폴더';
  static const searchFileName = '파일명 검색';
  static const folderEmpty = '표시할 폴더나 TXT 파일이 없습니다.';
  static const chooseFolderOrFile = 'TXT 파일이 있는 폴더를 선택하거나\n파일 하나를 바로 여세요.';
  static const chooseOneFile = '파일 하나 선택';
  static const folderAccessRequired = '폴더 내용을 보려면 설정에서 모든 파일 접근을 허용해 주세요.';

  static const missingFileTitle = '파일을 찾을 수 없습니다';
  static const missingFileBody = '파일이 이동되거나 삭제되었습니다. 최근 목록에서 지울까요?';
  static const keep = '유지';
  static const removeFromList = '목록에서 삭제';
  static const recentFiles = '최근 파일';
  static const browseFiles = '파일 탐색';
  static const noRecentFiles = '최근에 읽은 파일이 없습니다.';
  static const browseFilesHint = '파일 탐색 버튼으로 TXT 파일을 열어 보세요.';
  static const removeRecent = '최근 목록에서 삭제';

  static const openingLargeFile = '큰 파일을 여는 중입니다. 잠시 기다려 주세요.';
  static const fileChangedWhileReading = '읽는 동안 파일이 변경되었습니다. 다시 시도해 주세요.';
  static const fileReadFailed = '파일을 읽지 못했습니다.';
  static const openWithEncoding = '인코딩으로 열기';
  static const calculating = '계산 중';
  static const saveReadingPositionFailed = '읽기 위치를 저장하지 못했습니다.';
  static const addBookmark = '북마크 추가';
  static const emptyFile = '빈 파일입니다.';
  static const autoMode = '오토모드';
  static const openFile = '파일 열기';
  static const goToPosition = '위치 이동';
  static const searchBody = '본문 검색';
  static const bookmarks = '북마크';
  static const displaySettings = '표시 설정';
  static const fileInfo = '파일 정보';
  static const exitApp = '앱 종료';
  static const calculatingPages = '페이지를 계산하고 있습니다.';
  static const previousSearchResult = '이전 검색 결과';
  static const nextSearchResult = '다음 검색 결과';
  static const endSearch = '검색 종료';
  static const enterPositivePage = '1 이상의 페이지를 입력해 주세요.';
  static const lastPageAutoStopped = '마지막 페이지입니다. 오토모드를 종료했습니다.';
  static const page = '페이지';
  static const noSearchResults = '검색 결과가 없습니다.';
  static const noBookmarks = '저장된 북마크가 없습니다.';
  static const blankLine = '빈 줄';
  static const deleteBookmark = '북마크 삭제';
  static const changeEncoding = '인코딩 변경';

  static const readingMethod = '읽기 방식';
  static const verticalScroll = '세로 스크롤';
  static const swipe = '스와이프';
  static const tap = '탭';
  static const pageTurnDirection = '페이지 넘김 방향';
  static const horizontalTurn = '좌우 넘김';
  static const verticalTurn = '상하 넘김';
  static const bothDirections = '둘 다';
  static const bothDirectionsHint = '둘 다 모드에서는 탭 영역이 위/아래로 나뉩니다.';
  static const pageTurnAnimation = '페이지 넘김 애니메이션';
  static const autoPageInterval = '오토 페이지 간격 (초)';
  static const autoModeHint = '세로 스크롤에서도 오토모드를 켜면 스와이프·상하 넘김으로 자동 전환됩니다.';
  static const pageIndicator = '페이지 표시';
  static const currentPageOnly = '현재 페이지만';
  static const currentAndTotalPages = '현재/전체 페이지';
  static const font = '글꼴';
  static const systemFont = '시스템 기본 글꼴';
  static const importLocalFont = '로컬 글꼴 가져오기';
  static const fontSize = '글자 크기';
  static const lineHeight = '줄 간격';
  static const horizontalPadding = '좌우 여백';
  static const paragraphIndent = '문단 들여쓰기';
  static const none = '없음';
  static const oneCharacter = '한 글자';
  static const twoCharacters = '두 글자';
  static const colorTemplates = '색상 템플릿';
  static const previewCharacter = '가';
  static const fontPreview = '한글 미리보기 가나다라';
  static const lowContrastWarning = '명암비가 낮아 읽기 어려울 수 있습니다.';
  static const resetDefaultColors = '기본 색상으로 복구';
  static const keepScreenAwake = '읽는 동안 화면 켜짐 유지';
  static const fontLoadFailed = '글꼴을 불러오지 못했습니다.';
  static const fontImportFailed = '글꼴을 가져오지 못했습니다.';
  static const fontDeleteTitle = '글꼴 삭제';
  static const fontLoadedUntilRestart =
      '이미 불러온 글꼴 데이터는 앱을 다시 시작할 때까지 메모리에 남을 수 있습니다.';
  static const fontDeleteFailed = '글꼴을 삭제하지 못했습니다.';
  static const fontDeletedSaveFailed = '글꼴은 삭제했지만 설정을 저장하지 못했습니다.';
  static const backgroundRgb = '배경색 RGB';
  static const foregroundRgb = '글자색 RGB';
  static const defaultGreen = '기본 연두';
  static const paper = '종이';
  static const night = '밤';
  static const sepia = '세피아';

  static const invalidRgb = '잘못된 RGB 값';
  static const supportedFontsOnly = '지원하는 글꼴은 TTF 또는 OTF 파일입니다.';
  static const fontTooLarge = '글꼴 파일 크기는 32MB 이하여야 합니다.';
  static const invalidFont = '올바른 TTF 또는 OTF 글꼴 파일이 아닙니다.';
  static const positivePageSize = '페이지 크기는 0보다 커야 합니다.';

  static String folderReadFailed(Object error) => '폴더를 읽지 못했습니다.\n$error';
  static String stateImportFailed(Object error) => '저장 상태를 가져오지 못했습니다.\n$error';
  static String stateExportFailed(Object error) => '복구 파일을 내보내지 못했습니다.\n$error';
  static String folderOpenFailed(Object error) => '폴더를 열지 못했습니다.\n$error';
  static String unsupportedSchema(Object version) =>
      '지원하지 않는 저장 데이터 버전: $version';
  static String currentPage(int page) => '현재 $page페이지';
  static String pageRange(int lastPage) => '1~$lastPage 사이 페이지를 입력해 주세요.';
  static String calculatingThroughPage(int page) =>
      '$page페이지까지 계산하고 있습니다. 계산되는 즉시 이동합니다.';
  static String approximatePageRange(int totalPages) => '약 1~$totalPages (추정)';
  static String bookmarkSaved(Object page) => '$page에 북마크를 저장했습니다.';
  static String readingStateSaveDiagnostic(
    Object error,
    StackTrace stackTrace,
  ) => '읽기 상태 저장 실패: $error\n$stackTrace';
  static String fontDeleteTooltip(String label) => '$label 삭제';
  static String fontDeletePrompt(String label) => '$label 글꼴의 앱 내부 복사본을 삭제할까요?';
  static String settingDecrease(String label) => '$label 줄이기';
  static String settingIncrease(String label) => '$label 늘리기';
  static String contrastRatio(String ratio) => '명암비 $ratio:1';
  static String fileDetails(String path, String size, String encoding) =>
      '$path\n\n크기: $size\n인코딩: $encoding';
  static String fileTooLarge(
    int actualBytes,
    int maximumBytes,
    String encodingLabel,
  ) =>
      '파일이 너무 큽니다$encodingLabel: '
      '$actualBytes바이트 / 최대 $maximumBytes바이트';
}
