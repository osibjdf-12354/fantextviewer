# Page Overlap Handoff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep two repeated context lines on settled novel pages while ensuring only one page is painted during every transition frame.

**Architecture:** Preserve the existing paginator, cache, and reader overlap ranges. Change only `PageTurnView` so the outgoing page fades out alone during the first half of progress and the incoming page fades in alone during the second half, switching while fully transparent.

**Tech Stack:** Flutter, Dart, `AnimationController`, Flutter widget tests

## Global Constraints

- Keep the previous page's final two visual lines at the top of the next page.
- Never paint outgoing and incoming page copies in the same transition frame.
- Apply the same behavior to horizontal and vertical swipe, tap, accessibility, and automatic turns.
- Do not change pagination, page counts, bookmarks, saved offsets, scroll mode, or dependencies.
- Preserve text selection, cancellation, resize, and first/last-page behavior.

---

### Task 1: Single-page transition handoff

**Files:**
- Modify: `lib/page_turn_view.dart:302-329`
- Test: `test/page_turn_view_test.dart:156-278`

**Interfaces:**
- Consumes: `_progress.value`, `_axis`, `_translation(Axis, double)`, and the existing current/adjacent page widgets.
- Produces: the existing `PageTurnView` API with one painted page per animation frame; no public signature changes.

- [ ] **Step 1: Write the failing swipe handoff test**

Add this widget test before the resize test:

```dart
testWidgets('transition renders one page at a time on both axes', (
  tester,
) async {
  for (final direction in [
    PageTurnDirection.horizontal,
    PageTurnDirection.vertical,
  ]) {
    final page = ValueNotifier(1);
    addTearDown(page.dispose);
    await _pumpPager(tester, page, direction);
    final rect = tester.getRect(find.byType(PageTurnView));
    final extent = direction == PageTurnDirection.horizontal
        ? rect.width
        : rect.height;
    final firstMove = direction == PageTurnDirection.horizontal
        ? Offset(-extent * .25, 0)
        : Offset(0, -extent * .25);
    final secondMove = direction == PageTurnDirection.horizontal
        ? Offset(-extent * .5, 0)
        : Offset(0, -extent * .5);

    final gesture = await tester.startGesture(rect.center);
    await gesture.moveBy(firstMove);
    await tester.pump();
    expect(find.byKey(const ValueKey(1)), findsOneWidget);
    expect(find.byKey(const ValueKey(2)), findsNothing);

    await gesture.moveBy(secondMove);
    await tester.pump();
    expect(find.byKey(const ValueKey(1)), findsNothing);
    expect(find.byKey(const ValueKey(2)), findsOneWidget);

    await gesture.cancel();
    await tester.pumpAndSettle();
  }
});
```

- [ ] **Step 2: Strengthen the programmatic-turn test**

After the existing transform-axis assertion at the animation midpoint, add:

```dart
expect(find.text('page 0'), findsNothing);
expect(find.text('page 1'), findsOneWidget);
```

This covers the `animateNext` path used by automatic turns. Tap and
accessibility actions already call the same `_animateTurn` method.

- [ ] **Step 3: Run the tests and verify the current stack fails**

Run:

```powershell
flutter test test/page_turn_view_test.dart --plain-name "transition renders one page at a time on both axes"
flutter test test/page_turn_view_test.dart --plain-name "programmatic next page uses the requested vertical axis"
```

Expected: both tests fail because the current `Stack` contains the outgoing and
incoming pages together.

- [ ] **Step 4: Render one page on each side of the midpoint**

Replace the animated `Stack` body with:

```dart
final incoming = adjacent != null && progress.abs() >= .5;
final visiblePage = incoming ? adjacent : current;
final offsetValue = incoming ? adjacentStart + value : value;
final opacity = incoming
    ? (progress.abs() - .5) * 2
    : 1 - progress.abs() * 2;
return SizedBox.expand(
  child: Opacity(
    opacity: opacity.clamp(0, 1).toDouble(),
    child: Transform.translate(
      offset: _translation(axis, offsetValue),
      child: visiblePage,
    ),
  ),
);
```

Do not change gesture thresholds, durations, curves, page callbacks, or the
outer `ClipRect`.

- [ ] **Step 5: Run component tests**

Run:

```powershell
flutter test test/page_turn_view_test.dart
```

Expected: all page-turn component tests pass.

- [ ] **Step 6: Commit the handoff**

```powershell
git add -- lib/page_turn_view.dart test/page_turn_view_test.dart
git commit -m "fix: hand off overlapping pages without duplicates"
```

### Task 2: Verify novel overlap behavior

**Files:**
- Verify: `lib/text_paginator.dart`
- Verify: `lib/reader_screen.dart`
- Verify: `test/text_paginator_test.dart`
- Verify: `test/reader_screen_test.dart`

**Interfaces:**
- Consumes: `TextPage.displayStart`, paginator two-line overlap, and reader rendering from `displayStart`.
- Produces: unchanged two-line context with unchanged logical progress.

- [ ] **Step 1: Run overlap and reader regressions**

Run:

```powershell
flutter test test/text_paginator_test.dart --plain-name "next page repeats two visually wrapped lines"
flutter test test/reader_screen_test.dart --plain-name "page rendering repeats overlap without moving progress"
```

Expected: both tests pass.

- [ ] **Step 2: Run full verification**

Run:

```powershell
dart format --output=none --set-exit-if-changed lib/page_turn_view.dart test/page_turn_view_test.dart
flutter analyze
flutter test
```

Expected: formatting is unchanged, analysis reports no issues, and all tests
pass.

- [ ] **Step 3: Confirm final scope**

Run:

```powershell
git status -sb
git diff --check
git log -2 --oneline
```

Expected: the two-line overlap files are unchanged, the design and plan commits
remain, and only the approved page-handoff implementation commit is added.
