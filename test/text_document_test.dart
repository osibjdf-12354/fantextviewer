import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:geulbom/text_document.dart';

void main() {
  test('BOM과 UTF-8 유효성으로 인코딩을 판별한다', () {
    expect(
      detectTextEncoding(Uint8List.fromList([0xef, 0xbb, 0xbf, 0x61])),
      TextEncoding.utf8,
    );
    expect(
      detectTextEncoding(Uint8List.fromList([0xff, 0xfe, 0x61, 0])),
      TextEncoding.utf16le,
    );
    expect(
      detectTextEncoding(Uint8List.fromList([0xfe, 0xff, 0, 0x61])),
      TextEncoding.utf16be,
    );
    expect(
      detectTextEncoding(Uint8List.fromList([0xb0, 0xa1])),
      TextEncoding.cp949,
    );
  });

  test('BOM을 제거하고 모든 줄바꿈을 LF로 바꾼다', () async {
    final bytes = Uint8List.fromList([
      0xef,
      0xbb,
      0xbf,
      ...utf8.encode('가\r\n나\r다'),
    ]);

    final decoded = await decodeText(bytes);

    expect(decoded.encoding, TextEncoding.utf8);
    expect(decoded.text, '가\n나\n다');
  });

  test('CP949는 전달된 플랫폼 디코더를 사용한다', () async {
    final decoded = await decodeText(
      Uint8List.fromList([0xb0, 0xa1]),
      cp949Decoder: (_) async => '가',
    );

    expect(decoded.text, '가');
  });

  test('UTF-16 LE와 BE를 BOM에 맞춰 읽는다', () async {
    final little = await decodeText(
      Uint8List.fromList([0xff, 0xfe, 0x00, 0xac]),
    );
    final big = await decodeText(Uint8List.fromList([0xfe, 0xff, 0xac, 0x00]));

    expect(little.text, '가');
    expect(big.text, '가');
  });

  test('텍스트 구간은 모든 문자와 원문 오프셋을 보존한다', () {
    const source = '가나다\n라마바\n사아자';

    final chunks = splitText(source, maxChars: 5);

    expect(chunks.map((chunk) => chunk.text).join(), source);
    expect(chunks.first.start, 0);
    expect(chunks.last.end, source.length);
  });
}
