import 'package:flutter_test/flutter_test.dart';
import 'package:fantextviewer/text_document.dart';

void main() {
  test('splits a 20MB single line without scanning the remaining document', () {
    final source = List.filled(20 * 1024 * 1024, 'a').join();
    final stopwatch = Stopwatch()..start();

    final chunks = splitText(source, maxChars: 700);

    stopwatch.stop();
    expect(
      chunks.map((chunk) => chunk.text.length).reduce((a, b) => a + b),
      source.length,
    );
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
  });
}
