import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import '../l10n.dart';
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
  });

  final List<List<String>> pages;
  final TerminalMods mods;
  final ValueChanged<TerminalKey> onKey;
  final ValueChanged<TerminalMod> onModifier;

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
        decoration: const BoxDecoration(
          color: _TerminalKeyColors.background,
          border: Border(top: BorderSide(color: Color(0x14FFFFFF), width: 0.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 5, 6, 7),
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
                  onTap: () => _step(index, total),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

abstract final class _TerminalKeyColors {
  static const background = Color(0xFF0D0F13);
  static const fill = Color(0xFF15181F);
  static const border = Color(0x1FFFFFFF);
  static const accent = Color(0xFF7FB4FF);
  static const label = Color(0xFFC9CDD6);
  static const lockedLabel = Color(0xFF0B0D10);
}

class _KeyButton extends StatelessWidget {
  const _KeyButton({
    required this.terminalKey,
    required this.mods,
    required this.onKey,
    required this.onModifier,
  });

  final TerminalKey terminalKey;
  final TerminalMods mods;
  final ValueChanged<TerminalKey> onKey;
  final ValueChanged<TerminalMod> onModifier;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final mod = terminalKey.modifier;
    final armed = mod != null && mods.isArmed(mod);
    final locked = mod != null && mods.isLocked(mod);
    final active = armed || locked;
    final radius = BorderRadius.circular(7);
    void onTap() {
      if (mod == null) {
        onKey(terminalKey);
      } else {
        onModifier(mod);
      }
    }

    return Semantics(
      button: true,
      selected: active,
      label: l10n.terminalKeyName(terminalKey.id),
      value: locked
          ? l10n.terminalKeyLocked
          : armed
          ? l10n.terminalKeyArmed
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
                ? _TerminalKeyColors.accent
                : armed
                ? _TerminalKeyColors.accent.withValues(alpha: 0.26)
                : _TerminalKeyColors.fill,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(
                color: active
                    ? _TerminalKeyColors.accent
                    : _TerminalKeyColors.border,
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
              fontFamily: 'DejaVuSansMono',
              fontSize: 11.5,
              height: 1.1,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: locked
                  ? _TerminalKeyColors.lockedLabel
                  : _TerminalKeyColors.label,
              decoration: TextDecoration.none,
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
    required this.onTap,
  });

  final int index;
  final int total;
  final String label;
  final String hint;
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
                        ? _TerminalKeyColors.accent
                        : const Color(0x3DFFFFFF),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
