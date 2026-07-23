import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'strings.dart';
import 'text_document.dart';

typedef PaginationBatchCallback = void Function(List<TextPage> pages);
typedef TextLayoutCallback = void Function(int characterCount);

// ponytail: cap UI-isolate layout work; raise only if a real viewport underfills.
const _maxLayoutCharacters = 4096;

class TextPage {
  const TextPage({required this.start, required this.end, int? displayStart})
    : displayStart = displayStart ?? start;

  final int start;
  final int end;
  final int displayStart;
}

Future<List<TextPage>> paginateText({
  required String text,
  required Size size,
  required TextStyle style,
  int paragraphIndent = 0,
  ValueChanged<double>? onProgress,
  PaginationBatchCallback? onBatch,
  TextLayoutCallback? onLayout,
  bool Function()? isCancelled,
}) async {
  if (text.isEmpty) return const [];
  if (size.width <= 0 || size.height <= 0) {
    throw ArgumentError.value(size, 'size', AppStrings.positivePageSize);
  }

  final pages = <TextPage>[];
  var logicalStart = 0;
  var displayStart = 0;
  var batchStart = 0;
  var probeLength = 4096;
  while (logicalStart < text.length) {
    if (isCancelled?.call() == true) break;
    final boundary = await _nextPageBoundary(
      text,
      logicalStart,
      displayStart,
      size,
      style,
      paragraphIndent,
      probeLength,
      onLayout,
      isCancelled,
    );
    if (boundary == null) break;
    pages.add(
      TextPage(
        start: logicalStart,
        end: boundary.end,
        displayStart: displayStart,
      ),
    );
    probeLength = ((boundary.end - displayStart) * 1.25).ceil();
    logicalStart = boundary.end;
    displayStart = boundary.nextDisplayStart;
    if (pages.length - batchStart == 8) {
      onBatch?.call(pages.sublist(batchStart));
      batchStart = pages.length;
      onProgress?.call(logicalStart / text.length);
    }
    if (pages.length.isEven) await Future<void>.delayed(Duration.zero);
  }
  if (batchStart < pages.length) {
    onBatch?.call(pages.sublist(batchStart));
    onProgress?.call(logicalStart / text.length);
  }
  return pages;
}

Future<List<TextPage>> paginateTextWindow({
  required String text,
  required int startOffset,
  required Size size,
  required TextStyle style,
  int paragraphIndent = 0,
  int maxPages = 24,
  TextLayoutCallback? onLayout,
  bool Function()? isCancelled,
}) async {
  if (text.isEmpty) return const [];
  if (size.width <= 0 || size.height <= 0) {
    throw ArgumentError.value(size, 'size', AppStrings.positivePageSize);
  }
  if (maxPages < 1) throw ArgumentError.value(maxPages, 'maxPages');

  var logicalStart = startOffset.clamp(0, text.length - 1);
  if (_splitsSurrogatePair(text, logicalStart)) logicalStart--;
  if (logicalStart > 0) {
    final lowerBound = math.max(0, logicalStart - 4096);
    final newline = text.substring(lowerBound, logicalStart).lastIndexOf('\n');
    if (newline >= 0) logicalStart = lowerBound + newline + 1;
  }

  final pages = <TextPage>[];
  var displayStart = logicalStart;
  var probeLength = 4096;
  while (logicalStart < text.length && pages.length < maxPages) {
    if (isCancelled?.call() == true) break;
    final boundary = await _nextPageBoundary(
      text,
      logicalStart,
      displayStart,
      size,
      style,
      paragraphIndent,
      probeLength,
      onLayout,
      isCancelled,
    );
    if (boundary == null) break;
    pages.add(
      TextPage(
        start: logicalStart,
        end: boundary.end,
        displayStart: displayStart,
      ),
    );
    probeLength = ((boundary.end - displayStart) * 1.25).ceil();
    logicalStart = boundary.end;
    displayStart = boundary.nextDisplayStart;
    if (pages.length.isEven) await Future<void>.delayed(Duration.zero);
  }
  return pages;
}

int estimatedPageCount(
  int textLength,
  List<TextPage> measuredPages, {
  required int fallbackCharactersPerPage,
}) {
  if (textLength <= 0) return 0;
  final measuredCharactersPerPage = measuredPages.isEmpty
      ? fallbackCharactersPerPage
      : (measuredPages.last.end / measuredPages.length).round();
  return math.max(
    1,
    (textLength / math.max(1, measuredCharactersPerPage)).ceil(),
  );
}

int estimatedPageForOffset(
  int offset, {
  required int textLength,
  required int totalPages,
}) {
  if (textLength <= 1 || totalPages <= 1) return 1;
  final ratio = offset.clamp(0, textLength - 1) / (textLength - 1);
  return 1 + (ratio * (totalPages - 1)).floor();
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

typedef _PageBoundary = ({int end, int nextDisplayStart});

Future<_PageBoundary?> _nextPageBoundary(
  String text,
  int logicalStart,
  int displayStart,
  Size size,
  TextStyle style,
  int paragraphIndent,
  int probeLength,
  TextLayoutCallback? onLayout,
  bool Function()? isCancelled,
) async {
  probeLength = probeLength.clamp(1, _maxLayoutCharacters);
  var candidateEnd = math.min(
    math.max(logicalStart + 1, displayStart + probeLength),
    text.length,
  );
  late TextPainter painter;
  late IndentedText formatted;
  while (true) {
    if (candidateEnd - displayStart >= 1024) {
      await Future<void>.delayed(Duration.zero);
    }
    if (isCancelled?.call() == true) return null;
    formatted = formatParagraphIndentation(
      text,
      start: displayStart,
      end: candidateEnd,
      paragraphIndent: paragraphIndent,
    );
    onLayout?.call(candidateEnd - displayStart);
    painter = _layout(formatted.text, size.width, style);
    if (isCancelled?.call() == true) {
      painter.dispose();
      return null;
    }
    if (painter.height > size.height || candidateEnd == text.length) break;
    if (candidateEnd - displayStart >= _maxLayoutCharacters) {
      painter.dispose();
      var end = candidateEnd;
      if (_splitsSurrogatePair(text, end)) end--;
      return (end: end, nextDisplayStart: end);
    }
    painter.dispose();
    candidateEnd = math.min(
      displayStart +
          math.min(_maxLayoutCharacters, (candidateEnd - displayStart) * 2),
      text.length,
    );
  }

  if (painter.height <= size.height) {
    painter.dispose();
    return (end: candidateEnd, nextDisplayStart: candidateEnd);
  }

  final displayOffset =
      _lastFullyVisibleLineEnd(painter, size.height) ??
      painter
          .getPositionForOffset(
            Offset(size.width, math.max(0, size.height - .1)),
          )
          .offset
          .clamp(1, formatted.text.length)
          .toInt();
  var end = formatted.sourceOffsetAt(displayOffset);
  if (_splitsSurrogatePair(text, end)) {
    end = end - logicalStart > 1 ? end - 1 : end + 1;
  }
  if (end < text.length && text.codeUnitAt(end) == 0x0a) end++;
  end = end.clamp(logicalStart + 1, text.length);
  final nextDisplayStart = _overlapSourceStart(
    formatted,
    painter,
    displayOffset,
    logicalStart,
    end,
  );
  painter.dispose();
  return (end: end, nextDisplayStart: nextDisplayStart);
}

int _overlapSourceStart(
  IndentedText formatted,
  TextPainter painter,
  int displayEnd,
  int logicalStart,
  int end,
) {
  var position = displayEnd;
  for (var line = 0; line < 2; line++) {
    final boundary = painter.getLineBoundary(
      TextPosition(offset: position - 1),
    );
    if (boundary.start == 0) break;
    position = boundary.start;
  }
  return formatted.sourceOffsetAt(position).clamp(logicalStart, end).toInt();
}

int? _lastFullyVisibleLineEnd(TextPainter painter, double height) {
  final lines = painter.computeLineMetrics();
  var lastVisibleLine = -1;
  for (var index = 0; index < lines.length; index++) {
    if (lines[index].baseline + lines[index].descent > height) break;
    lastVisibleLine = index;
  }
  if (lastVisibleLine < 0) return null;

  final line = lines[lastVisibleLine];
  final position = painter.getPositionForOffset(
    Offset(line.left, line.baseline),
  );
  return painter.getLineBoundary(position).end;
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
