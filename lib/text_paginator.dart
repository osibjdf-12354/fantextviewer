import 'dart:math' as math;

import 'package:flutter/widgets.dart';

typedef PaginationBatchCallback = void Function(List<TextPage> pages);
typedef TextLayoutCallback = void Function(int characterCount);

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
  PaginationBatchCallback? onBatch,
  TextLayoutCallback? onLayout,
  bool Function()? isCancelled,
}) async {
  if (text.isEmpty) return const [];
  if (size.width <= 0 || size.height <= 0) {
    throw ArgumentError.value(size, 'size', '페이지 크기는 0보다 커야 합니다.');
  }

  final pages = <TextPage>[];
  var start = 0;
  var batchStart = 0;
  var probeLength = 4096;
  while (start < text.length) {
    if (isCancelled?.call() == true) break;
    final end = _nextPageEnd(
      text,
      start,
      size,
      style,
      probeLength,
      onLayout,
      isCancelled,
    );
    if (end == null) break;
    pages.add(TextPage(start: start, end: end));
    probeLength = end - start;
    start = end;
    if (pages.length - batchStart == 8) {
      onBatch?.call(pages.sublist(batchStart));
      batchStart = pages.length;
      onProgress?.call(start / text.length);
      await Future<void>.delayed(Duration.zero);
    }
  }
  if (batchStart < pages.length) {
    onBatch?.call(pages.sublist(batchStart));
    onProgress?.call(start / text.length);
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

int? _nextPageEnd(
  String text,
  int start,
  Size size,
  TextStyle style,
  int probeLength,
  TextLayoutCallback? onLayout,
  bool Function()? isCancelled,
) {
  var candidateEnd = math.min(start + probeLength, text.length);
  late TextPainter painter;
  while (true) {
    painter = _layout(
      text.substring(start, candidateEnd),
      size.width,
      style,
      onLayout,
    );
    if (isCancelled?.call() == true) {
      painter.dispose();
      return null;
    }
    if (painter.height > size.height || candidateEnd == text.length) break;
    painter.dispose();
    candidateEnd = math.min(start + (candidateEnd - start) * 2, text.length);
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

TextPainter _layout(
  String text,
  double width,
  TextStyle style,
  TextLayoutCallback? onLayout,
) {
  onLayout?.call(text.length);
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
