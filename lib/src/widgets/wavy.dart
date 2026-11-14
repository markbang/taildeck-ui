import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

/// Material 3 Expressive's indeterminate wavy line: a travelling sine wave
/// with a lighter track, 1.8 s per pass.
class WavyLine extends StatefulWidget {
  const WavyLine({
    super.key,
    this.color,
    this.height = 8,
    this.wavelength = 26,
    this.amplitude = 2.4,
  });

  final Color? color;
  final double height;
  final double wavelength;
  final double amplitude;

  @override
  State<WavyLine> createState() => _WavyLineState();
}

class _WavyLineState extends State<WavyLine>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.disableAnimations) {
      _controller
        ..stop()
        ..value = 0.35;
      return;
    }
    if (!_controller.isAnimating) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tint = widget.color ?? context.colorScheme.primary;
    return RepaintBoundary(
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _WavyLinePainter(
              phase: _controller.value * 2 * math.pi,
              tint: tint,
              wavelength: widget.wavelength,
              amplitude: widget.amplitude,
            ),
          ),
        ),
      ),
    );
  }
}

class _WavyLinePainter extends CustomPainter {
  _WavyLinePainter({
    required this.phase,
    required this.tint,
    required this.wavelength,
    required this.amplitude,
  });

  final double phase;
  final Color tint;
  final double wavelength;
  final double amplitude;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final track = _wave(size, mid, tint.withValues(alpha: 0.22));
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(track, stroke..color = tint.withValues(alpha: 0.22));

    // The active run travels rightwards across the track.
    final window = size.width * 0.38;
    final start =
        -window + (size.width + window) * ((phase / (2 * math.pi)) % 1);
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(start, 0, window, size.height));
    canvas.drawPath(_wave(size, mid, tint), stroke..color = tint);
    canvas.restore();
  }

  Path _wave(Size size, double mid, Color color) {
    final path = Path();
    for (double x = 0; x <= size.width; x += 2) {
      final y =
          mid + amplitude * math.sin((x / wavelength) * 2 * math.pi + phase);
      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path;
  }

  @override
  bool shouldRepaint(_WavyLinePainter old) =>
      old.phase != phase || old.tint != tint;
}
