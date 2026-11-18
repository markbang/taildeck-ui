import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/context.dart';

/// Makes a widget pressable: tap, hover, focus and keyboard activation, with
/// the plain state layer [overlay] paints over [fill] inside [shape]. A widget
/// that shows those states itself leaves [overlay] null and listens.
class PressRegion extends StatefulWidget {
  const PressRegion({
    super.key,
    this.onTap,
    this.onHover,
    this.onPressedChanged,
    this.onFocusChange,
    this.shape,
    this.fill,
    this.overlay,
    this.hoverColor,
    this.canRequestFocus = true,
    this.excludeFromSemantics = false,
    this.enableFeedback = true,
    this.mouseCursor,
    required this.child,
  });

  final VoidCallback? onTap;
  final ValueChanged<bool>? onHover;
  final ValueChanged<bool>? onPressedChanged;
  final ValueChanged<bool>? onFocusChange;
  final ShapeBorder? shape;
  final Color? fill;
  final WidgetStateProperty<Color?>? overlay;

  /// Replaces the hover of [overlay].
  final Color? hoverColor;
  final bool canRequestFocus;
  final bool excludeFromSemantics;
  final bool enableFeedback;

  /// Defaults to a click cursor while [onTap] is set.
  final MouseCursor? mouseCursor;
  final Widget child;

  /// Shows keyboard and remote focus only.
  static const focusOverlay = _StateOverlay(hovered: false);

  /// Shows a hover and keyboard or remote focus.
  static const hoverOverlay = _StateOverlay(hovered: true);

  /// [hoverOverlay] with a press too, which [Brightness] decides the look of.
  static const pressOverlay = _StateOverlay(hovered: true, pressed: true);

  @override
  State<PressRegion> createState() => _PressRegionState();
}

/// The grey a held row or menu item lays over its whole background, as a
/// grouped table cell highlights on iOS.
Color pressHighlightOf(Brightness brightness) => brightness == Brightness.dark
    ? const Color(0x40CCCCCC)
    : const Color(0x66BCBCBC);

/// Resolved against the region's brightness, which [WidgetStateProperty] has no
/// way to ask for; see [_PressRegionState._overlayColor].
class _StateOverlay implements WidgetStateProperty<Color?> {
  const _StateOverlay({required this.hovered, this.pressed = false});

  final bool hovered;
  final bool pressed;

  @override
  Color? resolve(Set<WidgetState> states) => null;

  Color? resolveFor(Set<WidgetState> states, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    if (pressed && states.contains(WidgetState.pressed)) {
      return pressHighlightOf(brightness);
    }
    if (states.contains(WidgetState.focused)) {
      return dark ? const Color(0x1FFFFFFF) : const Color(0x1F000000);
    }
    if (hovered && states.contains(WidgetState.hovered)) {
      return dark ? const Color(0x0AFFFFFF) : const Color(0x0A000000);
    }
    return null;
  }
}

class _PressRegionState extends State<PressRegion> {
  static const _overlayFade = Duration(milliseconds: 50);

  late final _actions = <Type, Action<Intent>>{
    ActivateIntent: CallbackAction<ActivateIntent>(
      onInvoke: (_) => _activate(),
    ),
    ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
      onInvoke: (_) => _activate(),
    ),
  };
  final _states = <WidgetState>{};
  bool _downInThisEvent = false;

  bool get _enabled => widget.onTap != null;

  void _activate() {
    if (widget.enableFeedback) {
      Feedback.forTap(context);
    }
    widget.onTap?.call();
  }

  void _setState(WidgetState state, bool on) {
    final changed = on ? _states.add(state) : _states.remove(state);
    if (changed && widget.overlay != null) {
      setState(() {});
    }
  }

  void _setPressed(bool pressed) {
    _setState(WidgetState.pressed, pressed);
    widget.onPressedChanged?.call(pressed);
  }

  void _pressDown() {
    _setPressed(true);
    _downInThisEvent = true;
    scheduleMicrotask(() => _downInThisEvent = false);
  }

  // A tap too quick for a scroll view to let its press through reports down
  // and up together; the highlight still shows for a frame before it fades.
  void _pressUp() {
    if (!_downInThisEvent) {
      _setPressed(false);
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) _setPressed(false);
    });
  }

  Color? _overlayColor(BuildContext context) {
    final hoverColor = widget.hoverColor;
    if (hoverColor != null &&
        _states.length == 1 &&
        _states.contains(WidgetState.hovered)) {
      return hoverColor;
    }
    return switch (widget.overlay) {
      final _StateOverlay overlay => overlay.resolveFor(
        _states,
        context.colorScheme.brightness,
      ),
      final overlay? => overlay.resolve(_states),
      null => null,
    };
  }

  Widget _painted(BuildContext context) {
    if (widget.overlay == null) {
      if (widget.fill == null) {
        return widget.child;
      }
      return DecoratedBox(
        decoration: ShapeDecoration(
          color: widget.fill,
          shape: widget.shape ?? const RoundedSuperellipseBorder(),
        ),
        child: widget.child,
      );
    }
    final shape = widget.shape ?? const RoundedSuperellipseBorder();
    final overlay = TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: _overlayColor(context) ?? const Color(0x00000000)),
      // A press shows at once; only its release fades.
      duration: _states.contains(WidgetState.pressed)
          ? Duration.zero
          : _overlayFade,
      builder: (context, color, child) =>
          CustomPaint(painter: _OverlayPainter(color, shape), child: child),
      child: widget.child,
    );
    return widget.fill == null
        ? overlay
        : DecoratedBox(
            decoration: ShapeDecoration(color: widget.fill, shape: shape),
            child: overlay,
          );
  }

  @override
  Widget build(BuildContext context) {
    final detector = FocusableActionDetector(
      actions: _actions,
      enabled: _enabled,
      onFocusChange: (focused) {
        _setState(WidgetState.focused, focused);
        widget.onFocusChange?.call(focused);
      },
      mouseCursor:
          widget.mouseCursor ??
          (_enabled ? SystemMouseCursors.click : MouseCursor.defer),
      onShowHoverHighlight: (hovered) {
        _setState(WidgetState.hovered, hovered);
        widget.onHover?.call(hovered);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTapDown: _enabled ? (_) => _pressDown() : null,
        onTapUp: _enabled ? (_) => _pressUp() : null,
        onTapCancel: _enabled ? () => _setPressed(false) : null,
        onTap: _enabled ? _activate : null,
        child: _painted(context),
      ),
    );
    return Semantics(
      onTap: widget.excludeFromSemantics || !_enabled ? null : _activate,
      child: widget.canRequestFocus ? detector : ExcludeFocus(child: detector),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  const _OverlayPainter(this.color, this.shape);

  final Color? color;
  final ShapeBorder shape;

  @override
  void paint(Canvas canvas, Size size) {
    final color = this.color;
    if (color == null || color.a == 0) {
      return;
    }
    shape.paintInterior(canvas, Offset.zero & size, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_OverlayPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.shape != shape;
}
