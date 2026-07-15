import 'dart:math' as math;

import 'package:flutter/widgets.dart';

class TextPage {
  const TextPage({required this.start, required this.end});

  final int start;
  final int end;
}

Future<List<TextPage>> paginateText({
  required String text,
  required Size size,
  required TextStyle style,
  ValueChanged<double>? onProgress,
  bool Function()? isCancelled,
}) async {
  if (text.isEmpty) return const [];
  if (size.width <= 0 || size.height <= 0) {
    throw ArgumentError.value(size, 'size', '페이지 크기는 0보다 커야 합니다.');
  }

  final pages = <TextPage>[];
  var start = 0;
  while (start < text.length) {
    if (isCancelled?.call() == true) break;
    final end = _nextPageEnd(text, start, size, style);
    pages.add(TextPage(start: start, end: end));
    start = end;
    onProgress?.call(start / text.length);
    if (pages.length % 25 == 0) {
      await Future<void>.delayed(Duration.zero);
    }
  }
  return pages;
}

int pageForOffset(List<TextPage> pages, int offset) {
  if (pages.isEmpty || offset <= pages.first.start) return 0;
  if (offset >= pages.last.end) return pages.length - 1;

  var low = 0;
  var high = pages.length - 1;
  while (low <= high) {
    final middle = (low + high) ~/ 2;
    final page = pages[middle];
    if (offset < page.start) {
      high = middle - 1;
    } else if (offset >= page.end) {
      low = middle + 1;
    } else {
      return middle;
    }
  }
  return low.clamp(0, pages.length - 1);
}

int _nextPageEnd(String text, int start, Size size, TextStyle style) {
  var candidateEnd = math.min(start + 4096, text.length);
  late TextPainter painter;
  while (true) {
    painter = _layout(text.substring(start, candidateEnd), size.width, style);
    if (painter.height > size.height || candidateEnd == text.length) break;
    painter.dispose();
    candidateEnd = math.min(candidateEnd + 4096, text.length);
  }

  if (painter.height <= size.height) {
    painter.dispose();
    return candidateEnd;
  }

  final localOffset = painter
      .getPositionForOffset(Offset(size.width, math.max(0, size.height - .1)))
      .offset
      .clamp(1, candidateEnd - start);
  painter.dispose();

  var end = start + localOffset;
  if (_splitsSurrogatePair(text, end)) {
    end = end - start > 1 ? end - 1 : end + 1;
  }
  return end.clamp(start + 1, text.length);
}

TextPainter _layout(String text, double width, TextStyle style) {
  return TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: width);
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
