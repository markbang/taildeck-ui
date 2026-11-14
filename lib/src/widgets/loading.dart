import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';


/// One of the shapes the Material 3 loading indicator morphs through, written
/// as a polar curve so a morph between two of them is a lerp of five numbers.
class LoadingShape {
  const LoadingShape({
    this.lobes = 0,
    this.amplitude = 0,
    this.exponent = 2,
    this.width = 1,
    this.height = 1,
  });

  /// Bumps around the circle; 0 is a plain round or oval shape.
  final double lobes;
  final double amplitude;

  /// 2 is an ellipse, higher makes the sides flatter, as [width] and [height]
  /// set the extremes.
  final double exponent;
  final double width;
  final double height;

  /// Material's indeterminate sequence: burst, cookie9, pentagon, pill, sunny,
  /// cookie4, oval (`LoadingIndicatorDefaults.IndeterminateIndicatorPolygons`).
  static const sequence = [
    LoadingShape(lobes: 12, amplitude: 0.26, exponent: 1.4),
    LoadingShape(lobes: 9, amplitude: 0.11),
    LoadingShape(lobes: 5, amplitude: 0.2, exponent: 1.5),
    LoadingShape(exponent: 4, height: 0.62),
    LoadingShape(lobes: 12, amplitude: 0.18, exponent: 1.6),
    LoadingShape(lobes: 4, amplitude: 0.13),
    LoadingShape(height: 0.8),
  ];

  static const circle = LoadingShape();

  static LoadingShape lerp(LoadingShape a, LoadingShape b, double t) =>
      LoadingShape(
        lobes: a.lobes + (b.lobes - a.lobes) * t,
        amplitude: a.amplitude + (b.amplitude - a.amplitude) * t,
        exponent: a.exponent + (b.exponent - a.exponent) * t,
        width: a.width + (b.width - a.width) * t,
        height: a.height + (b.height - a.height) * t,
      );

  double radiusAt(double angle) {
    final cos = math.cos(angle).abs();
    final sin = math.sin(angle).abs();
    final base = math.pow(
      math.pow(cos / width, exponent) + math.pow(sin / height, exponent),
      -1 / exponent,
    );
    return base * (1 + amplitude * math.cos(lobes * angle));
  }

  Path pathIn(Size size) {
    const steps = 180;
    final center = size.center(Offset.zero);
    var longest = 0.0;
    for (var i = 0; i < steps; i++) {
      longest = math.max(longest, radiusAt(2 * math.pi * i / steps));
    }
    final scale = size.shortestSide / 2 / longest;
    final path = Path();
    for (var i = 0; i < steps; i++) {
      final angle = 2 * math.pi * i / steps;
      final point =
          center +
          Offset(math.cos(angle), math.sin(angle)) * (radiusAt(angle) * scale);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }
}

/// Material 3 Expressive's loading indicator: a dot that morphs through seven
/// shapes, a quarter turn per morph, inside a slow 4.666 s spin.
///
/// Kotlin draws it as `LoadingIndicator` / `ContainedLoadingIndicator`
/// (`material3/LoadingIndicator.kt`): a morph every 650 ms on a
/// `spring(0.6, 200, visibilityThreshold = 0.1)`, rotated by the morph's
/// progress plus a quarter turn each time.
class LoadingIndicator extends StatefulWidget {
  const LoadingIndicator({
    super.key,
    this.size = 24,
    this.color,
    this.contained = false,
    this.progress,
    this.semanticLabel,
  });

  /// The container's side; the dot takes [activeFraction] of it.
  final double size;

  /// Defaults to the primary color, or the container's content color when
  /// [contained].
  final Color? color;
  final bool contained;

  /// A determinate morph from the circle to the burst, as the pull-to-refresh
  /// indicator shows while pulled.
  final double? progress;

  final String? semanticLabel;

  /// The active dot against the container, from `LoadingIndicatorTokens`.
  static const activeFraction = 38 / 48;

  @override
  State<LoadingIndicator> createState() => _LoadingIndicatorState();
}

class _LoadingIndicatorState extends State<LoadingIndicator>
    with TickerProviderStateMixin {
  static const _morphInterval = Duration(milliseconds: 650);
  static const _spin = Duration(milliseconds: 4666);
  static const _morph = Duration(milliseconds: 350);

  late final _cycle = AnimationController(vsync: this, duration: _morphInterval)
    ..addStatusListener(_onCycle);
  late final _turn = AnimationController(vsync: this, duration: _spin);
  final _morphCurve = SpringCurve(
    SpringDescription.withDampingRatio(mass: 1, stiffness: 200, ratio: 0.6),
    seconds: _morph.inMilliseconds / 1000,
  );
  int _index = 0;
  int _quarterTurns = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant LoadingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.progress != widget.progress) _sync();
  }

  void _sync() {
    final animate = widget.progress == null && !context.disableAnimations;
    if (!animate) {
      _cycle.stop();
      _turn.stop();
      return;
    }
    if (!_cycle.isAnimating) _cycle.repeat();
    if (!_turn.isAnimating) _turn.repeat();
  }

  // Compose starts the next morph every 650 ms and turns the shape a quarter
  // each time.
  void _onCycle(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _index = (_index + 1) % LoadingShape.sequence.length;
    _quarterTurns++;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cycle.dispose();
    _turn.dispose();
    super.dispose();
  }

  double get _morphProgress {
    if (widget.progress != null) return widget.progress!.clamp(0.0, 1.0);
    if (context.disableAnimations) return 1;
    return _morphCurve.transform(_cycle.value).clamp(0.0, 1.0);
  }

  LoadingShape get _shape {
    final progress = widget.progress;
    if (progress != null) {
      return LoadingShape.lerp(
        LoadingShape.circle,
        LoadingShape.sequence.first,
        progress.clamp(0.0, 1.0),
      );
    }
    final sequence = LoadingShape.sequence;
    return LoadingShape.lerp(
      sequence[_index],
      sequence[(_index + 1) % sequence.length],
      _morphProgress,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final dot =
        widget.color ??
        (widget.contained ? scheme.onPrimaryContainer : scheme.primary);
    final container = widget.contained
        ? scheme.primaryContainer
        : const Color(0x00000000);
    final progress = widget.progress;
    final box = SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: Listenable.merge([_cycle, _turn]),
        builder: (context, _) {
          final rotation = progress != null
              ? -progress.clamp(0.0, 1.0) * math.pi
              : _morphProgress * math.pi / 2 +
                    _quarterTurns * math.pi / 2 +
                    _turn.value * 2 * math.pi;
          final active = widget.size * LoadingIndicator.activeFraction;
          return DecoratedBox(
            decoration: BoxDecoration(color: container, shape: BoxShape.circle),
            child: Center(
              child: Transform.rotate(
                angle: rotation,
                child: CustomPaint(
                  size: Size.square(active),
                  painter: _LoadingPainter(shape: _shape, color: dot),
                ),
              ),
            ),
          );
        },
      ),
    );
    final label = widget.semanticLabel;
    if (label != null) {
      return Semantics(
        label: label,
        child: ExcludeSemantics(child: box),
      );
    }
    return ExcludeSemantics(child: box);
  }
}

class _LoadingPainter extends CustomPainter {
  _LoadingPainter({required this.shape, required this.color});

  final LoadingShape shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(shape.pathIn(size), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_LoadingPainter old) => true;
}
