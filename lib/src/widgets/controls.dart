import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../l10n.dart';
import '../motion.dart';
import 'loading.dart';

/// Material 3's pressed shape: a pill's corners squash to 8 dp while held, on
/// Compose's default effects spring (230 ms, no bounce). Clipping keeps the
/// child's own fill inside the narrower shape.
class PressSquish extends StatefulWidget {
  const PressSquish({
    super.key,
    required this.shape,
    required this.pressed,
    required this.child,
  });

  final ShapeBorder shape;
  final bool pressed;
  final Widget child;

  @override
  State<PressSquish> createState() => _PressSquishState();
}

class _PressSquishState extends State<PressSquish>
    with SingleTickerProviderStateMixin {
  static const _pressedCorner = 8.0;

  late final _controller = AnimationController(
    vsync: this,
    value: widget.pressed ? 1 : 0,
  );
  late final _curve = CurvedAnimation(parent: _controller, curve: fade.curve);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = motionDuration(context, fade);
  }

  @override
  void didUpdateWidget(covariant PressSquish oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pressed == widget.pressed) return;
    widget.pressed ? _controller.forward() : _controller.reverse();
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 44.0;
        return AnimatedBuilder(
          animation: _curve,
          builder: (context, child) {
            final t = _curve.value;
            if (t == 0) return child!;
            final pill = height / 2;
            final shape = RoundedSuperellipseBorder(
              borderRadius: BorderRadius.all(
                Radius.circular(pill + (_pressedCorner - pill) * t),
              ),
            );
            return ClipPath(
              clipper: ShapeBorderClipper(shape: shape),
              child: child,
            );
          },
          child: widget.child,
        );
      },
    );
  }
}

/// A pressable surface with the state layer [PressRegion] leaves out by
/// default: a tint on press and focus, and Material's pressed shape for
/// surfaces drawn as buttons.
class TapFeedback extends StatefulWidget {
  const TapFeedback({
    super.key,
    this.onTap,
    this.shape,
    this.fill,
    this.squish = false,
    this.enabled = true,
    this.excludeFromSemantics = false,
    this.semanticsLabel,
    required this.child,
  });

  final VoidCallback? onTap;
  final ShapeBorder? shape;
  final Color? fill;
  final bool squish;
  final bool enabled;
  final bool excludeFromSemantics;
  final String? semanticsLabel;
  final Widget child;

  @override
  State<TapFeedback> createState() => _TapFeedbackState();
}

class _TapFeedbackState extends State<TapFeedback> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && widget.onTap != null;
    final shape = widget.shape ?? const RoundedSuperellipseBorder();
    final content = widget.squish
        ? PressSquish(
            shape: shape,
            pressed: _pressed && enabled,
            child: widget.child,
          )
        : widget.child;
    final region = PressRegion(
      onTap: enabled ? widget.onTap : null,
      onPressedChanged: widget.squish ? _setPressed : null,
      shape: shape,
      fill: widget.fill,
      overlay: PressRegion.pressOverlay,
      excludeFromSemantics: widget.excludeFromSemantics,
      child: content,
    );
    final label = widget.semanticsLabel;
    if (label == null) return region;
    return Semantics(
      container: true,
      label: label,
      button: true,
      enabled: enabled,
      excludeSemantics: true,
      child: region,
    );
  }
}

/// A filled button that swaps its label for a spinner and disables itself
/// while [loading], then hands the result back to the caller's notice.
class LoadingButton extends StatelessWidget {
  const LoadingButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.glyph,
    this.style,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final Glyph? glyph;
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: label,
      value: loading ? l10n.pleaseWait : null,
      enabled: onPressed != null && !loading,
      excludeSemantics: true,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        style: style,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                LoadingIndicator(size: 18, semanticLabel: l10n.pleaseWait)
              else if (glyph != null)
                GlyphIcon(glyph!, size: 18),
              if (loading || glyph != null) const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A grouped card whose rows fade and collapse in and out as they are added
/// or removed; the separator belongs to the row above it, so it leaves with
/// the row instead of being left behind.
class AnimatedGroupCard extends StatefulWidget {
  const AnimatedGroupCard({
    super.key,
    required this.children,
    this.dividerInset = 60,
  });

  final List<Widget> children;
  final double dividerInset;

  @override
  State<AnimatedGroupCard> createState() => _AnimatedGroupCardState();
}

class _AnimatedGroupCardState extends State<AnimatedGroupCard>
    with TickerProviderStateMixin {
  late final _transitions = EntryTransitions<Key>(
    vsync: this,
    onLeft: _handleLeft,
  );
  late List<Widget> _entries = _rows(widget.children);

  List<Widget> _rows(List<Widget> children) => [
    for (var i = 0; i < children.length; i++)
      _CardRow(
        key: children[i].key ?? ValueKey('card-row-$i'),
        first: i == 0,
        inset: widget.dividerInset,
        child: children[i],
      ),
  ];

  @override
  void didUpdateWidget(covariant AnimatedGroupCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _rows(widget.children);
    final merged = _transitions.sync(
      _entries,
      next,
      (row) => row.key!,
      motionDuration(context, placement),
    );
    _entries = _keepPlace(_entries, next, merged);
  }

  /// A leaving row collapses where it was, not at the end of the card.
  List<Widget> _keepPlace(
    List<Widget> previous,
    List<Widget> next,
    List<Widget> merged,
  ) {
    final nextKeys = {for (final row in next) row.key};
    final leaving = [
      for (final row in merged)
        if (!nextKeys.contains(row.key)) row,
    ];
    final before = {
      for (var i = 0; i < previous.length; i++) previous[i].key: i,
    };
    final ordered = <Widget>[];
    var index = 0;
    for (final row in next) {
      final at = before[row.key] ?? previous.length;
      while (index < leaving.length && (before[leaving[index].key] ?? 0) < at) {
        ordered.add(leaving[index++]);
      }
      ordered.add(row);
    }
    ordered.addAll(leaving.skip(index));
    return ordered;
  }

  void _handleLeft(Key key) {
    if (!mounted || widget.children.any((child) => child.key == key)) return;
    setState(() {
      _entries = [
        for (final entry in _entries)
          if (entry.key != key) entry,
      ];
    });
  }

  @override
  void dispose() {
    _transitions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      radius: AppCorner.xl,
      padding: EdgeInsets.zero,
      child: ClipRSuperellipse(
        borderRadius: AppRadius.all(AppCorner.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in _entries)
              EntryTransition(
                key: entry.key,
                animation: _transitions.animationOf(entry.key!),
                leaving: _transitions.isLeaving(entry.key!),
                child: entry,
              ),
          ],
        ),
      ),
    );
  }
}

class _CardRow extends StatelessWidget {
  const _CardRow({
    super.key,
    required this.first,
    required this.inset,
    required this.child,
  });

  final bool first;
  final double inset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!first)
          Padding(
            padding: EdgeInsets.only(left: inset),
            child: const Divider(height: 0.5, thickness: 0.5),
          ),
        child,
      ],
    );
  }
}

/// Fades and lifts a section into place once, a little after the one above.
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    this.index = 0,
    this.offset = 8,
    required this.child,
  });

  final int index;
  final double offset;
  final Widget child;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 200);
  static const _step = Duration(milliseconds: 32);
  static const _maxDelay = Duration(milliseconds: 160);

  late final _controller = AnimationController(
    vsync: this,
    duration: _duration,
  );
  Timer? _start;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_start != null || _controller.value > 0) return;
    if (context.disableAnimations) {
      _controller.value = 1;
      return;
    }
    final delay = _step * widget.index;
    _start = Timer(delay > _maxDelay ? _maxDelay : delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _start?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (context.disableAnimations) return widget.child;
    final slide = Tween<Offset>(
      begin: Offset(0, widget.offset),
      end: Offset.zero,
    ).chain(CurveTween(curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOut),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Transform.translate(
          offset: slide.evaluate(_controller),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}
