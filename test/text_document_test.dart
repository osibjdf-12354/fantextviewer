import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:geulbom/text_document.dart';

void main() {
  test(
    'loads a large UTF-8 file while the root event loop stays responsive',
    () async {
      final directory = await Directory.systemTemp.createTemp('geulbom_decode');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}${Platform.pathSeparator}large.txt');
      await file.writeAsString(List.filled(4 * 1024 * 1024, '가').join());
      var timerTicks = 0;
      final timer = Timer.periodic(
        const Duration(milliseconds: 1),
        (_) => timerTicks++,
      );

      final decoded = await loadTextFile(file.path);
      timer.cancel();

      expect(decoded.encoding, TextEncoding.utf8);
      expect(decoded.text.length, 4 * 1024 * 1024);
      expect(timerTicks, greaterThan(1));
    },
  );

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

  test('개행 없는 대형 텍스트도 단일 렌더링 청크로 만들지 않는다', () {
    final source = List.filled(200000, '가').join();

    final chunks = splitText(source, maxChars: 700);

    expect(chunks.length, greaterThan(1));
    expect(chunks.every((chunk) => chunk.text.length <= 64 * 1024), isTrue);
    expect(chunks.map((chunk) => chunk.text).join(), source);
  });

  test('formats novel paragraphs without doubling existing indentation', () {
    const source = '첫 문단\n\n 둘째\n\t셋째\n　넷째\n마지막';

    final one = formatParagraphIndentation(
      source,
      start: 0,
      end: source.length,
      paragraphIndent: 1,
    );
    final two = formatParagraphIndentation(
      source,
      start: 0,
      end: source.length,
      paragraphIndent: 2,
    );

    expect(one.text, '　첫 문단\n\n 둘째\n\t셋째\n　넷째\n　마지막');
    expect(two.text, '　　첫 문단\n\n 둘째\n\t셋째\n　넷째\n　　마지막');
    final displayOffset = two.text.indexOf('마지막');
    expect(two.sourceOffsetAt(displayOffset), source.indexOf('마지막'));
    expect(two.sourceOffsetAt(displayOffset + 3), source.length);
  });

  test('does not indent a range that begins mid-paragraph', () {
    const source = '앞문장 계속\n새 문단';
    final start = source.indexOf('문장');

    final formatted = formatParagraphIndentation(
      source,
      start: start,
      end: source.length,
      paragraphIndent: 1,
    );

    expect(formatted.text, '문장 계속\n　새 문단');
    expect(formatted.sourceOffsetAt(0), start);
    expect(formatted.sourceOffsetAt(formatted.text.length), source.length);
  });

  test('zero indentation returns the unmodified source range', () {
    const source = '앞\n뒤';
    final formatted = formatParagraphIndentation(
      source,
      start: 2,
      end: source.length,
      paragraphIndent: 0,
    );

    expect(formatted.text, '뒤');
    expect(formatted.sourceOffsetAt(1), source.length);
  });
}
