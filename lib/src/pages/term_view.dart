import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../native/term.dart';

/// Owns one libghostty-vt terminal and notifies when a new snapshot is ready.
class TerminalSession extends ChangeNotifier {
  TerminalSession(this.term) : _snapshot = term.snapshot();

  final NativeTerm term;
  TermSnapshot _snapshot;
  TermSnapshot get snapshot => _snapshot;

  /// Called after the emulator grid changed, so an SSH session can follow.
  void Function(int cols, int rows)? onResize;

  /// Feeds remote output; returns the bytes the remote should get back.
  Uint8List? feed(Uint8List bytes) {
    final reply = term.write(bytes);
    _refresh();
    return reply;
  }

  void scroll(int delta) {
    term.scroll(delta);
    _refresh();
  }

  void resize(int cols, int rows, int cellWidth, int cellHeight) {
    if (cols == term.cols && rows == term.rows) return;
    term.resize(cols, rows, cellWidth, cellHeight);
    onResize?.call(cols, rows);
    _refresh();
  }

  String? get title => term.title();

  void _refresh() {
    _snapshot = term.snapshot();
    notifyListeners();
  }

  @override
  void dispose() {
    term.dispose();
    super.dispose();
  }
}

/// Monospace cell metrics for one font size.
class _Metrics {
  _Metrics(double fontSize)
    : style = const TextStyle(
        fontFamily: 'DejaVuSansMono',
        fontFamilyFallback: ['NotoSansCJK'],
        height: 1.0,
      ).copyWith(fontSize: fontSize) {
    final painter = TextPainter(
      text: TextSpan(text: 'M', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    cellWidth = painter.width;
    final line = painter.computeLineMetrics().first;
    cellHeight = math.max(line.height, fontSize);
    ascent = line.ascent;
    painter.dispose();
  }

  final TextStyle style;
  late final double cellWidth;
  late final double cellHeight;
  late final double ascent;
}

/// Paints terminal snapshots on a fixed grid and resizes the emulator to the
/// available cells.
class TerminalCanvas extends StatefulWidget {
  const TerminalCanvas({
    super.key,
    required this.session,
    this.fontSize = 13.5,
    this.padding = const EdgeInsets.fromLTRB(18, 10, 18, 10),
  });

  final TerminalSession session;
  final double fontSize;
  final EdgeInsets padding;

  @override
  State<TerminalCanvas> createState() => _TerminalCanvasState();
}

class _TerminalCanvasState extends State<TerminalCanvas> {
  late _Metrics _metrics = _Metrics(widget.fontSize);

  @override
  void didUpdateWidget(TerminalCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fontSize != widget.fontSize) {
      _metrics = _Metrics(widget.fontSize);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Leave room for padding, so the last row and column are never clipped.
        final cols = math.max(
          1,
          ((constraints.maxWidth - widget.padding.horizontal) / _metrics.cellWidth).floor(),
        );
        final rows = math.max(
          1,
          ((constraints.maxHeight - widget.padding.vertical) / _metrics.cellHeight).floor(),
        );
        _scheduleResize(cols, rows);
        return ClipRect(
          child: ListenableBuilder(
            listenable: widget.session,
            builder: (context, _) => CustomPaint(
              painter: _GridPainter(
                snapshot: widget.session.snapshot,
                metrics: _metrics,
                origin: Offset(widget.padding.left, widget.padding.top),
              ),
              size: Size.infinite,
            ),
          ),
        );
      },
    );
  }

  void _scheduleResize(int cols, int rows) {
    if (cols == widget.session.term.cols && rows == widget.session.term.rows) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.session.resize(
        cols,
        rows,
        _metrics.cellWidth.ceil(),
        _metrics.cellHeight.ceil(),
      );
    });
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({required this.snapshot, required this.metrics, required this.origin});

  final TermSnapshot snapshot;
  final _Metrics metrics;
  final Offset origin;

  static const _selectionBg = Color(0xFF2C4A38);
  static const _selectionFg = Color(0xFFFFFFFF);
  static const _cursorFallback = Color(0xFF8FD3A8);

  double get _cw => metrics.cellWidth;
  double get _ch => metrics.cellHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final brush = Paint()..isAntiAlias = false;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Color(snapshot.defaultBg),
    );
    final gridWidth = math.min(size.width, snapshot.cols * _cw + origin.dx);
    final gridHeight = math.min(size.height, snapshot.rows * _ch + origin.dy);
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, gridWidth, gridHeight));

    _paintBackgrounds(canvas, brush);
    _paintText(canvas);
    _paintCursor(canvas, brush);
    _paintScrollbar(canvas, brush, size);
    canvas.restore();
  }

  int _bgOf(int x, int y) {
    final flags = snapshot.flagsAt(x, y);
    if (flags & TermFlags.selected != 0) return _selectionBg.toARGB32();
    if (flags & TermFlags.inverse != 0) {
      return flags & TermFlags.hasFg != 0
          ? snapshot.fgAt(x, y)
          : snapshot.defaultFg;
    }
    return flags & TermFlags.hasBg != 0 ? snapshot.bgAt(x, y) : snapshot.defaultBg;
  }

  Color _fgOf(int x, int y) {
    final flags = snapshot.flagsAt(x, y);
    var value = flags & TermFlags.hasFg != 0 ? snapshot.fgAt(x, y) : snapshot.defaultFg;
    if (flags & TermFlags.inverse != 0) {
      value = flags & TermFlags.hasBg != 0 ? snapshot.bgAt(x, y) : snapshot.defaultBg;
    }
    if (flags & TermFlags.selected != 0) return _selectionFg;
    if (flags & TermFlags.faint != 0) return Color(value & 0xFFFFFF).withValues(alpha: 0.6);
    return Color(value);
  }

  void _paintBackgrounds(Canvas canvas, Paint brush) {
    final defaultBg = snapshot.defaultBg;
    for (var y = 0; y < snapshot.rows; y++) {
      final top = origin.dy + y * _ch;
      for (var x = 0; x < snapshot.cols; x++) {
        final flags = snapshot.flagsAt(x, y);
        if (flags & TermFlags.spacer != 0) continue;
        final bg = _bgOf(x, y);
        if (bg == defaultBg) continue;
        // A wide glyph's background covers its spacer cell too.
        final span = flags & TermFlags.wide != 0 ? 2 : 1;
        brush.color = Color(bg);
        canvas.drawRect(
          Rect.fromLTWH(origin.dx + x * _cw, top, span * _cw + 0.5, _ch),
          brush,
        );
      }
    }
  }

  String _textOf(int x, int y) {
    final multi = snapshot.graphemeAt(x, y);
    if (multi != null) return multi;
    return String.fromCharCode(snapshot.codepointAt(x, y));
  }

  TextStyle _styleFor(int x, int y, Color color) {
    final flags = snapshot.flagsAt(x, y);
    return metrics.style.copyWith(
      color: color,
      fontWeight: flags & TermFlags.bold != 0 ? FontWeight.w700 : FontWeight.w400,
      fontStyle: flags & TermFlags.italic != 0 ? FontStyle.italic : FontStyle.normal,
      decoration: TextDecoration.none,
    );
  }

  bool _sameStyle(int x, int y, int refX, int refY) {
    const mask = TermFlags.bold |
        TermFlags.italic |
        TermFlags.faint |
        TermFlags.inverse |
        TermFlags.selected;
    if (snapshot.flagsAt(x, y) & mask != snapshot.flagsAt(refX, refY) & mask) {
      return false;
    }
    final a = _fgOf(x, y);
    final b = _fgOf(refX, refY);
    return a.toARGB32() == b.toARGB32();
  }

  void _paintText(Canvas canvas) {
    for (var y = 0; y < snapshot.rows; y++) {
      final top = origin.dy + y * _ch;
      var x = 0;
      while (x < snapshot.cols) {
        final flags = snapshot.flagsAt(x, y);
        final cp = snapshot.codepointAt(x, y);
        if (cp <= 32 ||
            flags & TermFlags.spacer != 0 ||
            flags & TermFlags.invisible != 0) {
          _paintDecoration(canvas, x, 1, top, flags, _fgOf(x, y));
          x++;
          continue;
        }
        final wide = flags & TermFlags.wide != 0;
        final span = wide ? 2 : 1;
        final text = _textOf(x, y);
        final color = _fgOf(x, y);
        // Batch plain ASCII runs of one style into a single draw.
        if (text.length == 1 && cp < 0x7F && flags & TermFlags.multi == 0) {
          final run = StringBuffer();
          var j = x;
          while (j < snapshot.cols) {
            final fj = snapshot.flagsAt(j, y);
            final cpj = snapshot.codepointAt(j, y);
            if (cpj < 32 ||
                cpj >= 0x7F ||
                fj & (TermFlags.spacer | TermFlags.multi | TermFlags.invisible) != 0 ||
                !_sameStyle(j, y, x, y)) {
              break;
            }
            run.writeCharCode(cpj);
            j++;
          }
          final painter = TextPainter(
            text: TextSpan(text: run.toString(), style: _styleFor(x, y, color)),
            textDirection: TextDirection.ltr,
            maxLines: 1,
          )..layout();
          painter.paint(canvas, Offset(origin.dx + x * _cw, top));
          painter.dispose();
          _paintDecoration(canvas, x, j - x, top, flags, color);
          x = j;
          continue;
        }
        final painter = TextPainter(
          text: TextSpan(text: text, style: _styleFor(x, y, color)),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        // Wide glyphs center in their two cells; single ones fill one.
        final left = origin.dx + x * _cw + math.max(0, (span * _cw - painter.width) / 2);
        painter.paint(canvas, Offset(left, top));
        painter.dispose();
        _paintDecoration(canvas, x, span, top, flags, color);
        x += span;
      }
    }
  }

  void _paintDecoration(Canvas canvas, int x, int cells, double top, int flags, Color color) {
    if (flags & (TermFlags.underline | TermFlags.strike) == 0) return;
    final brush = Paint()..color = color;
    final thick = math.max(1.0, _ch / 14);
    final left = origin.dx + x * _cw;
    final right = left + cells * _cw;
    if (flags & TermFlags.underline != 0) {
      canvas.drawRect(
        Rect.fromLTRB(left, top + _ch - thick * 1.5, right, top + _ch - thick * 0.5),
        brush,
      );
    }
    if (flags & TermFlags.strike != 0) {
      final mid = top + _ch / 2;
      canvas.drawRect(Rect.fromLTRB(left, mid - thick / 2, right, mid + thick / 2), brush);
    }
  }

  void _paintCursor(Canvas canvas, Paint brush) {
    if (!snapshot.cursorVisible) return;
    final x = snapshot.cursorX;
    final y = snapshot.cursorY;
    if (x < 0 || y < 0 || x >= snapshot.cols || y >= snapshot.rows) return;
    final flags = snapshot.flagsAt(x, y);
    final left = origin.dx + x * _cw;
    final top = origin.dy + y * _ch;
    final right = left + (flags & TermFlags.wide != 0 ? 2 : 1) * _cw;
    brush.color = snapshot.cursorColor != 0
        ? Color(snapshot.cursorColor | 0xFF000000)
        : _cursorFallback;
    final bar = math.max(2.0, _cw / 6);
    switch (snapshot.cursorStyle) {
      case CursorStyle.bar:
        canvas.drawRect(Rect.fromLTWH(left, top, bar, _ch), brush);
      case CursorStyle.underline:
        canvas.drawRect(Rect.fromLTRB(left, top + _ch - bar, right, top + _ch), brush);
      case CursorStyle.blockHollow:
        brush
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
        canvas.drawRect(Rect.fromLTRB(left + 0.5, top + 0.5, right - 0.5, top + _ch - 0.5), brush);
        brush.style = PaintingStyle.fill;
      default:
        canvas.drawRect(Rect.fromLTRB(left, top, right, top + _ch), brush);
        // Keep the glyph under a block cursor readable.
        final cp = snapshot.codepointAt(x, y);
        if (cp > 32) {
          final painter = TextPainter(
            text: TextSpan(
              text: _textOf(x, y),
              style: _styleFor(x, y, Color(snapshot.defaultBg)),
            ),
            textDirection: TextDirection.ltr,
            maxLines: 1,
          )..layout();
          painter.paint(canvas, Offset(left, top));
          painter.dispose();
        }
    }
  }

  void _paintScrollbar(Canvas canvas, Paint brush, Size size) {
    final total = snapshot.scrollTotal;
    final offset = snapshot.scrollOffset;
    final len = snapshot.scrollLen;
    if (total <= len || offset + len >= total) return;
    final height = math.max(0.0, size.height - origin.dy);
    final top = origin.dy + height * offset / total;
    final bottom = math.max(top + 24, origin.dy + height * (offset + len) / total);
    brush.color = const Color(0x66FFFFFF);
    canvas.drawRect(Rect.fromLTRB(size.width - 6, top, size.width - 2, bottom), brush);
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.snapshot != snapshot || old.metrics != metrics || old.origin != origin;
}
