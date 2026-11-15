import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import '../l10n.dart';
import '../terminal_appearance.dart';
import '../terminal_store.dart';
import '../widgets/controls.dart';

/// The open sessions as a strip of chips: node, login and status, with a tap
/// to switch. Every session keeps its own grid, so switching is instant.
class TerminalSessionStrip extends StatelessWidget {
  const TerminalSessionStrip({
    super.key,
    required this.sessions,
    required this.current,
    required this.palette,
    this.onSwitch,
  });

  final List<SshTerminal> sessions;
  final SshTerminal current;
  final TerminalPalette palette;
  final ValueChanged<SshTerminal>? onSwitch;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: l10n.a11yTerminalSessions(sessions.length),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.chrome,
          border: Border(
            bottom: BorderSide(color: palette.border, width: 0.5),
          ),
        ),
        child: SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            children: [
              for (final session in sessions)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _SessionChip(
                    session: session,
                    current: session == current,
                    palette: palette,
                    onTap: onSwitch == null || session == current
                        ? null
                        : () => onSwitch!(session),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionChip extends StatelessWidget {
  const _SessionChip({
    required this.session,
    required this.current,
    required this.palette,
    this.onTap,
  });

  final SshTerminal session;
  final bool current;
  final TerminalPalette palette;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = session.closed
        ? l10n.terminalSessionDropped
        : l10n.connected;
    final tint = session.closed ? palette.error : palette.success;
    return Semantics(
      button: true,
      selected: current,
      label: l10n.a11yTerminalSession('${session.user}@${session.node.name}', state),
      hint: current ? null : l10n.terminalSessionSwitchHint,
      onTap: onTap,
      excludeSemantics: true,
      child: TapFeedback(
        onTap: onTap,
        excludeFromSemantics: true,
        squish: true,
        shape: AppShape.full,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: ShapeDecoration(
            color: current
                ? palette.surface
                : palette.surface.withValues(alpha: 0.4),
            shape: StadiumBorder(
              side: BorderSide(
                color: current ? palette.accent : palette.border,
                width: current ? 1 : 0.5,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                '${session.user}@${session.node.name}',
                style: TextStyle(
                  fontFamily: terminalFontFamily(TerminalFontId.dejavu),
                  fontSize: 11.5,
                  fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                  color: palette.foreground,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

