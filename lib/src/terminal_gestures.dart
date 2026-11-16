/// Grid gestures for the terminal: one-finger swipe to arrow keys, the word
/// under a finger, the cell range a selection covers and the URL it may hold.
library;

import 'dart:math' as math;
import 'dart:ui';

/// Arrow a swipe sends.
enum TerminalArrow { up, down, left, right }

/// The axis a swipe locked onto.
enum SwipeAxis { horizontal, vertical }

/// One-finger drag to arrow keys. The axis is chosen once the finger passed
/// [slop], then every [step] px along it sends one key; movement across the
/// chosen axis is ignored, so a shaky swipe never zig-zags.
class SwipeStepper {
  SwipeStepper({this.step = 26, this.slop = 8, this.maxPerUpdate = 3});

  final double step;
  final double slop;

  /// A fast flick would otherwise flood the remote with dozens of keys.
  final int maxPerUpdate;

  SwipeAxis? _axis;
  double _carry = 0;
  Offset _total = Offset.zero;

  /// The axis this gesture locked onto; null until it moved far enough.
  SwipeAxis? get axis => _axis;

  void reset() {
    _axis = null;
    _carry = 0;
    _total = Offset.zero;
  }

  /// Arrows [delta] just earned, in drag order.
  List<TerminalArrow> update(Offset delta) {
    final axis = _axis;
    if (axis == null) {
      _total += delta;
      if (_total.distance < slop) return const [];
      _axis = _total.dx.abs() >= _total.dy.abs()
          ? SwipeAxis.horizontal
          : SwipeAxis.vertical;
      _carry = _axis == SwipeAxis.horizontal ? _total.dx : _total.dy;
    } else {
      _carry += axis == SwipeAxis.horizontal ? delta.dx : delta.dy;
    }
    final out = <TerminalArrow>[];
    while (_carry.abs() >= step && out.length < maxPerUpdate) {
      final forward = _carry > 0;
      _carry -= forward ? step : -step;
      out.add(
        _axis == SwipeAxis.horizontal
            ? (forward ? TerminalArrow.right : TerminalArrow.left)
            : (forward ? TerminalArrow.down : TerminalArrow.up),
      );
    }
    return out;
  }
}

/// A terminal selection: the cell it started on and the cell it reaches.
class GridSelection {
  const GridSelection(this.startX, this.startY, this.endX, this.endY);

  final int startX;
  final int startY;
  final int endX;
  final int endY;

  int get left => math.min(startX, endX);
  int get right => math.max(startX, endX);
  int get top => math.min(startY, endY);
  int get bottom => math.max(startY, endY);

  GridSelection withStart(int x, int y) => GridSelection(x, y, endX, endY);

  GridSelection withEnd(int x, int y) => GridSelection(startX, startY, x, y);

  @override
  String toString() => 'GridSelection($startX,$startY -> $endX,$endY)';
}

/// Column range of the word under [x]: the run of filled cells around it.
({int from, int to}) wordRange(int x, int columns, bool Function(int) filled) {
  final seed = x.clamp(0, columns - 1);
  if (!filled(seed)) return (from: seed, to: seed);
  var from = seed;
  var to = seed;
  while (from > 0 && filled(from - 1)) {
    from--;
  }
  while (to < columns - 1 && filled(to + 1)) {
    to++;
  }
  return (from: from, to: to);
}

/// The word under [x] when wide (CJK) characters own a spacer cell: the run
/// continues through the spacer, so 你好 is one word and not just 你.
({int from, int to}) wordRangeWithSpacers(
  int x,
  int columns, {
  required bool Function(int) hasText,
  required bool Function(int) spacer,
}) {
  bool filled(int column) {
    if (spacer(column)) return column > 0 && hasText(column - 1);
    return hasText(column);
  }

  return wordRange(x, columns, filled);
}

const _trailingPunctuation = '.,;:!?\'")]}';

/// The URL when the whole selection is one http(s) link, else null. Trailing
/// sentence punctuation is not part of the link.
String? urlInSelection(String? text) {
  if (text == null) return null;
  var trimmed = text.trim();
  while (trimmed.isNotEmpty &&
      _trailingPunctuation.contains(trimmed[trimmed.length - 1])) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  final lower = trimmed.toLowerCase();
  if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
    return null;
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.host.isEmpty) return null;
  return trimmed;
}

/// Zoom limits shared by the pinch and Settings.
const terminalFontMin = 8.0;
const terminalFontMax = 24.0;
const terminalFontDefault = 13.0;

double clampTerminalFont(double size) =>
    size.clamp(terminalFontMin, terminalFontMax).toDouble();
