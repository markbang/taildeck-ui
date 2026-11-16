import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../glyphs.dart';
import '../widgets/controls.dart';
import '../l10n.dart';
import '../terminal_appearance.dart';
import '../terminal_keys.dart';
import 'term_key_bar.dart';

/// The terminal's floating capsule: the three keys a soft keyboard lacks, the
/// d-pad that opens the extra keys, snippets, paste, Compose, and the keyboard
/// toggle. It floats over the grid and carries the bottom safe area.
class TerminalToolbar extends StatelessWidget {
  const TerminalToolbar({
    super.key,
    required this.palette,
    required this.mods,
    required this.pages,
    required this.expanded,
    required this.keyboardVisible,
    required this.onToggleExpanded,
    required this.onKey,
    required this.onModifier,
    required this.onSnippets,
    required this.onPaste,
    required this.onCompose,
    required this.onKeyboard,
    this.bottomInset = 0,
  });

  final TerminalPalette palette;
  final TerminalMods mods;

  /// The user's pages from Settings, shown under a fixed arrow page.
  final List<List<String>> pages;

  /// The extra-key panel above the capsule is open.
  final bool expanded;

  /// The soft keyboard is up; the keyboard button then closes it.
  final bool keyboardVisible;
  final VoidCallback onToggleExpanded;
  final ValueChanged<TerminalKey> onKey;
  final ValueChanged<TerminalMod> onModifier;
  final VoidCallback onSnippets;
  final VoidCallback onPaste;
  final VoidCallback onCompose;
  final VoidCallback onKeyboard;

  /// Gesture bar or cutout below the capsule.
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reduce = context.disableAnimations;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: reduce
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.bottomCenter,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                    child: _FrostedPanel(
                      palette: palette,
                      child: TerminalKeyBar(
                        pages: [
                          const ['left', 'up', 'down', 'right'],
                          for (final page in pages) page,
                        ],
                        mods: mods,
                        onKey: onKey,
                        onModifier: onModifier,
                        palette: palette,
                        floating: true,
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 8 + bottomInset),
            child: _FrostedPanel(
              palette: palette,
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    _CapsuleItem(
                      label: 'Ctrl',
                      active:
                          mods.isArmed(TerminalMod.ctrl) ||
                          mods.isLocked(TerminalMod.ctrl),
                      onTap: () => onModifier(TerminalMod.ctrl),
                      palette: palette,
                      semanticLabel: l10n.terminalKeyName('ctrl'),
                      semanticValue: mods.isLocked(TerminalMod.ctrl)
                          ? l10n.terminalKeyLocked
                          : mods.isArmed(TerminalMod.ctrl)
                          ? l10n.terminalKeyArmed
                          : null,
                    ),
                    _CapsuleItem(
                      label: 'Esc',
                      onTap: () => onKey(terminalKeyById('esc')!),
                      palette: palette,
                      semanticLabel: l10n.terminalKeyName('esc'),
                    ),
                    _CapsuleItem(
                      label: 'Tab',
                      onTap: () => onKey(terminalKeyById('tab')!),
                      palette: palette,
                      semanticLabel: l10n.terminalKeyName('tab'),
                    ),
                    _CapsuleItem(
                      glyph: Glyphs2.dpad,
                      active: expanded,
                      onTap: onToggleExpanded,
                      palette: palette,
                      semanticLabel: l10n.terminalArrowKeys,
                      semanticValue: expanded ? l10n.terminalKeyOn : null,
                    ),
                    _CapsuleItem(
                      glyph: Glyphs2.bolt,
                      onTap: onSnippets,
                      palette: palette,
                      semanticLabel: l10n.terminalSnippets,
                    ),
                    _CapsuleItem(
                      glyph: Glyphs.paste,
                      onTap: onPaste,
                      palette: palette,
                      semanticLabel: l10n.terminalPasteButton,
                    ),
                    _CapsuleItem(
                      flex: 2,
                      glyph: Glyphs2.compose,
                      label: l10n.terminalCompose,
                      onTap: onCompose,
                      palette: palette,
                      semanticLabel: l10n.terminalCompose,
                    ),
                    _CapsuleItem(
                      glyph: Glyphs2.keyboard,
                      active: keyboardVisible,
                      onTap: onKeyboard,
                      palette: palette,
                      semanticLabel: keyboardVisible
                          ? l10n.terminalHideKeyboard
                          : l10n.terminalShowKeyboard,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FrostedPanel extends StatelessWidget {
  const _FrostedPanel({required this.palette, required this.child});

  final TerminalPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tint = palette.surface.withValues(alpha: 0.86);
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: StadiumBorder(
          side: BorderSide(
            color: palette.foreground.withValues(alpha: 0.14),
            width: 0.5,
          ),
        ),
        shadows: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: ColoredBox(color: tint, child: child),
        ),
      ),
    );
  }
}

class _CapsuleItem extends StatelessWidget {
  const _CapsuleItem({
    required this.onTap,
    required this.palette,
    required this.semanticLabel,
    this.label,
    this.glyph,
    this.active = false,
    this.flex = 1,
    this.semanticValue,
  });

  final VoidCallback onTap;
  final TerminalPalette palette;
  final String semanticLabel;
  final String? semanticValue;
  final String? label;
  final Glyph? glyph;
  final bool active;
  final int flex;

  @override
  Widget build(BuildContext context) {
    final color = active ? palette.accent : palette.foreground;
    return Expanded(
      flex: flex,
      child: Semantics(
        container: true,
        button: true,
        selected: active,
        label: semanticLabel,
        value: semanticValue,
        excludeSemantics: true,
        onTap: onTap,
        child: TapFeedback(
          onTap: onTap,
          excludeFromSemantics: true,
          shape: AppShape.full,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 1, vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: ShapeDecoration(
              color: active
                  ? palette.accent.withValues(alpha: 0.18)
                  : const Color(0x00000000),
              shape: AppShape.all(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (glyph case final glyph?)
                  GlyphIcon(glyph, size: 17, color: color),
                if (glyph != null && label != null) const SizedBox(width: 4),
                if (label case final label?)
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.1,
                        fontWeight: FontWeight.w600,
                        color: color,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
