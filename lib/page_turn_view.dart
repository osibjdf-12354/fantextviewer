import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'models.dart';

class PageTurnView extends StatefulWidget {
  const PageTurnView({
    super.key,
    required this.index,
    required this.itemCount,
    required this.direction,
    this.tapOnly = false,
    this.animationEnabled = true,
    this.onInteractionStart,
    this.onInteractionEnd,
    required this.onPageChanged,
    required this.itemBuilder,
  });

  final int index;
  final int itemCount;
  final PageTurnDirection direction;
  final bool tapOnly;
  final bool animationEnabled;
  final VoidCallback? onInteractionStart;
  final VoidCallback? onInteractionEnd;
  final ValueChanged<int> onPageChanged;
  final IndexedWidgetBuilder itemBuilder;

  @override
  PageTurnViewState createState() => PageTurnViewState();
}

class PageTurnViewState extends State<PageTurnView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(
    vsync: this,
    value: 0,
    lowerBound: -1,
    upperBound: 1,
  );
  final Set<int> _activePointers = {};
  int? _pointer;
  Offset _downPosition = Offset.zero;
  Offset _lastPosition = Offset.zero;
  Duration _downTime = Duration.zero;
  Axis? _axis;
  double _dragProgress = 0;
  VelocityTracker? _velocityTracker;
  bool _cancelled = false;
  Size _size = Size.zero;
  bool _systemDisablesAnimations = false;

  bool get _animationEnabled =>
      widget.animationEnabled && !_systemDisablesAnimations;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disabled = MediaQuery.disableAnimationsOf(context);
    if (_systemDisablesAnimations == disabled) return;
    _systemDisablesAnimations = disabled;
    if (disabled) _resetInteraction();
  }

  @override
  void didUpdateWidget(PageTurnView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index ||
        oldWidget.itemCount != widget.itemCount ||
        oldWidget.direction != widget.direction ||
        oldWidget.tapOnly != widget.tapOnly ||
        oldWidget.animationEnabled != widget.animationEnabled) {
      _resetInteraction();
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  void _resetInteraction() {
    _progress.stop();
    _progress.value = 0;
    _pointer = null;
    _axis = null;
    _dragProgress = 0;
    _velocityTracker = null;
    _cancelled = false;
  }

  Future<bool> animateNext(Axis axis) async {
    if (_progress.isAnimating || !_canTurn(1)) return false;
    await _animateTurn(1, axis);
    return true;
  }

  void cancelTurn() => _resetInteraction();

  void _handleDown(PointerDownEvent event) {
    if (_activePointers.isEmpty) widget.onInteractionStart?.call();
    _activePointers.add(event.pointer);
    if (_activePointers.length > 1) {
      _cancelled = true;
      return;
    }
    if (_progress.isAnimating) return;
    _pointer = event.pointer;
    _downPosition = event.position;
    _lastPosition = event.position;
    _downTime = event.timeStamp;
    _axis = null;
    _dragProgress = 0;
    _cancelled = false;
    _velocityTracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
  }

  void _handleMove(PointerMoveEvent event) {
    if (event.pointer != _pointer || _cancelled || widget.tapOnly) return;
    _velocityTracker?.addPosition(event.timeStamp, event.position);
    final delta = event.position - _downPosition;
    if (_axis == null) {
      if (event.timeStamp - _downTime >= kLongPressTimeout) {
        _cancelled = true;
        return;
      }
      if (delta.distance < kTouchSlop) return;
      _axis = _chooseAxis(delta);
      if (_axis == null) {
        _cancelled = true;
        return;
      }
    }
    final movement = event.position - _lastPosition;
    _lastPosition = event.position;
    final value = _axis == Axis.horizontal ? movement.dx : movement.dy;
    final extent = _extent(_axis!);
    if (extent == 0) return;
    _dragProgress += value / extent;
    if (_dragProgress == 0) {
      _progress.value = 0;
      return;
    }
    final pageDelta = _dragProgress < 0 ? 1 : -1;
    if (!_canTurn(pageDelta)) {
      _progress.value = 0;
      return;
    }
    if (!_animationEnabled) return;
    _progress.value = _dragProgress.clamp(-1, 1).toDouble();
  }

  void _handleUp(PointerUpEvent event) {
    _activePointers.remove(event.pointer);
    _notifyInteractionEnd();
    if (event.pointer != _pointer) {
      if (_activePointers.isEmpty) _cancelled = false;
      return;
    }
    _velocityTracker?.addPosition(event.timeStamp, event.position);
    final elapsed = event.timeStamp - _downTime;
    final distance = (event.position - _downPosition).distance;
    final cancelled = _cancelled;
    final axis = _axis;
    final velocity = _velocityTracker?.getVelocity().pixelsPerSecond;
    final progress = _animationEnabled
        ? _progress.value
        : _dragProgress.clamp(-1, 1).toDouble();
    _pointer = null;
    _dragProgress = 0;
    _velocityTracker = null;
    if (_activePointers.isEmpty) _cancelled = false;

    if (cancelled) {
      unawaited(_animateBack());
      return;
    }
    if (axis == null) {
      if (widget.tapOnly &&
          elapsed < kLongPressTimeout &&
          distance < kTouchSlop) {
        final horizontal = widget.direction == PageTurnDirection.horizontal;
        final pageDelta = horizontal
            ? (event.localPosition.dx < _size.width / 2 ? -1 : 1)
            : (event.localPosition.dy < _size.height / 2 ? -1 : 1);
        unawaited(_animateTurn(pageDelta, _tapAxis));
      }
      return;
    }

    final axisVelocity = axis == Axis.horizontal ? velocity?.dx : velocity?.dy;
    final moved = progress.abs() >= .2;
    final flung =
        axisVelocity != null &&
        axisVelocity.abs() >= 600 &&
        axisVelocity.sign == progress.sign;
    if (!moved && !flung) {
      unawaited(_animateBack());
      return;
    }
    unawaited(_animateTurn(progress < 0 ? 1 : -1, axis));
  }

  void _handleCancel(PointerCancelEvent event) {
    _activePointers.remove(event.pointer);
    _notifyInteractionEnd();
    if (event.pointer != _pointer) {
      if (_activePointers.isEmpty) _cancelled = false;
      return;
    }
    _pointer = null;
    _dragProgress = 0;
    _velocityTracker = null;
    if (_activePointers.isEmpty) _cancelled = false;
    unawaited(_animateBack());
  }

  void _notifyInteractionEnd() {
    if (_activePointers.isEmpty) widget.onInteractionEnd?.call();
  }

  Axis? _chooseAxis(Offset delta) {
    return switch (widget.direction) {
      PageTurnDirection.horizontal =>
        delta.dx.abs() >= delta.dy.abs() ? Axis.horizontal : null,
      PageTurnDirection.vertical =>
        delta.dy.abs() >= delta.dx.abs() ? Axis.vertical : null,
      PageTurnDirection.both =>
        delta.dx.abs() >= delta.dy.abs() ? Axis.horizontal : Axis.vertical,
    };
  }

  Axis get _tapAxis => widget.direction == PageTurnDirection.horizontal
      ? Axis.horizontal
      : Axis.vertical;

  double _extent(Axis axis) =>
      axis == Axis.horizontal ? _size.width : _size.height;

  bool _canTurn(int pageDelta) {
    final target = widget.index + pageDelta;
    return target >= 0 && target < widget.itemCount;
  }

  Future<void> _animateTurn(int pageDelta, Axis axis) async {
    if (_progress.isAnimating) return;
    if (!_canTurn(pageDelta)) {
      await _animateBack();
      return;
    }
    if (!_animationEnabled) {
      widget.onPageChanged(widget.index + pageDelta);
      return;
    }
    setState(() => _axis = axis);
    final target = pageDelta > 0 ? -1.0 : 1.0;
    final fraction = (target - _progress.value).abs().clamp(.25, 1.0);
    await _progress.animateTo(
      target,
      duration: Duration(milliseconds: (180 * fraction).round()),
      curve: Curves.easeOutCubic,
    );
    if (!mounted) return;
    widget.onPageChanged(widget.index + pageDelta);
    if (!mounted) return;
    _progress.value = 0;
    setState(() => _axis = null);
  }

  Future<void> _animateBack() async {
    if (_progress.value != 0) {
      await _progress.animateTo(
        0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
      );
    }
    if (mounted) setState(() => _axis = null);
  }

  Offset _translation(Axis axis, double value) =>
      axis == Axis.horizontal ? Offset(value, 0) : Offset(0, value);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        final previous = widget.index > 0
            ? KeyedSubtree(
                key: ValueKey(widget.index - 1),
                child: widget.itemBuilder(context, widget.index - 1),
              )
            : null;
        final current = KeyedSubtree(
          key: ValueKey(widget.index),
          child: widget.itemBuilder(context, widget.index),
        );
        final next = widget.index + 1 < widget.itemCount
            ? KeyedSubtree(
                key: ValueKey(widget.index + 1),
                child: widget.itemBuilder(context, widget.index + 1),
              )
            : null;
        return Semantics(
          value: '${widget.index + 1}',
          increasedValue: next == null ? null : '${widget.index + 2}',
          decreasedValue: previous == null ? null : '${widget.index}',
          onIncrease: next == null
              ? null
              : () => unawaited(_animateTurn(1, _tapAxis)),
          onDecrease: previous == null
              ? null
              : () => unawaited(_animateTurn(-1, _tapAxis)),
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _handleDown,
            onPointerMove: _handleMove,
            onPointerUp: _handleUp,
            onPointerCancel: _handleCancel,
            child: ClipRect(
              child: AnimatedBuilder(
                animation: _progress,
                builder: (context, _) {
                  final axis = _axis ?? _tapAxis;
                  final extent = _extent(axis);
                  final progress = _progress.value;
                  final value = progress * extent;
                  final adjacent = progress < 0
                      ? next
                      : progress > 0
                      ? previous
                      : null;
                  final adjacentStart = progress < 0 ? extent : -extent;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      if (adjacent != null)
                        Transform.translate(
                          offset: _translation(axis, adjacentStart + value),
                          child: adjacent,
                        ),
                      Transform.translate(
                        offset: _translation(axis, value),
                        child: current,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
