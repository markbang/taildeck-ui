import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import '../l10n.dart';
import '../terminal_appearance.dart';
import '../terminal_keys.dart';
import '../widgets/controls.dart';

/// The extra key row under the terminal input: one page at a time, swiped, or
/// stepped with the page dots for keyboards and screen readers.
class TerminalKeyBar extends StatefulWidget {
  const TerminalKeyBar({
    super.key,
    required this.pages,
    required this.mods,
    required this.onKey,
    required this.onModifier,
    this.active = const {},
    this.palette = defaultTerminalPalette,
    this.bottomInset = 0,
  });

  final List<List<String>> pages;
  final TerminalMods mods;

  /// Toggle keys currently on, drawn like an armed modifier.
  final Set<String> active;
  final ValueChanged<TerminalKey> onKey;
  final ValueChanged<TerminalMod> onModifier;
  final TerminalPalette palette;

  /// Gesture bar or cutout below the row: the row's own background covers it,
  /// so the row sits on the same surface as the rest of the page.
  final double bottomInset;

  @override
  State<TerminalKeyBar> createState() => _TerminalKeyBarState();
}

class _TerminalKeyBarState extends State<TerminalKeyBar> {
  final _controller = PageController();
  int _page = 0;

  @override
  void didUpdateWidget(TerminalKeyBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_page < widget.pages.length) return;
    _page = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller.hasClients) _controller.jumpToPage(0);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _step(int index, int total) {
    final target = (index + 1) % total;
    if (context.disableAnimations) {
      _controller.jumpToPage(target);
      return;
    }
    _controller.animateToPage(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      for (final page in widget.pages)
        if (page.isNotEmpty) page,
    ];
    if (pages.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final total = pages.length;
    final index = _page.clamp(0, total - 1);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: l10n.a11yTerminalKeyRow(total),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: widget.palette.chrome,
          border: Border(
            top: BorderSide(color: widget.palette.border, width: 0.5),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(6, 5, 6, 7 + widget.bottomInset),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: total,
                    onPageChanged: (value) => setState(() => _page = value),
                    itemBuilder: (context, page) => Row(
                      children: [
                        for (final id in pages[page])
                          if (terminalKeyById(id) case final key?)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                child: _KeyButton(
                                  terminalKey: key,
                                  mods: widget.mods,
                                  onKey: widget.onKey,
                                  onModifier: widget.onModifier,
                                  active: widget.active.contains(key.id),
                                  palette: widget.palette,
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
              ),
              if (total > 1)
                _PageDots(
                  index: index,
                  total: total,
                  label: l10n.a11yTerminalKeyPage(index + 1, total),
                  hint: l10n.a11yTerminalKeyPageNext,
                  palette: widget.palette,
                  onTap: () => _step(index, total),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyButton extends StatefulWidget {
  const _KeyButton({
    required this.terminalKey,
    required this.mods,
    required this.onKey,
    required this.onModifier,
    this.active = false,
    required this.palette,
  });

  final TerminalKey terminalKey;
  final TerminalMods mods;

  /// A toggle key's state, shown like an armed modifier.
  final bool active;
  final ValueChanged<TerminalKey> onKey;
  final ValueChanged<TerminalMod> onModifier;
  final TerminalPalette palette;

  @override
  State<_KeyButton> createState() => _KeyButtonState();
}

class _KeyButtonState extends State<_KeyButton> {
  /// Arrows repeat while held, the way a hardware arrow does; the first
  /// repeat comes before Flutter's own 500 ms long press.
  static const _holdDelay = Duration(milliseconds: 380);
  static const _holdInterval = Duration(milliseconds: 70);
  static const _repeating = {'left', 'up', 'down', 'right'};

  Timer? _repeat;
  bool _held = false;

  bool get _repeats =>
      _repeating.contains(widget.terminalKey.id) &&
      widget.terminalKey.modifier == null;

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  void _startHold() {
    _held = false;
    if (!_repeats) return;
    _repeat?.cancel();
    _repeat = Timer(_holdDelay, () {
      if (!mounted) return;
      _held = true;
      _fire();
      _repeat = Timer.periodic(_holdInterval, (_) {
        if (mounted) _fire();
      });
    });
  }

  void _stopHold() {
    _repeat?.cancel();
    _repeat = null;
  }

  void _fire() => widget.onKey(widget.terminalKey);

  @override
  Widget build(BuildContext context) {
    final terminalKey = widget.terminalKey;
    final l10n = AppLocalizations.of(context);
    final mod = terminalKey.modifier;
    final armed = mod != null && widget.mods.isArmed(mod);
    final locked = mod != null && widget.mods.isLocked(mod);
    final active = armed || locked || widget.active;
    final radius = BorderRadius.circular(7);
    void onTap() {
      // A hold already sent its keys; the release must not send one more.
      if (_held) {
        _held = false;
        return;
      }
      if (mod == null) {
        widget.onKey(terminalKey);
      } else {
        widget.onModifier(mod);
      }
    }

    return Listener(
      onPointerDown: (_) => _startHold(),
      onPointerUp: (_) => _stopHold(),
      onPointerCancel: (_) => _stopHold(),
      child: Semantics(
        button: true,
        selected: active,
        label: l10n.terminalKeyName(terminalKey.id),
        value: locked
            ? l10n.terminalKeyLocked
            : armed
            ? l10n.terminalKeyArmed
            : widget.active
            ? l10n.terminalKeyOn
            : null,
        onTap: onTap,
        excludeSemantics: true,
        child: TapFeedback(
          onTap: onTap,
          excludeFromSemantics: true,
          shape: RoundedRectangleBorder(borderRadius: radius),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: locked
                  ? widget.palette.accent
                  : armed
                  ? widget.palette.accent.withValues(alpha: 0.26)
                  : widget.palette.surface,
              shape: RoundedRectangleBorder(
                borderRadius: radius,
                side: BorderSide(
                  color: active
                      ? widget.palette.accent
                      : widget.palette.border,
                  width: active ? 1 : 0.5,
                ),
              ),
            ),
            child: Text(
              terminalKey.label,
              maxLines: 1,
              overflow: TextOverflow.clip,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: terminalFontFamily(TerminalFontId.dejavu),
                fontSize: 11.5,
                height: 1.1,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: locked
                    ? widget.palette.background
                    : widget.palette.foreground,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({
    required this.index,
    required this.total,
    required this.label,
    required this.hint,
    required this.palette,
    required this.onTap,
  });

  final int index;
  final int total;
  final String label;
  final String hint;
  final TerminalPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      hint: hint,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 18,
          height: 32,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < total; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 4,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == index
                        ? palette.accent
                        : palette.foreground.withValues(alpha: 0.24),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
