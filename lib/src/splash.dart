import 'dart:async';

import 'package:flutter/widgets.dart';

import 'preview_env.dart';

/// Colours of the launch screen; the Android (colors.xml, launch_background),
/// iOS (LaunchScreen.storyboard) and desktop runners use the same values.
const splashBackground = Color(0xFF101214);
const splashMarkBackground = Color(0xFF15181B);
const splashMarkForeground = Color(0xFFE8EAED);
const splashMarkAccent = Color(0xFF5FD08A);

/// The launcher mark, drawn at [size] like the adaptive icon: a disc of
/// [splashMarkBackground] with the 3x3 node grid scaled to its 72dp crop.
class SplashMark extends StatelessWidget {
  const SplashMark({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: const _SplashMarkPainter());
}

class _SplashMarkPainter extends CustomPainter {
  const _SplashMarkPainter();

  // Positions and radius in the 108dp adaptive-icon viewport.
  static const _dots = [
    (38.0, 38.0, 1.0, splashMarkForeground),
    (54.0, 38.0, 1.0, splashMarkForeground),
    (70.0, 38.0, 0.35, splashMarkForeground),
    (38.0, 54.0, 0.35, splashMarkForeground),
    (54.0, 54.0, 1.0, splashMarkAccent),
    (70.0, 54.0, 1.0, splashMarkForeground),
    (38.0, 70.0, 0.35, splashMarkForeground),
    (54.0, 70.0, 1.0, splashMarkForeground),
    (70.0, 70.0, 0.35, splashMarkForeground),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 72; // the 108dp viewport cut to its 72dp crop
    canvas.drawCircle(
      size.center(Offset.zero),
      size.width / 2,
      Paint()..color = splashMarkBackground,
    );
    for (final (x, y, alpha, color) in _dots) {
      canvas.drawCircle(
        Offset((x - 18) * unit, (y - 18) * unit),
        6 * unit,
        Paint()..color = color.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SplashMarkPainter oldDelegate) => false;
}

/// Holds the launch screen over the app until the first frame is painted, then
/// fades it out. The composition matches the platform splash (Android window
/// background, iOS LaunchScreen), so the hand-off has no blank frame.
class SplashGate extends StatefulWidget {
  const SplashGate({
    super.key,
    required this.child,
    this.iconSize = 96,
    this.dwell = const Duration(milliseconds: 80),
    this.fade = const Duration(milliseconds: 260),
  });

  final Widget child;
  final double iconSize;
  final Duration dwell;
  final Duration fade;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  // Preview builds ('?splash=0') and tests take the app as it is.
  bool _showing = previewParam('splash') != '0';
  bool _fading = false;
  Timer? _dwell;
  Timer? _fade;

  @override
  void initState() {
    super.initState();
    if (!_showing) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _dwell = Timer(widget.dwell, () {
        if (!mounted) return;
        setState(() => _fading = true);
        _fade = Timer(widget.fade, () {
          if (mounted) setState(() => _showing = false);
        });
      });
    });
  }

  @override
  void dispose() {
    _dwell?.cancel();
    _fade?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The child keeps its slot so removing the splash does not rebuild the app
    // underneath; the overlay is decoration and lets input through.
    return Stack(
      children: [
        widget.child,
        if (_showing)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _fading ? 0 : 1,
                duration: widget.fade,
                curve: Curves.easeOut,
                child: ColoredBox(
                  color: splashBackground,
                  child: Center(child: SplashMark(size: widget.iconSize)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
