import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:characters/characters.dart' as characters;
import 'package:charset_converter/charset_converter.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'strings.dart';

enum TextEncoding { utf8, utf16le, utf16be, cp949 }

const maxSupportedTextFileBytes = 64 * 1024 * 1024;
const maxWholeFileDecodeBytes = 32 * 1024 * 1024;
const _textFileChannel = MethodChannel('com.songs.fantextviewer/text-file');

class TextFileTooLargeException implements Exception {
  const TextFileTooLargeException({
    required this.actualBytes,
    required this.maximumBytes,
    required this.encoding,
  });

  final int actualBytes;
  final int maximumBytes;
  final TextEncoding? encoding;

  @override
  String toString() {
    final encodingLabel = encoding == null ? '' : ' (${encoding!.name})';
    return AppStrings.fileTooLarge(actualBytes, maximumBytes, encodingLabel);
  }
}

class DecodedText {
  const DecodedText(this.text, this.encoding, {required this.fingerprint});

  final String text;
  final TextEncoding encoding;
  final String fingerprint;
}

class TextChunk {
  const TextChunk._({
    required this.start,
    required this.end,
    required this._source,
  });

  final int start;
  final int end;
  final String _source;

  String get text => _source.substring(start, end);
}

class IndentedText {
  const IndentedText(
    this.text,
    this.sourceStart,
    this.sourceEnd,
    this._insertedOffsets,
  );

  final String text;
  final int sourceStart;
  final int sourceEnd;
  final List<int> _insertedOffsets;

  int sourceOffsetAt(int displayOffset) {
    final safeOffset = displayOffset.clamp(0, text.length).toInt();
    var insertedBefore = 0;
    for (final offset in _insertedOffsets) {
      if (offset >= safeOffset) break;
      insertedBefore++;
    }
    return (sourceStart + safeOffset - insertedBefore)
        .clamp(sourceStart, sourceEnd)
        .toInt();
  }

  int displayOffsetForSource(int sourceOffset) {
    final safeSourceOffset = sourceOffset.clamp(sourceStart, sourceEnd).toInt();
    var displayOffset = safeSourceOffset - sourceStart;
    for (final insertedOffset in _insertedOffsets) {
      if (insertedOffset > displayOffset) break;
      displayOffset++;
    }
    return displayOffset.clamp(0, text.length).toInt();
  }
}

IndentedText formatParagraphIndentation(
  String source, {
  required int start,
  required int end,
  required int paragraphIndent,
}) {
  RangeError.checkValidRange(start, end, source.length);
  assert(paragraphIndent >= 0 && paragraphIndent <= 2);
  if (paragraphIndent == 0) {
    return IndentedText(source.substring(start, end), start, end, const []);
  }

  final buffer = StringBuffer();
  final insertedOffsets = <int>[];
  for (var index = start; index < end; index++) {
    final codeUnit = source.codeUnitAt(index);
    final paragraphStart = index == 0 || source.codeUnitAt(index - 1) == 0x0a;
    final alreadyIndented =
        codeUnit == 0x20 || codeUnit == 0x09 || codeUnit == 0x3000;
    if (paragraphStart && codeUnit != 0x0a && !alreadyIndented) {
      for (var count = 0; count < paragraphIndent; count++) {
        insertedOffsets.add(buffer.length);
        buffer.writeCharCode(0x3000);
      }
    }
    buffer.writeCharCode(codeUnit);
  }
  return IndentedText(buffer.toString(), start, end, insertedOffsets);
}

Future<DecodedText> decodeText(
  Uint8List bytes, {
  TextEncoding? forced,
  Future<String> Function(Uint8List)? cp949Decoder,
  String? contentFingerprint,
}) async {
  var encoding = forced ?? _bomEncoding(bytes);
  String value;
  if (encoding == null) {
    try {
      value = utf8.decode(bytes, allowMalformed: false);
      encoding = TextEncoding.utf8;
    } on FormatException {
      encoding = TextEncoding.cp949;
      value = await (cp949Decoder ?? _decodeCp949)(bytes);
    }
  } else {
    value = await _decodeBytes(bytes, encoding, cp949Decoder);
  }
  return DecodedText(
    _normalizeLineEndings(value),
    encoding,
    fingerprint: contentFingerprint ?? sha256.convert(bytes).toString(),
  );
}

Future<DecodedText> loadTextFile(
  String path, {
  TextEncoding? forced,
  int maxFileBytes = maxSupportedTextFileBytes,
  int maxWholeFileBytes = maxWholeFileDecodeBytes,
  bool? isAndroid,
}) async {
  final rootToken = ServicesBinding.rootIsolateToken;
  return Isolate.run(
    () => _loadTextFileInBackground(
      path,
      forced,
      rootToken,
      maxFileBytes,
      maxWholeFileBytes,
      isAndroid ?? Platform.isAndroid,
    ),
    debugName: 'load text file',
  );
}

Future<DecodedText> _loadTextFileInBackground(
  String path,
  TextEncoding? forced,
  RootIsolateToken? rootToken,
  int maxFileBytes,
  int maxWholeFileBytes,
  bool isAndroid,
) async {
  if (rootToken != null) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(rootToken);
  }
  final file = File(path);
  final size = await file.length();
  if (size > maxFileBytes) {
    throw TextFileTooLargeException(
      actualBytes: size,
      maximumBytes: maxFileBytes,
      encoding: forced,
    );
  }
  final fingerprint = (await sha256.bind(file.openRead()).first).toString();
  final reader = await file.open();
  late final Uint8List prefix;
  try {
    prefix = await reader.read(3);
  } finally {
    await reader.close();
  }
  final bomEncoding = _bomEncoding(prefix);
  final encoding = forced ?? bomEncoding;
  if (encoding == TextEncoding.utf16le || encoding == TextEncoding.utf16be) {
    final value = await _decodeUtf16File(
      file,
      encoding == TextEncoding.utf16le ? Endian.little : Endian.big,
      skipBom: bomEncoding == encoding,
    );
    return DecodedText(
      _normalizeLineEndings(value),
      encoding!,
      fingerprint: fingerprint,
    );
  }
  if (encoding == null || encoding == TextEncoding.utf8) {
    try {
      final start = bomEncoding == TextEncoding.utf8 ? 3 : 0;
      final value = await file.openRead(start).transform(utf8.decoder).join();
      return DecodedText(
        _normalizeLineEndings(value),
        TextEncoding.utf8,
        fingerprint: fingerprint,
      );
    } on FormatException {
      if (encoding == TextEncoding.utf8) rethrow;
    }
  }
  if (size > maxWholeFileBytes) {
    throw TextFileTooLargeException(
      actualBytes: size,
      maximumBytes: maxWholeFileBytes,
      encoding: encoding ?? TextEncoding.cp949,
    );
  }
  if (isAndroid) {
    final value = await _textFileChannel.invokeMethod<String>('decode', {
      'path': path,
      'encoding': 'MS949',
    });
    if (value == null) throw const FormatException('CP949 decode failed');
    return DecodedText(
      _normalizeLineEndings(value),
      TextEncoding.cp949,
      fingerprint: fingerprint,
    );
  }
  final bytes = await file.readAsBytes();
  return decodeText(
    bytes,
    forced: encoding ?? TextEncoding.cp949,
    contentFingerprint: fingerprint,
  );
}

Future<String> _decodeBytes(
  Uint8List bytes,
  TextEncoding encoding,
  Future<String> Function(Uint8List)? cp949Decoder,
) async {
  return switch (encoding) {
    TextEncoding.utf8 => utf8.decode(
      Uint8List.sublistView(
        bytes,
        _startsWith(bytes, const [0xef, 0xbb, 0xbf]) ? 3 : 0,
      ),
      allowMalformed: false,
    ),
    TextEncoding.utf16le => _decodeUtf16(bytes, Endian.little),
    TextEncoding.utf16be => _decodeUtf16(bytes, Endian.big),
    TextEncoding.cp949 => await (cp949Decoder ?? _decodeCp949)(bytes),
  };
}

TextEncoding? _bomEncoding(Uint8List bytes) {
  if (_startsWith(bytes, const [0xef, 0xbb, 0xbf])) {
    return TextEncoding.utf8;
  }
  if (_startsWith(bytes, const [0xff, 0xfe])) {
    return TextEncoding.utf16le;
  }
  if (_startsWith(bytes, const [0xfe, 0xff])) {
    return TextEncoding.utf16be;
  }
  return null;
}

String _normalizeLineEndings(String value) =>
    value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

List<TextChunk> splitText(
  String text, {
  int maxChars = 1200,
  TextStyle? layoutStyle,
  double? maxWidth,
  TextDirection textDirection = TextDirection.ltr,
}) {
  if (text.isEmpty) return const [];
  if (maxChars < 1) throw ArgumentError.value(maxChars, 'maxChars');
  if (maxWidth != null && (!maxWidth.isFinite || maxWidth <= 0)) {
    throw ArgumentError.value(maxWidth, 'maxWidth');
  }

  final result = <TextChunk>[];
  var start = 0;
  while (start < text.length) {
    var end = (start + maxChars).clamp(0, text.length);
    if (end < text.length) {
      var newline = -1;
      for (var index = end; index >= start + maxChars ~/ 2; index--) {
        if (text.codeUnitAt(index) == 0x0a) {
          newline = index;
          break;
        }
      }
      if (newline >= 0) {
        end = newline + 1;
      } else {
        final hardLimit = (start + maxChars * 2).clamp(0, text.length);
        var nextNewline = -1;
        for (var index = end; index < hardLimit; index++) {
          if (text.codeUnitAt(index) == 0x0a) {
            nextNewline = index;
            break;
          }
        }
        if (nextNewline >= 0) {
          end = nextNewline + 1;
        } else if (layoutStyle != null && maxWidth != null) {
          end = _visualLineBoundary(
            text,
            start: start,
            preferredEnd: end,
            scanEnd: hardLimit,
            style: layoutStyle,
            maxWidth: maxWidth,
            textDirection: textDirection,
          );
        }
      }
      end = _graphemeBoundaryAtOrBefore(text, end, after: start);
    }
    result.add(TextChunk._(start: start, end: end, source: text));
    start = end;
  }
  return result;
}

int _visualLineBoundary(
  String text, {
  required int start,
  required int preferredEnd,
  required int scanEnd,
  required TextStyle style,
  required double maxWidth,
  required TextDirection textDirection,
}) {
  final safeScanEnd = _graphemeBoundaryAtOrBefore(text, scanEnd, after: start);
  final segment = text.substring(start, safeScanEnd);
  final painter = TextPainter(
    text: TextSpan(text: segment, style: style),
    textDirection: textDirection,
  )..layout(maxWidth: maxWidth);
  try {
    final line = painter.getLineBoundary(
      TextPosition(offset: (preferredEnd - start).clamp(0, segment.length)),
    );
    final localEnd = line.start > 0 ? line.start : line.end;
    return start + localEnd;
  } finally {
    painter.dispose();
  }
}

int _graphemeBoundaryAtOrBefore(
  String text,
  int candidate, {
  required int after,
}) {
  if (candidate >= text.length) return text.length;
  final range = characters.CharacterRange.at(text, candidate);
  final boundary = range.stringBeforeLength;
  if (boundary > after) return boundary;
  if (range.isNotEmpty) return boundary + range.current.length;
  if (range.moveNext()) return range.stringBeforeLength + range.current.length;
  return text.length;
}

bool _startsWith(Uint8List bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var index = 0; index < prefix.length; index++) {
    if (bytes[index] != prefix[index]) return false;
  }
  return true;
}

String _decodeUtf16(Uint8List bytes, Endian endian) {
  final start =
      _startsWith(bytes, const [0xff, 0xfe]) ||
          _startsWith(bytes, const [0xfe, 0xff])
      ? 2
      : 0;
  return _decodeUtf16Chunk(Uint8List.sublistView(bytes, start), endian);
}

String _decodeUtf16Chunk(Uint8List bytes, Endian endian) {
  final codes = <int>[];
  for (var start = 0; start + 1 < bytes.length; start += 2) {
    codes.add(
      endian == Endian.little
          ? bytes[start] | bytes[start + 1] << 8
          : bytes[start] << 8 | bytes[start + 1],
    );
  }
  return String.fromCharCodes(codes);
}

Future<String> _decodeUtf16File(
  File file,
  Endian endian, {
  required bool skipBom,
}) async {
  final reader = await file.open();
  final output = StringBuffer();
  int? pendingByte;
  try {
    if (skipBom) await reader.setPosition(2);
    while (true) {
      final chunk = await reader.read(64 * 1024);
      if (chunk.isEmpty) break;
      Uint8List bytes = chunk;
      if (pendingByte != null) {
        bytes = Uint8List(chunk.length + 1)
          ..[0] = pendingByte
          ..setRange(1, chunk.length + 1, chunk);
        pendingByte = null;
      }
      if (bytes.length.isOdd) {
        pendingByte = bytes.last;
        bytes = Uint8List.sublistView(bytes, 0, bytes.length - 1);
      }
      if (bytes.isNotEmpty) output.write(_decodeUtf16Chunk(bytes, endian));
    }
  } finally {
    await reader.close();
  }
  if (pendingByte != null) {
    throw const FormatException('UTF-16 file has an incomplete code unit');
  }
  return output.toString();
}

Future<String> _decodeCp949(Uint8List bytes) async {
  try {
    return await CharsetConverter.decode('MS949', bytes);
  } catch (_) {
    return CharsetConverter.decode('EUC-KR', bytes);
  }
}
