import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:characters/characters.dart' as characters;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geulbom/text_document.dart';

void main() {
  test(
    'content fingerprint distinguishes equal-length replacement files',
    () async {
      final first = await decodeText(Uint8List.fromList(utf8.encode('AAAA')));
      final second = await decodeText(Uint8List.fromList(utf8.encode('BBBB')));

      expect((first as dynamic).fingerprint, isNotEmpty);
      expect(
        (first as dynamic).fingerprint,
        isNot((second as dynamic).fingerprint),
      );
    },
  );

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

  test('production decode path detects BOM, UTF-8, and CP949', () async {
    expect(
      (await decodeText(Uint8List.fromList([0xef, 0xbb, 0xbf, 0x61]))).encoding,
      TextEncoding.utf8,
    );
    expect(
      (await decodeText(Uint8List.fromList([0xff, 0xfe, 0x61, 0]))).encoding,
      TextEncoding.utf16le,
    );
    expect(
      (await decodeText(Uint8List.fromList([0xfe, 0xff, 0, 0x61]))).encoding,
      TextEncoding.utf16be,
    );
    expect(
      (await decodeText(
        Uint8List.fromList([0xb0, 0xa1]),
        cp949Decoder: (_) async => '가',
      )).encoding,
      TextEncoding.cp949,
    );
  });

  test('rejects an oversized file before decoding it', () async {
    final directory = await Directory.systemTemp.createTemp('geulbom_limit');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}large.txt');
    await file.writeAsBytes(List<int>.filled(17, 0x61));

    await expectLater(
      loadTextFile(file.path, maxFileBytes: 16),
      throwsA(
        isA<TextFileTooLargeException>()
            .having((error) => error.actualBytes, 'actualBytes', 17)
            .having((error) => error.maximumBytes, 'maximumBytes', 16),
      ),
    );
  });

  test('bounds whole-file decoding for UTF-16 and CP949', () async {
    final directory = await Directory.systemTemp.createTemp(
      'geulbom_decode_limit',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}legacy.txt');
    await file.writeAsBytes(List<int>.filled(9, 0x61));

    await expectLater(
      loadTextFile(
        file.path,
        forced: TextEncoding.cp949,
        maxFileBytes: 20,
        maxWholeFileBytes: 8,
      ),
      throwsA(isA<TextFileTooLargeException>()),
    );
  });

  test('Android CP949 decoding obeys the whole-file byte cap', () async {
    final directory = await Directory.systemTemp.createTemp(
      'geulbom_android_cp949_limit',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}legacy.txt');
    await file.writeAsBytes(List<int>.filled(9, 0x61));

    await expectLater(
      loadTextFile(
        file.path,
        forced: TextEncoding.cp949,
        maxFileBytes: 20,
        maxWholeFileBytes: 8,
        isAndroid: true,
      ),
      throwsA(
        isA<TextFileTooLargeException>().having(
          (error) => error.maximumBytes,
          'maximumBytes',
          8,
        ),
      ),
    );
  });

  test('UTF-16 file decoding streams beyond the whole-file byte cap', () async {
    final directory = await Directory.systemTemp.createTemp(
      'geulbom_utf16_stream',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}utf16.txt');
    await file.writeAsBytes([
      0xff,
      0xfe,
      0x00,
      0xac,
      0x01,
      0xac,
      0x02,
      0xac,
      0x03,
      0xac,
    ]);

    final decoded = await loadTextFile(
      file.path,
      forced: TextEncoding.utf16le,
      maxFileBytes: 20,
      maxWholeFileBytes: 8,
    );

    expect(decoded.text, '가각갂갃');
    expect(decoded.encoding, TextEncoding.utf16le);
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
    final source = List.filled(70 * 1024, '가').join();

    final chunks = splitText(source, maxChars: 700);

    expect(chunks.length, greaterThan(1));
    expect(chunks.every((chunk) => chunk.text.length <= 1400), isTrue);
    expect(chunks.map((chunk) => chunk.text).join(), source);
  });

  test('chunks never split a Unicode grapheme cluster', () {
    final source = List.filled(100, 'e\u0301👨‍👩‍👧‍👦').join();
    final boundaries = <int>{0};
    var offset = 0;
    for (final character in characters.Characters(source)) {
      offset += character.length;
      boundaries.add(offset);
    }

    final chunks = splitText(source, maxChars: 7);

    expect(chunks.map((chunk) => chunk.text).join(), source);
    for (final chunk in chunks) {
      expect(boundaries, contains(chunk.start));
      expect(boundaries, contains(chunk.end));
    }
  });

  test('layout-aware chunks end at actual visual line boundaries', () {
    final source = List.filled(5000, '가').join();
    const style = TextStyle(fontSize: 20, height: 1.5);

    final chunks = splitText(
      source,
      maxChars: 300,
      layoutStyle: style,
      maxWidth: 180,
    );
    final painter = TextPainter(
      text: TextSpan(text: source, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 180);
    addTearDown(painter.dispose);

    expect(chunks.length, greaterThan(1));
    for (final chunk in chunks.take(chunks.length - 1)) {
      expect(
        painter.getLineBoundary(TextPosition(offset: chunk.end)).start,
        chunk.end,
      );
    }
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

  test('maps source offsets to display offsets after inserted indentation', () {
    const source = '첫 문단\n둘째';
    final formatted = formatParagraphIndentation(
      source,
      start: 0,
      end: source.length,
      paragraphIndent: 2,
    );

    expect(formatted.displayOffsetForSource(0), 2);
    expect(formatted.displayOffsetForSource(source.indexOf('둘')), 9);
    expect(formatted.sourceOffsetAt(9), source.indexOf('둘'));
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
