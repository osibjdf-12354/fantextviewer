enum ReadingMode { scroll, page }

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
    final color = tryCreate(
      (json['red'] as num).toInt(),
      (json['green'] as num).toInt(),
      (json['blue'] as num).toInt(),
    );
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

class ReaderSettings {
  const ReaderSettings({
    this.mode = ReadingMode.scroll,
    this.background = const RgbColor(196, 236, 187),
    this.foreground = const RgbColor(32, 48, 32),
    this.fontFileName,
    this.fontSize = 20,
    this.lineHeight = 1.65,
    this.horizontalPadding = 20,
    this.keepAwake = false,
  });

  final ReadingMode mode;
  final RgbColor background;
  final RgbColor foreground;
  final String? fontFileName;
  final double fontSize;
  final double lineHeight;
  final double horizontalPadding;
  final bool keepAwake;

  ReaderSettings copyWith({
    ReadingMode? mode,
    RgbColor? background,
    RgbColor? foreground,
    Object? fontFileName = _unchangedFontFileName,
    double? fontSize,
    double? lineHeight,
    double? horizontalPadding,
    bool? keepAwake,
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
    'keepAwake': keepAwake,
  };

  factory ReaderSettings.fromJson(Map<String, dynamic> json) {
    return ReaderSettings(
      mode: ReadingMode.values.firstWhere(
        (mode) => mode.name == json['mode'],
        orElse: () => ReadingMode.scroll,
      ),
      background: json['background'] == null
          ? const RgbColor(196, 236, 187)
          : RgbColor.fromJson(json['background'] as Map<String, dynamic>),
      foreground: json['foreground'] == null
          ? const RgbColor(32, 48, 32)
          : RgbColor.fromJson(json['foreground'] as Map<String, dynamic>),
      fontFileName: json['fontFileName'] as String?,
      fontSize: (json['fontSize'] as num? ?? 20).toDouble(),
      lineHeight: (json['lineHeight'] as num? ?? 1.65).toDouble(),
      horizontalPadding: (json['horizontalPadding'] as num? ?? 20).toDouble(),
      keepAwake: json['keepAwake'] as bool? ?? false,
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
    offset: (json['offset'] as num).toInt(),
    excerpt: json['excerpt'] as String,
    createdAt: json['createdAt'] as String,
  );
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

  factory DocumentState.fromJson(Map<String, dynamic> json) => DocumentState(
    path: json['path'] as String,
    offset: (json['offset'] as num? ?? 0).toInt(),
    scrollAlignment: (json['scrollAlignment'] as num? ?? 0).toDouble(),
    encoding: json['encoding'] as String?,
    lastOpened: json['lastOpened'] as String? ?? '',
    fileSize: (json['fileSize'] as num?)?.toInt(),
    modified: json['modified'] as String?,
    bookmarks: (json['bookmarks'] as List<dynamic>? ?? const [])
        .map((item) => Bookmark.fromJson(item as Map<String, dynamic>))
        .toList(),
  );
}

class AppData {
  AppData({ReaderSettings? settings, Map<String, DocumentState>? documents})
    : settings = settings ?? const ReaderSettings(),
      documents = documents ?? {};

  ReaderSettings settings;
  final Map<String, DocumentState> documents;

  Map<String, Object> toJson() => {
    'settings': settings.toJson(),
    'documents': documents.map(
      (path, document) => MapEntry(path, document.toJson()),
    ),
  };

  factory AppData.fromJson(Map<String, dynamic> json) => AppData(
    settings: ReaderSettings.fromJson(
      json['settings'] as Map<String, dynamic>? ?? const {},
    ),
    documents: (json['documents'] as Map<String, dynamic>? ?? const {}).map(
      (path, value) =>
          MapEntry(path, DocumentState.fromJson(value as Map<String, dynamic>)),
    ),
  );
}
