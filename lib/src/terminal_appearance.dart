/// How the terminal looks: color theme, font family, cursor shape and blink.
///
/// The grid is painted by `TerminalCanvas` from libghostty-vt snapshots, so a
/// theme is the colors of the page chrome (header, input bar, key row) plus
/// the default foreground and background the grid falls back to. Colors the
/// running program sets itself (ANSI, 256-color) stay as the emulator reports
/// them.
library;

import 'package:flutter/widgets.dart';

import 'native/term.dart';

/// The palettes a user can pick. [follow] resolves from the app's brightness.
enum TerminalThemeId {
  follow,
  taildeck,
  midnight,
  paper,
  solarizedDark,
  solarizedLight,
}

/// The font family the grid and the page chrome use.
enum TerminalFontId { dejavu, systemMono, sans }

/// Cursor shape; [follow] keeps what the program asked for with DECSCUSR.
enum TerminalCursorId { follow, block, bar, underline }

/// One color scheme: everything the terminal page paints, so a light palette
/// can invert the whole page and not only the grid.
@immutable
class TerminalPalette {
  const TerminalPalette({
    required this.id,
    required this.brightness,
    required this.background,
    required this.backgroundAlt,
    required this.foreground,
    required this.dim,
    required this.accent,
    required this.cursor,
    required this.selection,
    required this.selectionText,
    required this.chrome,
    required this.surface,
    required this.border,
    required this.success,
    required this.warning,
    required this.error,
  });

  final TerminalThemeId id;
  final Brightness brightness;

  /// Grid background; [backgroundAlt] is the gradient's lower stop.
  final Color background;
  final Color backgroundAlt;
  final Color foreground;
  final Color dim;
  final Color accent;
  final Color cursor;
  final Color selection;
  final Color selectionText;

  /// Header and key row; [surface] is the input bar and quick-command chips.
  final Color chrome;
  final Color surface;
  final Color border;
  final Color success;
  final Color warning;
  final Color error;

  bool get isLight => brightness == Brightness.light;

  /// `0xAARRGGBB` defaults for the native emulator.
  int get foregroundArgb => foreground.toARGB32();
  int get backgroundArgb => background.toARGB32();
  int get cursorArgb => cursor.toARGB32();
}

const _taildeck = TerminalPalette(
  id: TerminalThemeId.taildeck,
  brightness: Brightness.dark,
  background: Color(0xFF090A0C),
  backgroundAlt: Color(0xFF101319),
  foreground: Color(0xFFE7E9ED),
  dim: Color(0xFF7C838D),
  accent: Color(0xFF7FB4FF),
  cursor: Color(0xFF8FD3A8),
  selection: Color(0xFF2C4A38),
  selectionText: Color(0xFFFFFFFF),
  chrome: Color(0xFF0D0F13),
  surface: Color(0xFF15181F),
  border: Color(0x14FFFFFF),
  success: Color(0xFF57D7A0),
  warning: Color(0xFFE3B341),
  error: Color(0xFFFF7B72),
);

const _midnight = TerminalPalette(
  id: TerminalThemeId.midnight,
  brightness: Brightness.dark,
  background: Color(0xFF0A0F1E),
  backgroundAlt: Color(0xFF111A30),
  foreground: Color(0xFFDCE3F0),
  dim: Color(0xFF7E89A3),
  accent: Color(0xFF8CB4FF),
  cursor: Color(0xFFA7C4FF),
  selection: Color(0xFF24365E),
  selectionText: Color(0xFFFFFFFF),
  chrome: Color(0xFF0C1322),
  surface: Color(0xFF16203A),
  border: Color(0x1A8CB4FF),
  success: Color(0xFF6FE3B0),
  warning: Color(0xFFF0C674),
  error: Color(0xFFFF8B8B),
);

const _paper = TerminalPalette(
  id: TerminalThemeId.paper,
  brightness: Brightness.light,
  background: Color(0xFFF7F5EF),
  backgroundAlt: Color(0xFFEDEAE2),
  foreground: Color(0xFF23262B),
  dim: Color(0xFF6B6F76),
  accent: Color(0xFF2F6F4F),
  cursor: Color(0xFF2F6F4F),
  selection: Color(0xFFCFE3D6),
  selectionText: Color(0xFF10241A),
  chrome: Color(0xFFEDEAE2),
  surface: Color(0xFFE6E2D8),
  border: Color(0x14000000),
  success: Color(0xFF1F7A50),
  warning: Color(0xFF8A6100),
  error: Color(0xFFB3261E),
);

const _solarizedDark = TerminalPalette(
  id: TerminalThemeId.solarizedDark,
  brightness: Brightness.dark,
  background: Color(0xFF002B36),
  backgroundAlt: Color(0xFF00323D),
  foreground: Color(0xFF93A1A1),
  dim: Color(0xFF6D7B7B),
  accent: Color(0xFF2AA198),
  cursor: Color(0xFFB58900),
  selection: Color(0xFF0B4A57),
  selectionText: Color(0xFFFDF6E3),
  chrome: Color(0xFF002129),
  surface: Color(0xFF073642),
  border: Color(0x1F93A1A1),
  success: Color(0xFF859900),
  warning: Color(0xFFB58900),
  error: Color(0xFFDC322F),
);

const _solarizedLight = TerminalPalette(
  id: TerminalThemeId.solarizedLight,
  brightness: Brightness.light,
  background: Color(0xFFFDF6E3),
  backgroundAlt: Color(0xFFF5EED9),
  foreground: Color(0xFF586E75),
  dim: Color(0xFF93A1A1),
  accent: Color(0xFF268BD2),
  cursor: Color(0xFFCB4B16),
  selection: Color(0xFFEEE8D5),
  selectionText: Color(0xFF073642),
  chrome: Color(0xFFF5EED9),
  surface: Color(0xFFEEE8D5),
  border: Color(0x1A586E75),
  success: Color(0xFF859900),
  warning: Color(0xFFB58900),
  error: Color(0xFFDC322F),
);

/// What a widget paints with before Settings is read.
const defaultTerminalPalette = _taildeck;

const terminalPalettes = <TerminalThemeId, TerminalPalette>{
  TerminalThemeId.taildeck: _taildeck,
  TerminalThemeId.midnight: _midnight,
  TerminalThemeId.paper: _paper,
  TerminalThemeId.solarizedDark: _solarizedDark,
  TerminalThemeId.solarizedLight: _solarizedLight,
};

/// The palette [id] paints with; [follow] picks a dark or a light one.
TerminalPalette terminalPaletteOf(TerminalThemeId id, Brightness app) {
  if (id == TerminalThemeId.follow) {
    return app == Brightness.light ? _paper : _taildeck;
  }
  return terminalPalettes[id] ?? _taildeck;
}

/// The family the grid asks for; [TerminalFontId.systemMono] asks Fontconfig
/// and Android for the platform's monospace.
String terminalFontFamily(TerminalFontId id) => switch (id) {
  TerminalFontId.dejavu => 'DejaVuSansMono',
  TerminalFontId.systemMono => 'monospace',
  TerminalFontId.sans => 'Roboto',
};

const terminalFontFallback = <String>['NotoSansCJK', 'DejaVuSansMono'];

/// Parsers keep the default for anything this build does not know.
TerminalThemeId parseTerminalThemeId(Object? value) =>
    TerminalThemeId.values.firstWhere(
      (id) => id.name == value,
      orElse: () => TerminalThemeId.follow,
    );

TerminalFontId parseTerminalFontId(Object? value) =>
    TerminalFontId.values.firstWhere(
      (id) => id.name == value,
      orElse: () => TerminalFontId.dejavu,
    );

TerminalCursorId parseTerminalCursorId(Object? value) =>
    TerminalCursorId.values.firstWhere(
      (id) => id.name == value,
      orElse: () => TerminalCursorId.follow,
    );

/// The shape to paint: the setting, or [native] when it says follow.
int terminalCursorStyleOf(TerminalCursorId id, int native) => switch (id) {
  TerminalCursorId.follow => native,
  TerminalCursorId.block => CursorStyle.block,
  TerminalCursorId.bar => CursorStyle.bar,
  TerminalCursorId.underline => CursorStyle.underline,
};
