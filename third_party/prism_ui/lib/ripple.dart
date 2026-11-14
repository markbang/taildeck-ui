import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Material's ink ripple: a circle that grows out of where a press landed,
/// drifting to the centre of the surface as it does, and fades away when the
/// press ends.
///
/// Timed as `material-ripple`'s `RippleAnimation`: the radius runs to the
/// farthest corner over 225 ms on `fastOutSlowIn`, the alpha fades in over
/// 75 ms and out over 150 ms, both linear, and the centre travels linearly
/// over the same 225 ms.
class PressRipple extends ChangeNotifier {
  PressRipple({required TickerProvider vsync}) {
    _grow = AnimationController(vsync: vsync, duration: expand)
      ..addListener(notifyListeners);
    _fade = AnimationController(vsync: vsync, duration: fadeIn)
      ..addListener(notifyListeners);
  }

  static const fadeIn = Duration(milliseconds: 75);
  static const expand = Duration(milliseconds: 225);
  static const fadeOut = Duration(milliseconds: 150);

  /// How far past the surface's own bounds a bounded ripple reaches, in dp.
  static const extraRadius = 10.0;

  late final AnimationController _grow;
  late final AnimationController _fade;
  Offset? _origin;
  bool _released = false;
  bool _still = false;

  Offset? get origin => _origin;

  /// Whether anything is left to paint.
  bool get visible =>
      _origin != null && (_fade.value > 0.002 || _grow.value < 1 || !_released);

  /// Follows the platform's reduce-motion setting: the ink then appears and
  /// leaves at once.
  set still(bool value) {
    if (value == _still) return;
    _still = value;
    if (value) {
      _grow
        ..stop()
        ..value = 1;
    }
  }

  void press(Offset origin) {
    _origin = origin;
    _released = false;
    if (_still) {
      _grow.value = 1;
      _fade.value = 1;
      return;
    }
    _grow
      ..duration = expand
      ..forward(from: 0);
    _fade
      ..duration = fadeIn
      ..forward(from: 0);
  }

  void release() {
    if (_origin == null || _released) return;
    _released = true;
    _fade
      ..duration = _still ? Duration.zero : fadeOut
      ..animateTo(0).whenCompleteOrCancel(() {
        if (_fade.value == 0) {
          _origin = null;
          notifyListeners();
        }
      });
  }

  void clear() {
    _origin = null;
    _released = true;
    _grow
      ..stop()
      ..value = 0;
    _fade
      ..stop()
      ..value = 0;
  }

  /// Paints the ink inside [bounds], with [color] already carrying the state
  /// layer's alpha.
  void paint(Canvas canvas, Rect bounds, Color color) {
    final origin = _origin;
    if (origin == null || color.a == 0) return;
    final alpha = _fade.value;
    if (alpha <= 0.002) return;
    final travel = _grow.value;
    final start = bounds.longestSide * 0.3;
    final end =
        (bounds.size).bottomRight(Offset.zero).distance / 2 + extraRadius;
    final radius =
        start + (end - start) * Curves.fastOutSlowIn.transform(travel);
    final center = Offset.lerp(origin, bounds.center, travel)!;
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = color.withValues(alpha: color.a * alpha),
    );
  }

  @override
  void dispose() {
    _grow.dispose();
    _fade.dispose();
    super.dispose();
  }
}

/// Repaints [child] whenever [ripple] moves, and clips the ink to [shape].
class RippleLayer extends StatelessWidget {
  const RippleLayer({
    super.key,
    required this.ripple,
    required this.color,
    this.shape,
    required this.child,
  });

  final PressRipple ripple;
  final Color color;
  final ShapeBorder? shape;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ripple,
      builder: (context, child) => CustomPaint(
        painter: _RipplePainter(ripple, color, shape),
        child: child,
      ),
      child: child,
    );
  }
}

class _RipplePainter extends CustomPainter {
  _RipplePainter(this.ripple, this.color, this.shape);

  final PressRipple ripple;
  final Color color;
  final ShapeBorder? shape;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.save();
    final shape = this.shape;
    if (shape != null) {
      canvas.clipPath(shape.getOuterPath(bounds));
    }
    ripple.paint(canvas, bounds, color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RipplePainter old) => true;
}

/// The ripple radius a press on [size] covers: half the diagonal plus a
/// little, as `getRippleEndRadius` computes it.
double rippleRadiusFor(Size size) =>
    math.sqrt(size.width * size.width + size.height * size.height) / 2 +
    PressRipple.extraRadius;
