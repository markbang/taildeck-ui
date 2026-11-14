import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../l10n.dart';
import '../native/term.dart';
import '../terminal_gestures.dart';

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

  /// Re-reads the grid, e.g. after the selection changed.
  void refresh() => _refresh();

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

/// Paints terminal snapshots on a fixed grid, resizes the emulator to the
/// available cells, and turns finger gestures on that grid into terminal
/// input: swipe arrows, word selection with draggable handles, and pinch zoom.
class TerminalCanvas extends StatefulWidget {
  const TerminalCanvas({
    super.key,
    required this.session,
    this.fontSize = terminalFontDefault,
    this.padding = const EdgeInsets.fromLTRB(18, 10, 18, 10),
    this.swipeArrows = true,
    this.onArrow,
    this.onFontSize,
    this.onFocus,
    this.onOpenUrl,
    this.onPaste,
  });

  final TerminalSession session;
  final double fontSize;
  final EdgeInsets padding;

  /// One-finger swipe sends arrow keys; off, a vertical drag walks the
  /// scrollback instead.
  final bool swipeArrows;

  /// A swipe crossed one step along its axis.
  final ValueChanged<TerminalArrow>? onArrow;

  /// The font size a pinch asks for, already inside the zoom limits.
  final ValueChanged<double>? onFontSize;

  /// A tap on the grid, for the soft keyboard.
  final VoidCallback? onFocus;

  /// Opens the URL a selection holds; false when it did not open.
  final Future<bool> Function(String url)? onOpenUrl;

  /// Pastes the clipboard through the emulator's encoder.
  final VoidCallback? onPaste;

  @override
  State<TerminalCanvas> createState() => _TerminalCanvasState();
}

class _TerminalCanvasState extends State<TerminalCanvas> {
  late _Metrics _metrics = _Metrics(widget.fontSize);
  final _gridKey = GlobalKey();
  final _swipe = SwipeStepper();
  GridSelection? _selection;
  Offset? _doubleTapAt;
  double _pinchStart = terminalFontDefault;
  bool _pinching = false;
  double _scrollCarry = 0;
  double _height = 0;
  String _notice = '';
  Timer? _noticeTimer;

  @override
  void didUpdateWidget(TerminalCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fontSize != widget.fontSize) {
      _metrics = _Metrics(widget.fontSize);
    }
    if (oldWidget.session != widget.session) _selection = null;
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _height = constraints.maxHeight;
        // Leave room for padding, so the last row and column are never clipped.
        final cols = math.max(
          1,
          ((constraints.maxWidth - widget.padding.horizontal) /
                  _metrics.cellWidth)
              .floor(),
        );
        final rows = math.max(
          1,
          ((constraints.maxHeight - widget.padding.vertical) /
                  _metrics.cellHeight)
              .floor(),
        );
        _scheduleResize(cols, rows);
        return ClipRect(
          child: ListenableBuilder(
            listenable: widget.session,
            builder: (context, _) {
              final snapshot = widget.session.snapshot;
              final selection = _selection;
              return Stack(
                key: _gridKey,
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: _onTap,
                      onDoubleTapDown: (details) =>
                          _doubleTapAt = details.localPosition,
                      onDoubleTap: _onDoubleTap,
                      onLongPressStart: (details) =>
                          _selectWord(details.localPosition),
                      onScaleStart: (_) {
                        _swipe.reset();
                        _scrollCarry = 0;
                        _pinching = false;
                      },
                      onScaleUpdate: _onScaleUpdate,
                      child: CustomPaint(
                        painter: _GridPainter(
                          snapshot: snapshot,
                          metrics: _metrics,
                          origin: Offset(
                            widget.padding.left,
                            widget.padding.top,
                          ),
                        ),
                        size: Size.infinite,
                      ),
                    ),
                  ),
                  if (selection != null) ..._handles(snapshot, selection),
                  if (selection != null) _toolbar(snapshot, selection),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _onTap(TapUpDetails details) {
    if (_selection != null) {
      _clearSelection();
      return;
    }
    widget.onFocus?.call();
  }

  void _onDoubleTap() {
    final at = _doubleTapAt;
    if (at != null) _selectWord(at);
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount >= 2) {
      final onFontSize = widget.onFontSize;
      if (onFontSize == null) return;
      if (!_pinching) {
        _pinching = true;
        _pinchStart = widget.fontSize;
      }
      final next = clampTerminalFont(_pinchStart * details.scale);
      if ((next - widget.fontSize).abs() >= 0.5) onFontSize(next);
      return;
    }
    final selection = _selection;
    if (selection != null) {
      _extendSelection(details.localFocalPoint);
      return;
    }
    if (widget.swipeArrows) {
      for (final arrow in _swipe.update(details.focalPointDelta)) {
        widget.onArrow?.call(arrow);
      }
      return;
    }
    _scrollCarry += details.focalPointDelta.dy;
    final lines = (_scrollCarry / _metrics.cellHeight).truncate();
    if (lines == 0) return;
    _scrollCarry -= lines * _metrics.cellHeight;
    widget.session.scroll(lines);
  }

  (int, int) _cellAt(Offset local, TermSnapshot snapshot) {
    final columns = math.max(1, snapshot.cols);
    final x = ((local.dx - widget.padding.left) / _metrics.cellWidth)
        .floor()
        .clamp(0, columns - 1)
        .toInt();
    final y = ((local.dy - widget.padding.top) / _metrics.cellHeight)
        .floor()
        .clamp(0, math.max(0, snapshot.rows - 1))
        .toInt();
    return (x, y);
  }

  Offset _cellOrigin(int x, int y) => Offset(
    widget.padding.left + x * _metrics.cellWidth,
    widget.padding.top + y * _metrics.cellHeight,
  );

  /// Selects the word under [local]; a long press and a double tap both land
  /// here.
  void _selectWord(Offset local) {
    final snapshot = widget.session.snapshot;
    final columns = snapshot.cols;
    if (snapshot.rows == 0 || columns == 0) return;
    final (x, y) = _cellAt(local, snapshot);
    bool filled(int column) {
      final index = (y * columns + column) * 4;
      if (index + 3 >= snapshot.cells.length) return false;
      if (snapshot.cells[index + 3] & TermFlags.spacer != 0) return false;
      return snapshot.cells[index] > 32;
    }

    final range = wordRange(x, columns, filled);
    _applySelection(GridSelection(range.from, y, range.to, y));
    unawaited(HapticFeedback.mediumImpact());
  }

  void _extendSelection(Offset local) {
    final selection = _selection;
    if (selection == null) return;
    final (x, y) = _cellAt(local, widget.session.snapshot);
    if (x == selection.endX && y == selection.endY) return;
    _applySelection(selection.withEnd(x, y));
  }

  void _dragHandle(Offset global, {required bool start}) {
    final selection = _selection;
    final box = _gridKey.currentContext?.findRenderObject();
    if (selection == null || box is! RenderBox) return;
    final (x, y) = _cellAt(box.globalToLocal(global), widget.session.snapshot);
    final next = start ? selection.withStart(x, y) : selection.withEnd(x, y);
    if (start
        ? next.startX == selection.startX && next.startY == selection.startY
        : next.endX == selection.endX && next.endY == selection.endY) {
      return;
    }
    unawaited(HapticFeedback.selectionClick());
    _applySelection(next);
  }

  void _applySelection(GridSelection selection) {
    widget.session.term.select(
      selection.startX,
      selection.startY,
      selection.endX,
      selection.endY,
    );
    widget.session.refresh();
    setState(() => _selection = selection);
  }

  void _clearSelection() {
    widget.session.term.select(-1, 0, 0, 0);
    widget.session.refresh();
    setState(() => _selection = null);
  }

  List<Widget> _handles(TermSnapshot snapshot, GridSelection selection) {
    final start = _cellOrigin(selection.startX, selection.startY);
    final end = _cellOrigin(selection.endX, selection.endY);
    return [
      _handle(
        Offset(
          start.dx + _metrics.cellWidth / 2,
          start.dy + _metrics.cellHeight,
        ),
        start: true,
      ),
      _handle(
        Offset(end.dx + _metrics.cellWidth / 2, end.dy + _metrics.cellHeight),
        start: false,
      ),
    ];
  }

  Widget _handle(Offset anchor, {required bool start}) {
    const size = 34.0;
    return Positioned(
      left: anchor.dx - size / 2,
      top: anchor.dy - 4,
      width: size,
      height: size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onPanUpdate: (details) =>
            _dragHandle(details.globalPosition, start: start),
        child: Center(
          child: Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              color: const Color(0xFF57D7A0),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF0B0D10), width: 2),
            ),
          ),
        ),
      ),
    );
  }

  Widget _toolbar(TermSnapshot snapshot, GridSelection selection) {
    final l10n = AppLocalizations.of(context);
    final text = widget.session.term.selectionText();
    final url = urlInSelection(text);
    const gap = 10.0;
    final top = (widget.padding.top + selection.top * _metrics.cellHeight - 46)
        .clamp(4.0, math.max(4.0, _height - 46))
        .toDouble();
    return Positioned(
      left: 0,
      right: 0,
      top: top,
      child: Center(
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          label: l10n.terminalSelection,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: const Color(0xF21A1E25),
              shape: StadiumBorder(
                side: BorderSide(color: const Color(0x26FFFFFF), width: 0.5),
              ),
              shadows: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_notice.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        _notice,
                        style: const TextStyle(
                          fontFamily: 'DejaVuSansMono',
                          fontSize: 12,
                          color: Color(0xFF57D7A0),
                          decoration: TextDecoration.none,
                        ),
                      ),
                    )
                  else ...[
                    _ToolButton(label: l10n.copy, onTap: _copy),
                    if (url != null) ...[
                      const SizedBox(width: gap / 2),
                      _ToolButton(
                        label: l10n.terminalOpenLink,
                        onTap: () => unawaited(_open(url)),
                      ),
                    ],
                    if (widget.onPaste != null) ...[
                      const SizedBox(width: gap / 2),
                      _ToolButton(label: l10n.paste, onTap: widget.onPaste!),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _copy() async {
    final text = widget.session.term.selectionText();
    if (text == null || text.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    unawaited(HapticFeedback.lightImpact());
    _flash(AppLocalizations.of(context).terminalCopied);
  }

  Future<void> _open(String url) async {
    final opened = await (widget.onOpenUrl?.call(url) ?? Future.value(false));
    if (!mounted || opened) return;
    _flash(AppLocalizations.of(context).terminalOpenFailed);
  }

  void _flash(String message) {
    _noticeTimer?.cancel();
    setState(() => _notice = message);
    _noticeTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _notice = '');
    });
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

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'DejaVuSansMono',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFFE7E9ED),
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.snapshot,
    required this.metrics,
    required this.origin,
  });

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
    return flags & TermFlags.hasBg != 0
        ? snapshot.bgAt(x, y)
        : snapshot.defaultBg;
  }

  Color _fgOf(int x, int y) {
    final flags = snapshot.flagsAt(x, y);
    var value = flags & TermFlags.hasFg != 0
        ? snapshot.fgAt(x, y)
        : snapshot.defaultFg;
    if (flags & TermFlags.inverse != 0) {
      value = flags & TermFlags.hasBg != 0
          ? snapshot.bgAt(x, y)
          : snapshot.defaultBg;
    }
    if (flags & TermFlags.selected != 0) return _selectionFg;
    if (flags & TermFlags.faint != 0) {
      return Color(value & 0xFFFFFF).withValues(alpha: 0.6);
    }
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
      fontWeight: flags & TermFlags.bold != 0
          ? FontWeight.w700
          : FontWeight.w400,
      fontStyle: flags & TermFlags.italic != 0
          ? FontStyle.italic
          : FontStyle.normal,
      decoration: TextDecoration.none,
    );
  }

  bool _sameStyle(int x, int y, int refX, int refY) {
    const mask =
        TermFlags.bold |
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
                fj &
                        (TermFlags.spacer |
                            TermFlags.multi |
                            TermFlags.invisible) !=
                    0 ||
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
        final left =
            origin.dx + x * _cw + math.max(0, (span * _cw - painter.width) / 2);
        painter.paint(canvas, Offset(left, top));
        painter.dispose();
        _paintDecoration(canvas, x, span, top, flags, color);
        x += span;
      }
    }
  }

  void _paintDecoration(
    Canvas canvas,
    int x,
    int cells,
    double top,
    int flags,
    Color color,
  ) {
    if (flags & (TermFlags.underline | TermFlags.strike) == 0) return;
    final brush = Paint()..color = color;
    final thick = math.max(1.0, _ch / 14);
    final left = origin.dx + x * _cw;
    final right = left + cells * _cw;
    if (flags & TermFlags.underline != 0) {
      canvas.drawRect(
        Rect.fromLTRB(
          left,
          top + _ch - thick * 1.5,
          right,
          top + _ch - thick * 0.5,
        ),
        brush,
      );
    }
    if (flags & TermFlags.strike != 0) {
      final mid = top + _ch / 2;
      canvas.drawRect(
        Rect.fromLTRB(left, mid - thick / 2, right, mid + thick / 2),
        brush,
      );
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
        canvas.drawRect(
          Rect.fromLTRB(left, top + _ch - bar, right, top + _ch),
          brush,
        );
      case CursorStyle.blockHollow:
        brush
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
        canvas.drawRect(
          Rect.fromLTRB(left + 0.5, top + 0.5, right - 0.5, top + _ch - 0.5),
          brush,
        );
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
    final bottom = math.max(
      top + 24,
      origin.dy + height * (offset + len) / total,
    );
    brush.color = const Color(0x66FFFFFF);
    canvas.drawRect(
      Rect.fromLTRB(size.width - 6, top, size.width - 2, bottom),
      brush,
    );
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.snapshot != snapshot ||
      old.metrics != metrics ||
      old.origin != origin;
}
