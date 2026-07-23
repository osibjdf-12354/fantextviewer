enum ReadingMode { scroll, page, tap }

enum PageTurnDirection { horizontal, vertical, both }

const _defaultBackground = RgbColor(196, 236, 187);
const _defaultForeground = RgbColor(32, 48, 32);

double _boundedDouble(
  Object? value, {
  required double fallback,
  required double min,
  required double max,
}) {
  if (value is! num) return fallback;
  final number = value.toDouble();
  if (!number.isFinite) return fallback;
  return number.clamp(min, max).toDouble();
}

int _nonNegativeInt(Object? value, {int fallback = 0}) {
  if (value is! num || !value.isFinite) return fallback;
  return value.toInt().clamp(0, 0x7fffffffffffffff).toInt();
}

class RgbColor {
  const RgbColor(this.red, this.green, this.blue)
    : assert(red >= 0 && red <= 255),
      assert(green >= 0 && green <= 255),
      assert(blue >= 0 && blue <= 255);

  final int red;
  final int green;
  final int blue;

  int get value => 0xff000000 | red << 16 | green << 8 | blue;

  static RgbColor? tryCreate(int red, int green, int blue) {
    if (red < 0 ||
        red > 255 ||
        green < 0 ||
        green > 255 ||
        blue < 0 ||
        blue > 255) {
      return null;
    }
    return RgbColor(red, green, blue);
  }

  Map<String, int> toJson() => {'red': red, 'green': green, 'blue': blue};

  factory RgbColor.fromJson(Map<String, dynamic> json) {
    final red = json['red'];
    final green = json['green'];
    final blue = json['blue'];
    if (red is! num || green is! num || blue is! num) {
      throw const FormatException('잘못된 RGB 값');
    }
    final color = tryCreate(red.toInt(), green.toInt(), blue.toInt());
    if (color == null) throw const FormatException('잘못된 RGB 값');
    return color;
  }

  @override
  bool operator ==(Object other) =>
      other is RgbColor &&
      red == other.red &&
      green == other.green &&
      blue == other.blue;

  @override
  int get hashCode => Object.hash(red, green, blue);
}

const _unchangedFontFileName = Object();

int _paragraphIndentFromJson(Object? value) =>
    value is int && value >= 0 && value <= 2 ? value : 0;

int _autoPageIntervalFromJson(Object? value) =>
    value is int && value >= 1 && value <= 60 ? value : 5;

RgbColor _colorFromJson(Object? value, RgbColor fallback) {
  if (value is! Map<String, dynamic>) return fallback;
  try {
    return RgbColor.fromJson(value);
  } on FormatException {
    return fallback;
  }
}

class ReaderSettings {
  const ReaderSettings({
    this.mode = ReadingMode.scroll,
    this.background = _defaultBackground,
    this.foreground = _defaultForeground,
    this.fontFileName,
    this.fontSize = 20,
    this.lineHeight = 1.65,
    this.horizontalPadding = 20,
    this.paragraphIndent = 0,
    this.keepAwake = false,
    this.showTotalPages = false,
    this.pageTurnDirection = PageTurnDirection.horizontal,
    this.pageTurnAnimationEnabled = true,
    this.autoPageIntervalSeconds = 5,
  }) : assert(paragraphIndent >= 0 && paragraphIndent <= 2),
       assert(autoPageIntervalSeconds >= 1 && autoPageIntervalSeconds <= 60);

  final ReadingMode mode;
  final RgbColor background;
  final RgbColor foreground;
  final String? fontFileName;
  final double fontSize;
  final double lineHeight;
  final double horizontalPadding;
  final int paragraphIndent;
  final bool keepAwake;
  final bool showTotalPages;
  final PageTurnDirection pageTurnDirection;
  final bool pageTurnAnimationEnabled;
  final int autoPageIntervalSeconds;

  ReaderSettings copyWith({
    ReadingMode? mode,
    RgbColor? background,
    RgbColor? foreground,
    Object? fontFileName = _unchangedFontFileName,
    double? fontSize,
    double? lineHeight,
    double? horizontalPadding,
    int? paragraphIndent,
    bool? keepAwake,
    bool? showTotalPages,
    PageTurnDirection? pageTurnDirection,
    bool? pageTurnAnimationEnabled,
    int? autoPageIntervalSeconds,
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
      paragraphIndent: paragraphIndent ?? this.paragraphIndent,
      keepAwake: keepAwake ?? this.keepAwake,
      showTotalPages: showTotalPages ?? this.showTotalPages,
      pageTurnDirection: pageTurnDirection ?? this.pageTurnDirection,
      pageTurnAnimationEnabled:
          pageTurnAnimationEnabled ?? this.pageTurnAnimationEnabled,
      autoPageIntervalSeconds:
          autoPageIntervalSeconds ?? this.autoPageIntervalSeconds,
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
    'paragraphIndent': paragraphIndent,
    'keepAwake': keepAwake,
    'showTotalPages': showTotalPages,
    'pageTurnDirection': pageTurnDirection.name,
    'pageTurnAnimationEnabled': pageTurnAnimationEnabled,
    'autoPageIntervalSeconds': autoPageIntervalSeconds,
  };

  factory ReaderSettings.fromJson(Map<String, dynamic> json) {
    return ReaderSettings(
      mode: ReadingMode.values.firstWhere(
        (mode) => mode.name == json['mode'],
        orElse: () => ReadingMode.scroll,
      ),
      background: _colorFromJson(json['background'], _defaultBackground),
      foreground: _colorFromJson(json['foreground'], _defaultForeground),
      fontFileName: json['fontFileName'] is String
          ? json['fontFileName'] as String
          : null,
      fontSize: _boundedDouble(
        json['fontSize'],
        fallback: 20,
        min: 14,
        max: 36,
      ),
      lineHeight: _boundedDouble(
        json['lineHeight'],
        fallback: 1.65,
        min: 1.2,
        max: 2.2,
      ),
      horizontalPadding: _boundedDouble(
        json['horizontalPadding'],
        fallback: 20,
        min: 8,
        max: 40,
      ),
      paragraphIndent: _paragraphIndentFromJson(json['paragraphIndent']),
      keepAwake: json['keepAwake'] is bool ? json['keepAwake'] as bool : false,
      showTotalPages: json['showTotalPages'] is bool
          ? json['showTotalPages'] as bool
          : false,
      pageTurnDirection: PageTurnDirection.values.firstWhere(
        (direction) => direction.name == json['pageTurnDirection'],
        orElse: () => PageTurnDirection.horizontal,
      ),
      pageTurnAnimationEnabled: json['pageTurnAnimationEnabled'] is bool
          ? json['pageTurnAnimationEnabled'] as bool
          : true,
      autoPageIntervalSeconds: _autoPageIntervalFromJson(
        json['autoPageIntervalSeconds'],
      ),
    );
  }
}

class Bookmark {
  const Bookmark({
    required this.offset,
    required this.excerpt,
    required this.createdAt,
  });

  final int offset;
  final String excerpt;
  final String createdAt;

  Map<String, Object> toJson() => {
    'offset': offset,
    'excerpt': excerpt,
    'createdAt': createdAt,
  };

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
    offset: _nonNegativeInt(json['offset']),
    excerpt: json['excerpt'] as String,
    createdAt: json['createdAt'] as String,
  );

  static Bookmark? tryFromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['offset'] is! num ||
        !(value['offset'] as num).isFinite ||
        (value['offset'] as num) < 0 ||
        value['excerpt'] is! String ||
        value['createdAt'] is! String) {
      return null;
    }
    return Bookmark.fromJson(value);
  }
}

class DocumentState {
  DocumentState({
    required this.path,
    this.offset = 0,
    this.scrollAlignment = 0,
    this.encoding,
    this.lastOpened = '',
    this.fileSize,
    this.modified,
    List<Bookmark>? bookmarks,
  }) : bookmarks = bookmarks ?? [];

  final String path;
  int offset;
  double scrollAlignment;
  String? encoding;
  String lastOpened;
  int? fileSize;
  String? modified;
  final List<Bookmark> bookmarks;

  Map<String, Object?> toJson() => {
    'path': path,
    'offset': offset,
    'scrollAlignment': scrollAlignment,
    'encoding': encoding,
    'lastOpened': lastOpened,
    'fileSize': fileSize,
    'modified': modified,
    'bookmarks': bookmarks.map((bookmark) => bookmark.toJson()).toList(),
  };

  factory DocumentState.fromJson(Map<String, dynamic> json, {String? path}) {
    final rawFileSize = json['fileSize'];
    final bookmarks = json['bookmarks'] is List
        ? (json['bookmarks'] as List)
              .map(Bookmark.tryFromJson)
              .whereType<Bookmark>()
              .toList()
        : <Bookmark>[];
    return DocumentState(
      path: path ?? (json['path'] is String ? json['path'] as String : ''),
      offset: _nonNegativeInt(json['offset']),
      scrollAlignment: _boundedDouble(
        json['scrollAlignment'],
        fallback: 0,
        min: 0,
        max: 1,
      ),
      encoding: json['encoding'] is String ? json['encoding'] as String : null,
      lastOpened: json['lastOpened'] is String
          ? json['lastOpened'] as String
          : '',
      fileSize: rawFileSize is num && rawFileSize.isFinite && rawFileSize >= 0
          ? rawFileSize.toInt()
          : null,
      modified: json['modified'] is String ? json['modified'] as String : null,
      bookmarks: bookmarks,
    );
  }
}

class AppData {
  AppData({ReaderSettings? settings, Map<String, DocumentState>? documents})
    : settings = settings ?? const ReaderSettings(),
      documents = documents ?? {};

  ReaderSettings settings;
  final Map<String, DocumentState> documents;

  static const currentSchemaVersion = 2;

  Map<String, Object> toJson() => {
    'schemaVersion': currentSchemaVersion,
    'settings': settings.toJson(),
    'documents': documents.map(
      (path, document) => MapEntry(path, document.toJson()),
    ),
  };

  factory AppData.fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion is num && schemaVersion.toInt() > currentSchemaVersion) {
      throw FormatException('지원하지 않는 저장 데이터 버전: $schemaVersion');
    }

    final rawSettings = json['settings'];
    final rawDocuments = json['documents'];
    final documents = <String, DocumentState>{};
    if (rawDocuments is Map<String, dynamic>) {
      for (final entry in rawDocuments.entries) {
        if (entry.value is Map<String, dynamic>) {
          documents[entry.key] = DocumentState.fromJson(
            entry.value as Map<String, dynamic>,
            path: entry.key,
          );
        }
      }
    }
    return AppData(
      settings: rawSettings is Map<String, dynamic>
          ? ReaderSettings.fromJson(rawSettings)
          : const ReaderSettings(),
      documents: documents,
    );
  }
}
