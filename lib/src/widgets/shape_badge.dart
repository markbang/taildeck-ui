import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import '../motion.dart';

/// A Material Shapes polygon as the Kotlin app uses it, as a lobed blob:
/// [lobes] around the circle, each lifted by [amplitude] of the radius.
///
/// Compose morphs between `RoundedPolygon`s; a polar radius makes the same
/// morph continuous, so the badge keeps one path while it changes shape.
class BlobShape {
  const BlobShape(this.lobes, this.amplitude);

  final double lobes;
  final double amplitude;

  static const cookie4 = BlobShape(4, 0.045);
  static const cookie6 = BlobShape(6, 0.06);
  static const cookie7 = BlobShape(7, 0.07);
  static const cookie9 = BlobShape(9, 0.075);
  static const softBurst = BlobShape(12, 0.16);

  static BlobShape lerp(BlobShape a, BlobShape b, double t) => BlobShape(
    a.lobes + (b.lobes - a.lobes) * t,
    a.amplitude + (b.amplitude - a.amplitude) * t,
  );
}

/// A filled polygon behind [child] that morphs to a new [shape] with the slow
/// spatial spring, fades its [color] with the default effects one, and turns
/// once every 9 s while [spin] is set (Kotlin's `ShapeBadge`).
class ShapeBadge extends StatefulWidget {
  const ShapeBadge({
    super.key,
    required this.shape,
    required this.color,
    this.size = 40,
    this.spin = false,
    this.child,
  });

  final BlobShape shape;
  final Color color;
  final double size;
  final bool spin;
  final Widget? child;

  @override
  State<ShapeBadge> createState() => _ShapeBadgeState();
}

class _ShapeBadgeState extends State<ShapeBadge> with TickerProviderStateMixin {
  late final _morph = AnimationController(vsync: this, value: 1);
  late BlobShape _from = widget.shape;
  late BlobShape _to = widget.shape;
  late final _color = AnimationController(vsync: this, value: 1);
  late Color _colorFrom = widget.color;
  late Color _colorTo = widget.color;
  late final _turn = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSpin();
  }

  @override
  void didUpdateWidget(covariant ShapeBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shape != widget.shape) {
      _from = BlobShape.lerp(_from, _to, _morph.value);
      _to = widget.shape;
      _morph
        ..duration = motionDuration(context, slowSpatial)
        ..forward(from: 0);
    }
    if (oldWidget.color != widget.color) {
      _colorFrom = Color.lerp(_colorFrom, _colorTo, _color.value)!;
      _colorTo = widget.color;
      _color
        ..duration = motionDuration(context, fade)
        ..forward(from: 0);
    }
    if (oldWidget.spin != widget.spin) _syncSpin();
  }

  void _syncSpin() {
    if (!widget.spin || context.disableAnimations) {
      _turn
        ..stop()
        ..value = 0;
      return;
    }
    if (!_turn.isAnimating) _turn.repeat();
  }

  @override
  void dispose() {
    _morph.dispose();
    _color.dispose();
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = context.disableAnimations;
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: Listenable.merge([_morph, _color, _turn]),
        builder: (context, child) {
          final morph = still
              ? 1.0
              : (slowSpatial.curve.transform(_morph.value)).clamp(0.0, 1.0);
          final color = Color.lerp(
            _colorFrom,
            _colorTo,
            still ? 1 : fade.curve.transform(_color.value),
          )!;
          return Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: Transform.rotate(
                  angle: _turn.value * 2 * math.pi,
                  child: CustomPaint(
                    painter: _BlobPainter(
                      BlobShape.lerp(_from, _to, morph),
                      color,
                    ),
                  ),
                ),
              ),
              ?child,
            ],
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _BlobPainter extends CustomPainter {
  _BlobPainter(this.shape, this.color);

  final BlobShape shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    const steps = 144;
    final path = Path();
    for (var i = 0; i <= steps; i++) {
      final angle = 2 * math.pi * i / steps;
      final r = radius * (1 + shape.amplitude * math.cos(shape.lobes * angle));
      final point = center + Offset(math.cos(angle), math.sin(angle)) * r;
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BlobPainter old) =>
      old.color != color ||
      old.shape.lobes != shape.lobes ||
      old.shape.amplitude != shape.amplitude;
}
