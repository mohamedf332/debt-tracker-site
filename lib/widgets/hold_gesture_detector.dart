import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';

/// Finger-down -> long-press detector shared by the person rows and the
/// project chips, so both long presses behave and feel exactly the same.
///
///  * a progress fill runs across the pressed surface over [kLongPressTimeout];
///  * moving more than 8px retracts it (the gesture is a drag, not a menu);
///  * when the fill completes the device buzzes once;
///  * on release a completed hold opens the menu, a short still press taps.
class HoldGestureDetector extends StatefulWidget {
  const HoldGestureDetector({
    super.key,
    required this.onTap,
    required this.onLongPress,
    required this.child,
    this.progressColor = AppColors.primary,
    this.progressClip,
  });

  final VoidCallback onTap;
  final ValueChanged<Offset> onLongPress;
  final Widget child;

  /// Tint of the hold fill. Callers pick a colour that stays visible on their
  /// own background (the cyan chip needs something darker than cyan).
  final Color progressColor;

  /// Clips the fill to the child's silhouette. Needed for rounded chips so the
  /// bottom hairline does not spill past the corners.
  final BorderRadius? progressClip;

  @override
  State<HoldGestureDetector> createState() => _HoldGestureDetectorState();
}

class _HoldGestureDetectorState extends State<HoldGestureDetector>
    with SingleTickerProviderStateMixin {
  /// Movement above which a held press is a drag rather than a menu trigger.
  /// Matches the ~6-8px discriminator required by the spec.
  static const double _menuMoveTolerance = 8.0;
  static const Duration _retractDuration = Duration(milliseconds: 120);

  late final AnimationController _hold =
      AnimationController(vsync: this, duration: kLongPressTimeout);

  Duration? _downTime;
  Offset _downPosition = Offset.zero;
  double _maxDistance = 0;
  bool _buzzed = false;

  @override
  void initState() {
    super.initState();
    _hold.addStatusListener(_handleHoldStatus);
  }

  @override
  void dispose() {
    _hold.removeStatusListener(_handleHoldStatus);
    _hold.dispose();
    super.dispose();
  }

  void _handleHoldStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _buzzed) return;
    if (_downTime == null || _maxDistance > _menuMoveTolerance) return;
    _buzzed = true;
    HapticFeedback.vibrate();
  }

  /// The row can be unmounted while the finger is still down (the reorder
  /// drag lifts it out of the list), so every handler has to tolerate events
  /// arriving after [dispose] has torn the controller down.
  void _handleDown(PointerDownEvent event) {
    if (!mounted) return;
    _downTime = event.timeStamp;
    _downPosition = event.position;
    _maxDistance = 0;
    _buzzed = false;
    _hold.forward(from: 0);
  }

  void _handleMove(PointerMoveEvent event) {
    if (!mounted || _downTime == null) return;
    final distance = (event.position - _downPosition).distance;
    if (distance > _maxDistance) _maxDistance = distance;
    // The hold is no longer valid: let the fill retreat instead of freezing
    // mid-way. Later moves are no-ops because the controller is already going
    // back to 0.
    if (_maxDistance > _menuMoveTolerance &&
        _hold.status == AnimationStatus.forward) {
      _hold.animateTo(0, duration: _retractDuration, curve: Curves.easeOut);
    }
  }

  void _retract() {
    if (_hold.value == 0) return;
    _hold.animateTo(0, duration: _retractDuration, curve: Curves.easeOut);
  }

  void _handleUp(PointerUpEvent event) {
    if (!mounted) return;
    _hold.stop();
    final downTime = _downTime;
    _downTime = null;
    _retract();
    if (downTime == null) return;

    final held = event.timeStamp - downTime;
    if (held >= kLongPressTimeout) {
      if (_maxDistance <= _menuMoveTolerance) {
        widget.onLongPress(event.position);
      }
    } else if (_maxDistance <= kTouchSlop) {
      widget.onTap();
    }
  }

  void _handleCancel(PointerCancelEvent event) {
    if (!mounted) return;
    _hold.stop();
    _downTime = null;
    _retract();
  }

  @override
  Widget build(BuildContext context) {
    final Widget body = CustomPaint(
      // Painted above the child and repainted straight off the controller, so
      // the tile/chip subtree is never rebuilt while the finger is held.
      foregroundPainter: _HoldProgressPainter(_hold, widget.progressColor),
      child: widget.child,
    );

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _handleDown,
      onPointerMove: _handleMove,
      onPointerUp: _handleUp,
      onPointerCancel: _handleCancel,
      child: widget.progressClip == null
          ? body
          : ClipRRect(borderRadius: widget.progressClip!, child: body),
    );
  }
}

class _HoldProgressPainter extends CustomPainter {
  _HoldProgressPainter(this.animation, this.color) : super(repaint: animation);

  final Animation<double> animation;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    if (t <= 0 || size.isEmpty) return;

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = color.withValues(alpha: 0.10 * t),
    );

    const double barHeight = 3;
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - barHeight, size.width * t, barHeight),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_HoldProgressPainter oldDelegate) =>
      oldDelegate.animation != animation || oldDelegate.color != color;
}
