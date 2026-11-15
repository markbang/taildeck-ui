import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import 'preview_env.dart';

/// One Material 3 expressive motion token: the spring Compose plays and the
/// time it takes to settle, so a Flutter tween ends where the spring stops.
///
/// Mirrors the Kotlin app's `Motion` object (`ui/Theme.kt`), which reads
/// `MotionScheme.expressive()` from material3 1.5.0-alpha14.
class MotionSpec {
  const MotionSpec(this.duration, this.curve);

  final Duration duration;
  final Curve curve;
}

MotionSpec _spring(double stiffness, double ratio, double seconds) =>
    MotionSpec(
      Duration(milliseconds: (seconds * 1000).round()),
      SpringCurve(
        SpringDescription.withDampingRatio(
          mass: 1,
          stiffness: stiffness,
          ratio: ratio,
        ),
        seconds: seconds,
      ),
    );

/// Position and size (slowSpatialSpec): springs, so a change overshoots a
/// little; 0.8/200 settles in 600 ms.
final slowSpatial = _spring(200, 0.8, 0.60);

/// Fades and colors (defaultEffectsSpec): critically damped 1600, 230 ms.
final fade = _spring(1600, 1, 0.23);

/// Fades that leave quickly (fastEffectsSpec): critically damped 3800, 150 ms.
final fadeFast = _spring(3800, 1, 0.15);

/// Anything that moves and resizes on its own (defaultSpatialSpec): 0.8/380,
/// 440 ms.
final defaultSpatial = _spring(380, 0.8, 0.44);

/// A short move or resize (fastSpatialSpec): 0.6/800, 410 ms.
final fastSpatial = _spring(800, 0.6, 0.41);

/// Compose's `animateFloatAsState` default spring (`spring()`: no bounce,
/// stiffness 1500), used for chevrons.
final chevron = _spring(1500, 1, 0.24);

/// Compose's `animateItem()` placement spring, for rows that join or leave a
/// list: the default spatial spring.
final placement = defaultSpatial;

/// [spec]'s duration, or zero when the platform asks for reduced motion.
Duration motionDuration(BuildContext context, MotionSpec spec) =>
    context.motionDuration(spec.duration);

/// Animates its child's size whenever that size changes (Compose's
/// `animateContentSize(Motion.slow())`), clipped while it runs.
class AnimatedContentSize extends StatelessWidget {
  const AnimatedContentSize({
    super.key,
    required this.child,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: motionDuration(context, slowSpatial),
      curve: context.disableAnimations ? Curves.linear : slowSpatial.curve,
      alignment: alignment,
      child: child,
    );
  }
}

/// Grows a section in and out with a fade (Compose's `AnimatedVisibility`
/// with `expandVertically`/`shrinkVertically` and the default specs).
class ExpandVisibility extends StatelessWidget {
  const ExpandVisibility({
    super.key,
    required this.visible,
    required this.child,
    this.alignment = Alignment.topCenter,
  });

  final bool visible;
  final Widget child;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: motionDuration(context, slowSpatial),
      curve: context.disableAnimations ? Curves.linear : slowSpatial.curve,
      alignment: alignment,
      child: AnimatedSwitcher(
        duration: motionDuration(context, fade),
        switchInCurve: fade.curve,
        switchOutCurve: fadeFast.curve,
        child: visible
            ? KeyedSubtree(key: const ValueKey(true), child: child)
            : const SizedBox.shrink(),
      ),
    );
  }
}

/// Shows or hides [child] the way a lazy list item joins or leaves: the space
/// it takes animates on Compose's `animateItem()` placement spring, so the
/// rows below slide over the same 440 ms.
class PlacementVisibility extends StatelessWidget {
  const PlacementVisibility({
    super.key,
    required this.visible,
    required this.child,
    this.alignment = Alignment.topCenter,
  });

  final bool visible;
  final Widget child;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final still = context.disableAnimations;
    return AnimatedSize(
      duration: motionDuration(context, placement),
      curve: still ? Curves.linear : placement.curve,
      alignment: alignment,
      child: AnimatedSwitcher(
        duration: motionDuration(context, fade),
        switchInCurve: fade.curve,
        switchOutCurve: fadeFast.curve,
        child: visible
            ? KeyedSubtree(key: const ValueKey(true), child: child)
            : const SizedBox.shrink(),
      ),
    );
  }
}

/// Swaps between full-screen scenes the way the Kotlin app's NavHost does: the
/// new scene slides in from a fifth of the width with a fade, and the old one
/// leaves toward a tenth with a fast fade. Going back reverses the direction.
class MotionSwitcher extends StatefulWidget {
  const MotionSwitcher({
    super.key,
    required this.child,
    this.forward = true,
    this.fadeThrough = false,
  });

  /// Needs a key that changes when the scene does.
  final Widget child;

  /// True when the new scene is deeper than the old one.
  final bool forward;

  /// Signing in fades the shell in over the login form and scales it up from
  /// 96% instead of sliding (Kotlin's `home` enterTransition).
  final bool fadeThrough;

  @override
  State<MotionSwitcher> createState() => _MotionSwitcherState();
}

class _MotionSwitcherState extends State<MotionSwitcher>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this);
  late Widget _current = widget.child;
  Widget? _leaving;
  Timer? _clear;
  bool _forward = true;
  bool _fadeThrough = false;
  bool _started = false;

  @override
  void didUpdateWidget(covariant MotionSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.child.key == _current.key) {
      _current = widget.child;
      return;
    }
    _forward = widget.forward;
    _fadeThrough = widget.fadeThrough;
    _leaving = _current;
    _current = widget.child;
    _clear?.cancel();
    if (context.disableAnimations) {
      _leaving = null;
      return;
    }
    final spec = slowSpatial;
    _controller
      ..duration = spec.duration
      ..forward(from: 0);
    _started = true;
    _clear = Timer(spec.duration + const Duration(milliseconds: 50), () {
      if (mounted) setState(() => _leaving = null);
    });
  }

  @override
  void dispose() {
    _clear?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Outgoing: 1 → 0 within the fast fade at the start, so the old scene is
  /// gone before the new one lands.
  Animation<double> get _exit => CurvedAnimation(
    parent: _controller,
    curve: Interval(
      0,
      fadeFast.duration.inMicroseconds / slowSpatial.duration.inMicroseconds,
      curve: fadeFast.curve,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final leaving = _leaving;
    final enter = CurvedAnimation(
      parent: _controller,
      curve: slowSpatial.curve,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        if (leaving != null)
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final t = _exit.value;
              final begin = _forward ? -0.1 : 0.2;
              final opacity = Opacity(
                opacity: (1 - t).clamp(0, 1),
                child: child,
              );
              if (_fadeThrough) return opacity;
              return FractionalTranslation(
                translation: Offset(begin * (1 - t), 0),
                child: opacity,
              );
            },
            child: ExcludeFocus(child: leaving),
          ),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            if (!_started || leaving == null) return child!;
            final t = enter.value;
            final opacity = Opacity(opacity: t.clamp(0, 1), child: child);
            if (_fadeThrough) {
              return Transform.scale(scale: 0.96 + 0.04 * t, child: opacity);
            }
            final begin = _forward ? 0.2 : -0.1;
            return FractionalTranslation(
              translation: Offset(begin * (1 - t), 0),
              child: opacity,
            );
          },
          child: _current,
        ),
      ],
    );
  }
}

/// Crossfades a short status line (Compose's AnimatedContent with
/// `fadeIn(Motion.fade())` / `fadeOut(Motion.fadeFast())`).
class FadeThrough extends StatelessWidget {
  const FadeThrough({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: motionDuration(context, fade),
      switchInCurve: fade.curve,
      switchOutCurve: fadeFast.curve,
      layoutBuilder: (current, previous) => Stack(
        alignment: AlignmentDirectional.centerStart,
        children: [...previous, ?current],
      ),
      child: child,
    );
  }
}

/// A dot that fades in and out while something is in progress, like the
/// Kotlin app's `AgentDot`: alpha 0.35 → 1 over 700 ms, reversed.
class PulsingDot extends StatefulWidget {
  const PulsingDot({
    super.key,
    required this.color,
    this.size = 6,
    this.pulse = false,
  });

  final Color color;
  final double size;
  final bool pulse;

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  late final _alpha = _controller.drive(
    Tween<double>(
      begin: 0.35,
      end: 1,
    ).chain(CurveTween(curve: Curves.easeInOut)),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant PulsingDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pulse != widget.pulse) _sync();
  }

  void _sync() {
    if (!widget.pulse || context.disableAnimations) {
      _controller
        ..stop()
        ..value = 1;
      return;
    }
    if (!_controller.isAnimating) _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _alpha,
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: widget.color),
        duration: motionDuration(context, fade),
        curve: fade.curve,
        builder: (context, color, _) => SizedBox.square(
          dimension: widget.size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color ?? widget.color,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// Compose's `AnimatedVisibility`: the child fades in with the default effects
/// spring, and optionally scales up from [scaleFrom] and expands its height
/// with the slow spatial one. Leaving reverses both.
class MotionVisibility extends StatefulWidget {
  const MotionVisibility({
    super.key,
    required this.visible,
    required this.child,
    this.scaleFrom,
    this.expand = false,
    this.alignment = Alignment.topCenter,
  });

  final bool visible;
  final Widget child;

  /// Start scale on enter (Compose's `scaleIn(initialScale = ...)`); the exit
  /// is a plain fade, as in the Kotlin app.
  final double? scaleFrom;

  /// Animate the height as well (Compose's `expandVertically` /
  /// `shrinkVertically`).
  final bool expand;

  final AlignmentGeometry alignment;

  @override
  State<MotionVisibility> createState() => _MotionVisibilityState();
}

class _MotionVisibilityState extends State<MotionVisibility>
    with TickerProviderStateMixin {
  late final _effects = AnimationController(
    vsync: this,
    value: widget.visible ? 1 : 0,
  )..addStatusListener(_onStatus);
  late final _spatial = AnimationController(
    vsync: this,
    value: widget.visible ? 1 : 0,
  );
  late final _opacity = CurvedAnimation(
    parent: _effects,
    curve: fade.curve,
    reverseCurve: fadeFast.curve,
  );
  late final _size = CurvedAnimation(
    parent: _spatial,
    curve: slowSpatial.curve,
    reverseCurve: slowSpatial.curve,
  );
  late bool _present = widget.visible;

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.dismissed || widget.visible || !_present) {
      return;
    }
    setState(() => _present = false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _applyDurations();
  }

  @override
  void didUpdateWidget(covariant MotionVisibility oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible == widget.visible) return;
    _applyDurations();
    if (widget.visible) {
      setState(() => _present = true);
      _effects.forward(from: 0);
      _spatial.forward(from: 0);
      return;
    }
    _effects.reverse();
    _spatial.reverse();
  }

  void _applyDurations() {
    final still = context.disableAnimations;
    _effects
      ..duration = still ? Duration.zero : fade.duration
      ..reverseDuration = still ? Duration.zero : fadeFast.duration;
    _spatial
      ..duration = still ? Duration.zero : slowSpatial.duration
      ..reverseDuration = still ? Duration.zero : slowSpatial.duration;
  }

  @override
  void dispose() {
    _effects.dispose();
    _spatial.dispose();
    _opacity.dispose();
    _size.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_present) return const SizedBox.shrink();
    Widget child = FadeTransition(opacity: _opacity, child: widget.child);
    final scale = widget.scaleFrom;
    if (scale != null) {
      child = ScaleTransition(
        scale: Tween<double>(begin: scale, end: 1).animate(_opacity),
        child: child,
      );
    }
    if (widget.expand) {
      child = SizeTransition(
        sizeFactor: _size,
        alignment: widget.alignment,
        child: child,
      );
    }
    return IgnorePointer(
      ignoring: !widget.visible,
      child: ExcludeSemantics(excluding: !widget.visible, child: child),
    );
  }
}

/// Compose's `AnimatedContent` with a slide: the incoming child slides in from
/// a fraction of the height while it fades, the outgoing one slides the same
/// way out.
class SlideFadeSwitcher extends StatelessWidget {
  const SlideFadeSwitcher({
    super.key,
    required this.child,
    this.slide = 1 / 3,
    this.alignment = Alignment.center,
  });

  final Widget child;

  /// Fraction of the height both children travel.
  final double slide;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: motionDuration(context, slowSpatial),
      switchInCurve: fade.curve,
      switchOutCurve: Curves.easeOut,
      layoutBuilder: (current, previous) =>
          Stack(alignment: alignment, children: [...previous, ?current]),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: Offset(0, slide),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Compose's default `AnimatedContent` transition: the new child fades in and
/// scales up from [scale], the old one fades out.
class ScaleFadeSwitcher extends StatelessWidget {
  const ScaleFadeSwitcher({
    super.key,
    required this.child,
    this.scale = 0.92,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double scale;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: motionDuration(context, fade),
      switchInCurve: fade.curve,
      switchOutCurve: fadeFast.curve,
      layoutBuilder: (current, previous) =>
          Stack(alignment: alignment, children: [...previous, ?current]),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: scale, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// A chevron that turns over when a section opens, on Compose's
/// `animateFloatAsState` default spring.
class RotatingChevron extends StatelessWidget {
  const RotatingChevron({
    super.key,
    required this.open,
    this.size = 18,
    this.color,
  });

  final bool open;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: open ? 1 : 0),
      duration: motionDuration(context, chevron),
      curve: chevron.curve,
      builder: (context, value, child) => Transform.rotate(
        angle: (value + 0.5) * 3.141592653589793,
        child: child,
      ),
      child: GlyphIcon(Glyphs.chevronForward, size: size, color: color),
    );
  }
}

/// The three dots that light in turn in the Kotlin app's working bar: 600 ms
/// each, 160 ms apart, reversed.
class InkDots extends StatefulWidget {
  const InkDots({super.key, this.size = 6, this.color});

  final double size;
  final Color? color;

  @override
  State<InkDots> createState() => _InkDotsState();
}

class _InkDotsState extends State<InkDots> with SingleTickerProviderStateMixin {
  static const _period = Duration(milliseconds: 1200);
  static const _stagger = 160 / 1200;

  late final _controller = AnimationController(vsync: this, duration: _period);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.disableAnimations) {
      _controller
        ..stop()
        ..value = 0;
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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : 3),
                child: Opacity(
                  opacity: _alpha(_controller.value - i * _stagger),
                  child: SizedBox.square(
                    dimension: widget.size,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: tint,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// A triangle wave: 0.25 → 1 → 0.25 over one period.
  double _alpha(double t) {
    final phase = (t % 1 + 1) % 1;
    final wave = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
    return 0.25 + 0.75 * wave;
  }
}

/// The shell's tab pages, swapped as whole surfaces: [fade] drops the old page
/// to zero before the new one appears, otherwise the two pages slide past each
/// other, each one opaque. No frame blends two pages, a rapid switch only
/// retargets the travel, and pages that are not on screen stay in the tree
/// unpainted, so their state and scroll offset survive.
class TabSwitcher extends StatefulWidget {
  const TabSwitcher({
    super.key,
    required this.index,
    required this.count,
    required this.pageBuilder,
    required this.background,
    this.fade = false,
    this.animate = true,
  });

  final int index;
  final int count;
  final IndexedWidgetBuilder pageBuilder;

  /// Painted behind every page, so a page's own transparent root cannot let
  /// the page underneath show through.
  final Color background;

  final bool fade;

  /// False where a switch should not travel, as on a wide layout.
  final bool animate;

  @override
  State<TabSwitcher> createState() => _TabSwitcherState();
}

class _TabSwitcherState extends State<TabSwitcher>
    with SingleTickerProviderStateMixin {
  /// The visible page as a continuous value: 1.5 means halfway between pages
  /// 1 and 2, so a switch is a retarget and an interrupted switch resumes.
  late final _position = AnimationController.unbounded(
    vsync: this,
    value: widget.index.toDouble(),
  );
  final _built = <int>{};
  final _pageKeys = <int, GlobalKey>{};
  double _from = 0;
  double _to = 0;

  /// `?tabprobe=1` on a debug build logs the painted pages at each step of a
  /// switch, so the emulator gate can check the real paint state.
  final _probe = kDebugMode && previewParam('tabprobe') == '1';
  final _probedSteps = <int>{};

  /// How far a page travels while it is visible, in pages. A fade-through
  /// fades a page out by 40% of the travel and the next one in over the last
  /// 40%, so the two are never on screen together.
  static const _fadeSpan = 0.4;

  @override
  void initState() {
    super.initState();
    _built.add(widget.index);
    _from = _to = widget.index.toDouble();
    if (_probe) {
      _position.addListener(_probeStep);
      _position.addStatusListener(_probeSettled);
    }
  }

  @override
  void didUpdateWidget(covariant TabSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index == oldWidget.index) return;
    _built.add(widget.index);
    _probedSteps.clear();
    _from = _position.value;
    _to = widget.index.toDouble();
    if (!widget.animate || context.disableAnimations || widget.count < 2) {
      _position.value = _to;
      if (_probe) {
        debugPrint(
          'taildeck tabprobe: jump animate=${widget.animate} '
          'still=${context.disableAnimations}',
        );
      }
      return;
    }
    _position.animateTo(
      _to,
      duration: widget.fade ? fadeTabDuration : slowSpatial.duration,
      curve: widget.fade ? fadeTabCurve : slowSpatial.curve,
    );
  }

  @override
  void dispose() {
    if (_probe) {
      _position.removeListener(_probeStep);
      _position.removeStatusListener(_probeSettled);
    }
    _position.dispose();
    super.dispose();
  }

  void _probeStep() {
    final span = _to - _from;
    if (span == 0) return;
    final progress = ((_position.value - _from) / span).clamp(0.0, 1.0);
    final step = (progress * 10).floor();
    if (step == 0 || step >= 10 || !_probedSteps.add(step)) return;
    // Read the paint state once this build has been laid out and painted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _report(progress);
    });
  }

  void _probeSettled(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    // The pages are rebuilt with their final Offstage after this notification.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _report(1);
    });
  }

  /// Counts what is actually painted: each page's rect after its transforms,
  /// the opacity accumulated above it and whether an Offstage parent hides it.
  void _report(double progress) {
    final painted = <({int index, Rect rect, double opacity})>[];
    for (final index in _built) {
      final box = _pageKeys[index]?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      var hidden = false;
      var opacity = 1.0;
      Rect rect = box.localToGlobal(Offset.zero) & box.size;
      for (RenderObject? node = box; node != null; node = node.parent) {
        if (node is RenderOffstage) hidden = hidden || node.offstage;
        if (node is RenderOpacity) opacity *= node.opacity;
      }
      if (hidden || opacity == 0 || rect.isEmpty) continue;
      painted.add((index: index, rect: rect, opacity: opacity));
    }
    var blended = 0.0;
    for (var a = 0; a < painted.length; a++) {
      for (var b = a + 1; b < painted.length; b++) {
        final overlap = painted[a].rect.intersect(painted[b].rect);
        if (overlap.isEmpty) continue;
        final area = overlap.width * overlap.height;
        if (painted[a].opacity < 1 || painted[b].opacity < 1) blended += area;
      }
    }
    debugPrint(
      'taildeck tabprobe: from=${_from.toInt()} to=${_to.toInt()} '
      'p=${progress.toStringAsFixed(2)} painted=${painted.length} '
      'blend=${blended.round()} tabs=${painted.map((page) => page.index).join(",")}',
    );
  }

  /// The travel, held between its ends so a spring's overshoot cannot pull a
  /// page off its edge and leave a strip of background beside it.
  double get _travel => _position.value.clamp(
    _from < _to ? _from : _to,
    _from < _to ? _to : _from,
  );

  @override
  Widget build(BuildContext context) {
    // Built once per shell build, not once per animation frame: a settings
    // page rebuilding at 60 fps would cost more than the transition.
    final pages = <int, Widget>{
      for (final index in _built) index: _pageContent(context, index),
    };
    return ClipRect(
      child: AnimatedBuilder(
        animation: _position,
        builder: (context, _) {
          final position = _travel;
          return Stack(
            fit: StackFit.expand,
            children: [
              for (var index = 0; index < widget.count; index++)
                if (pages[index] case final page?)
                  _frame(index, page, position)
                else
                  const SizedBox.shrink(),
            ],
          );
        },
      ),
    );
  }

  Widget _pageContent(BuildContext context, int index) {
    return ColoredBox(
      key: _pageKeys.putIfAbsent(index, GlobalKey.new),
      color: widget.background,
      child: widget.pageBuilder(context, index),
    );
  }

  Widget _frame(int index, Widget page, double position) {
    final delta = index - position;
    final alpha = widget.fade
        ? ((_fadeSpan - delta.abs()) / _fadeSpan).clamp(0.0, 1.0)
        : (delta.abs() < 1 ? 1.0 : 0.0);
    final current = index == widget.index;
    // The wrapper shape stays the same for every page and every frame, so the
    // page's element (and its state) is never reparented.
    return Offstage(
      offstage: alpha == 0,
      child: TickerMode(
        enabled: current,
        child: ExcludeFocus(
          excluding: !current,
          child: FractionalTranslation(
            translation: widget.fade ? Offset.zero : Offset(delta, 0),
            child: Opacity(opacity: alpha, child: page),
          ),
        ),
      ),
    );
  }
}
