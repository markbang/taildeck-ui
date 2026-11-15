import 'dart:async';

import 'package:flutter/widgets.dart';

import 'preview_env.dart';

/// Colours of the launch screen; the Android (colors.xml, launch_background),
/// iOS (LaunchScreen.storyboard) and desktop runners use the same values.
const splashBackground = Color(0xFF101214);
const splashMarkForeground = Color(0xFFE8EAED);
const splashMarkAccent = Color(0xFF5FD08A);

/// The launch mark: the 3x3 node grid alone, at the 118dp span Android 12's
/// splash icon draws, on the [splashBackground] of the window behind it.
class SplashMark extends StatelessWidget {
  const SplashMark({super.key, this.dotsSpan = 118});

  /// Width and height of the whole grid, dot edge to dot edge.
  final double dotsSpan;

  @override
  Widget build(BuildContext context) => CustomPaint(
    // The launcher grid spans 44 of the 56 units its icon canvas keeps, so the
    // paint box leaves half a dot of margin around the dots.
    size: Size.square(dotsSpan * 56 / 44),
    painter: _SplashMarkPainter(dotsSpan),
  );
}

class _SplashMarkPainter extends CustomPainter {
  const _SplashMarkPainter(this.dotsSpan);

  final double dotsSpan;

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
    // One launcher unit is a dot's radius here; the grid runs 38..70 around
    // its middle dot at 54.
    final unit = dotsSpan / 44;
    final center = size.center(Offset.zero);
    for (final (x, y, alpha, color) in _dots) {
      canvas.drawCircle(
        center + Offset((x - 54) * unit, (y - 54) * unit),
        6 * unit,
        Paint()..color = color.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SplashMarkPainter oldDelegate) =>
      oldDelegate.dotsSpan != dotsSpan;
}

/// Holds the launch screen over the app until the first route is decided, then
/// fades it out. The composition matches the platform splash (Android window
/// background, iOS LaunchScreen), so the hand-off has no blank frame.
class SplashGate extends StatefulWidget {
  const SplashGate({
    super.key,
    required this.child,
    this.until,
    this.maxWait = const Duration(milliseconds: 1500),
    this.dotsSpan = 118,
    this.dwell = const Duration(milliseconds: 80),
    this.fade = const Duration(milliseconds: 260),
  });

  final Widget child;

  /// The route decision, normally the backend's saved login. A slow node never
  /// reaches this: [maxWait] hands the splash over anyway.
  final Future<void>? until;
  final Duration maxWait;
  final double dotsSpan;
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
      if (mounted) unawaited(_hold());
    });
  }

  Future<void> _hold() async {
    final until = widget.until;
    if (until != null) {
      await until
          .timeout(widget.maxWait, onTimeout: () {})
          .catchError((Object _) {});
    }
    if (!mounted) return;
    _dwell = Timer(widget.dwell, () {
      if (!mounted) return;
      setState(() => _fading = true);
      _fade = Timer(widget.fade, () {
        if (mounted) setState(() => _showing = false);
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
                  child: Center(child: SplashMark(dotsSpan: widget.dotsSpan)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
