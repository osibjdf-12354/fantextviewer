import 'dart:convert';
import 'dart:typed_data';

import 'package:charset_converter/charset_converter.dart';

enum TextEncoding { utf8, utf16le, utf16be, cp949 }

class DecodedText {
  const DecodedText(this.text, this.encoding);

  final String text;
  final TextEncoding encoding;
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

TextEncoding detectTextEncoding(Uint8List bytes) {
  if (_startsWith(bytes, const [0xef, 0xbb, 0xbf])) {
    return TextEncoding.utf8;
  }
  if (_startsWith(bytes, const [0xff, 0xfe])) {
    return TextEncoding.utf16le;
  }
  if (_startsWith(bytes, const [0xfe, 0xff])) {
    return TextEncoding.utf16be;
  }
  try {
    utf8.decode(bytes, allowMalformed: false);
    return TextEncoding.utf8;
  } on FormatException {
    return TextEncoding.cp949;
  }
}

Future<DecodedText> decodeText(
  Uint8List bytes, {
  TextEncoding? forced,
  Future<String> Function(Uint8List)? cp949Decoder,
}) async {
  final encoding = forced ?? detectTextEncoding(bytes);
  final value = switch (encoding) {
    TextEncoding.utf8 => utf8.decode(
      bytes.sublist(_startsWith(bytes, const [0xef, 0xbb, 0xbf]) ? 3 : 0),
      allowMalformed: false,
    ),
    TextEncoding.utf16le => _decodeUtf16(bytes, Endian.little),
    TextEncoding.utf16be => _decodeUtf16(bytes, Endian.big),
    TextEncoding.cp949 => await (cp949Decoder ?? _decodeCp949)(bytes),
  };
  return DecodedText(
    value.replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
    encoding,
  );
}

List<TextChunk> splitText(String text, {int maxChars = 1200}) {
  if (text.isEmpty) return const [];
  if (maxChars < 1) throw ArgumentError.value(maxChars, 'maxChars');

  final result = <TextChunk>[];
  var start = 0;
  while (start < text.length) {
    var end = (start + maxChars).clamp(0, text.length);
    if (end < text.length) {
      final newline = text.lastIndexOf('\n', end);
      if (newline >= start + maxChars ~/ 2) {
        end = newline + 1;
      } else {
        final nextNewline = text.indexOf('\n', end);
        final hardLimit = (start + 64 * 1024).clamp(0, text.length);
        end = nextNewline < 0 || nextNewline + 1 > hardLimit
            ? hardLimit
            : nextNewline + 1;
      }
      if (_splitsSurrogatePair(text, end)) end--;
    }
    result.add(TextChunk._(start: start, end: end, source: text));
    start = end;
  }
  return result;
}

bool _startsWith(Uint8List bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var index = 0; index < prefix.length; index++) {
    if (bytes[index] != prefix[index]) return false;
  }
  return true;
}

String _decodeUtf16(Uint8List bytes, Endian endian) {
  var start =
      _startsWith(bytes, const [0xff, 0xfe]) ||
          _startsWith(bytes, const [0xfe, 0xff])
      ? 2
      : 0;
  final codes = <int>[];
  for (; start + 1 < bytes.length; start += 2) {
    codes.add(
      endian == Endian.little
          ? bytes[start] | bytes[start + 1] << 8
          : bytes[start] << 8 | bytes[start + 1],
    );
  }
  return String.fromCharCodes(codes);
}

Future<String> _decodeCp949(Uint8List bytes) async {
  try {
    return await CharsetConverter.decode('MS949', bytes);
  } catch (_) {
    return CharsetConverter.decode('EUC-KR', bytes);
  }
}

bool _splitsSurrogatePair(String text, int offset) {
  if (offset <= 0 || offset >= text.length) return false;
  final before = text.codeUnitAt(offset - 1);
  final after = text.codeUnitAt(offset);
  return before >= 0xd800 &&
      before <= 0xdbff &&
      after >= 0xdc00 &&
      after <= 0xdfff;
}
