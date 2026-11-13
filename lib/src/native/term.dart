/// libghostty-vt through the C shim in `native/term/term_ffi.c`.
///
/// The emulator lives in native code; this library only feeds bytes in and
/// reads snapshots and input encodings back out. On Web (no dart:ffi) the
/// stub reports the emulator as unavailable and callers keep mock data.
library;

import 'dart:typed_data';

import 'term_stub.dart' if (dart.library.ffi) 'term_impl.dart' as platform;

/// Per-cell flags from `td_term_snapshot` (see the enum in term_ffi.c).
abstract final class TermFlags {
  static const bold = 1 << 0;
  static const italic = 1 << 1;
  static const faint = 1 << 2;
  static const underline = 1 << 3;
  static const strike = 1 << 4;
  static const inverse = 1 << 5;
  static const invisible = 1 << 6;
  static const wide = 1 << 7;
  static const spacer = 1 << 8;
  static const selected = 1 << 9;
  static const hasFg = 1 << 10;
  static const hasBg = 1 << 11;
  static const multi = 1 << 12;
}

/// `GhosttyRenderStateCursorVisualStyle`.
abstract final class CursorStyle {
  static const bar = 0;
  static const block = 1;
  static const underline = 2;
  static const blockHollow = 3;
}

/// Indices into [TermSnapshot.meta].
abstract final class TermMeta {
  static const cols = 0;
  static const rows = 1;
  static const cursorVisible = 2;
  static const cursorX = 3;
  static const cursorY = 4;
  static const cursorStyle = 5;
  static const fg = 6;
  static const bg = 7;
  static const cursorColor = 8;
  static const scrollTotal = 9;
  static const scrollOffset = 10;
  static const scrollLen = 11;
  static const titleChanged = 12;
  static const mouseTracking = 13;
  static const alternateScreen = 14;
  static const effects = 15;
}

/// One frame of the terminal grid. [cells] holds four ints per cell:
/// codepoint, fg, bg, [TermFlags]. Colors are `0xAARRGGBB`.
class TermSnapshot {
  const TermSnapshot({
    required this.cols,
    required this.rows,
    required this.cells,
    required this.meta,
    this.graphemes = const {},
  });

  final int cols;
  final int rows;
  final Int32List cells;
  final Int32List meta;

  /// Multi-codepoint graphemes by cell index (y * cols + x).
  final Map<int, String> graphemes;

  int get cursorX => meta[TermMeta.cursorX];
  int get cursorY => meta[TermMeta.cursorY];
  bool get cursorVisible => meta[TermMeta.cursorVisible] != 0;
  int get cursorStyle => meta[TermMeta.cursorStyle];
  int get defaultFg => meta[TermMeta.fg];
  int get defaultBg => meta[TermMeta.bg];
  int get cursorColor => meta[TermMeta.cursorColor];
  int get scrollTotal => meta[TermMeta.scrollTotal];
  int get scrollOffset => meta[TermMeta.scrollOffset];
  int get scrollLen => meta[TermMeta.scrollLen];
  bool get mouseTracking => meta[TermMeta.mouseTracking] != 0;
  bool get alternateScreen => meta[TermMeta.alternateScreen] != 0;

  int _at(int x, int y, int field) => cells[(y * cols + x) * 4 + field];

  int codepointAt(int x, int y) => _at(x, y, 0);
  int fgAt(int x, int y) => _at(x, y, 1);
  int bgAt(int x, int y) => _at(x, y, 2);
  int flagsAt(int x, int y) => _at(x, y, 3);
  String? graphemeAt(int x, int y) => graphemes[y * cols + x];
}

/// Bytes the remote (or a local test) should receive.
typedef TermReply = Uint8List;

/// A libghostty-vt terminal. All methods are synchronous; the shim serializes
/// access with its own mutex.
abstract class NativeTerm {
  int get cols;
  int get rows;

  /// Feeds remote output; the result is any response to send back.
  TermReply? write(Uint8List data);
  TermReply? resize(int cols, int rows, int cellWidth, int cellHeight);
  TermSnapshot snapshot();
  void scroll(int delta);

  /// GhosttyKey code, GhosttyMods bitmask (see `ghostty/vt/key.h`).
  TermReply? encodeKey(int key, int mods, {String? text, int unshifted = 0});
  TermReply? encodeMouse({
    required int action,
    required int button,
    required bool pressed,
    required double x,
    required double y,
    required int width,
    required int height,
    required int cellWidth,
    required int cellHeight,
  });
  TermReply? encodeFocus(bool gained);
  TermReply? encodePaste(Uint8List data);
  TermReply? takeClipboard();

  void select(int x0, int y0, int x1, int y1);
  String? selectionText();
  String? title();
  int codepointWidth(int codepoint);

  void dispose();
}

/// False on Web and when the shared library is missing.
bool get nativeTermSupported => platform.termSupported;

/// True when a terminal can actually be created on this host.
bool get nativeTermAvailable => platform.termAvailable;

/// Null on Web or when `libtaildeck_term.so` is not next to the executable.
NativeTerm? createNativeTerm({
  int cols = 80,
  int rows = 24,
  int scrollback = 10000,
  int fg = 0xFFE7E9ED,
  int bg = 0xFF0F1113,
  int cursor = 0xFF8FD3A8,
  String? libraryPath,
}) => platform.createPlatformTerm(
  cols: cols,
  rows: rows,
  scrollback: scrollback,
  fg: fg,
  bg: bg,
  cursor: cursor,
  libraryPath: libraryPath,
);
