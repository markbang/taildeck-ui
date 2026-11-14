import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import '../motion.dart';

/// Material's snackbar, as the Kotlin app reports finished actions: it slides
/// up over the page, waits, and slides away.
void showMotionSnack(BuildContext context, String text) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _MotionSnack(
      text: text,
      onDone: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );
  overlay.insert(entry);
}

class _MotionSnack extends StatefulWidget {
  const _MotionSnack({required this.text, required this.onDone});

  final String text;
  final VoidCallback onDone;

  @override
  State<_MotionSnack> createState() => _MotionSnackState();
}

class _MotionSnackState extends State<_MotionSnack>
    with SingleTickerProviderStateMixin {
  static const _wait = Duration(milliseconds: 3500);

  late final _controller = AnimationController(vsync: this);
  late final _opacity = CurvedAnimation(
    parent: _controller,
    curve: fade.curve,
    reverseCurve: fadeFast.curve,
  );
  late final _offset =
      Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(
        CurvedAnimation(
          parent: _controller,
          curve: slowSpatial.curve,
          reverseCurve: slowSpatial.curve,
        ),
      );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener(_onStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.isAnimating || _timer != null) return;
    final still = context.disableAnimations;
    _controller
      ..duration = still ? Duration.zero : slowSpatial.duration
      ..reverseDuration = still ? Duration.zero : fadeFast.duration;
    if (still) {
      _controller.value = 1;
      _timer = Timer(_wait, widget.onDone);
      return;
    }
    _controller.forward(from: 0);
    _timer = Timer(_wait, () {
      if (mounted) _controller.reverse();
    });
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) {
      _timer?.cancel();
      widget.onDone();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Positioned(
      left: 16,
      right: 16,
      bottom: 16 + context.bottomInset,
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: FadeTransition(
            opacity: _opacity,
            child: SlideTransition(
              position: _offset,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: scheme.inverseSurface,
                    shape: AppShape.all(AppCorner.md),
                    shadows: [
                      BoxShadow(
                        color: scheme.shadow.withValues(alpha: 0.24),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Text(
                      widget.text,
                      style: AppTextStyle.body
                          .of(context)
                          .copyWith(color: scheme.onInverseSurface),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
