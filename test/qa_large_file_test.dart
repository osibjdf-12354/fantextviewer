import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geulbom/app_store.dart';
import 'package:geulbom/reader_screen.dart';
import 'package:geulbom/text_document.dart';

void main() {
  test('20MB 한글 UTF-8 본문을 디코딩하고 청크로 준비한다', () async {
    final source = _largeKoreanText(20 * 1024 * 1024);
    final bytes = Uint8List.fromList(utf8.encode(source));
    final stopwatch = Stopwatch()..start();

    final decoded = await decodeText(bytes);
    final chunks = splitText(decoded.text, maxChars: 700);
    stopwatch.stop();

    expect(bytes.length, greaterThanOrEqualTo(20 * 1024 * 1024));
    expect(decoded.encoding, TextEncoding.utf8);
    expect(chunks, isNotEmpty);
    expect(chunks.first.start, 0);
    expect(chunks.last.end, decoded.text.length);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 30)));
  });

  testWidgets('5MB 본문이 스크롤 읽기 화면을 예외 없이 만든다', (tester) async {
    final text = _largeKoreanText(5 * 1024 * 1024);

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderView(
          path: '/large.txt',
          title: 'large.txt',
          text: text,
          encoding: TextEncoding.utf8,
          store: _MemoryStore(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('large.txt'), findsOneWidget);
    expect(find.textContaining('%'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

String _largeKoreanText(int minimumBytes) {
  const line = '가나다라마바사아자차카타파하 한글 대용량 텍스트 읽기 테스트입니다.\n';
  final lineBytes = utf8.encode(line).length;
  return List.filled((minimumBytes / lineBytes).ceil(), line).join();
}

class _MemoryStore extends AppStore {
  _MemoryStore() : super(File('unused'));

  @override
  Future<void> save() async {}
}
