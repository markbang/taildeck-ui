import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../l10n.dart';
import '../native/term.dart';
import '../term_session.dart';
import '../terminal_appearance.dart';
import '../terminal_gestures.dart';

/// Monospace cell metrics for one font family at one size.
class _Metrics {
  _Metrics(this.fontSize, this.family, this.fallback)
    : style = TextStyle(
        fontFamily: family,
        fontFamilyFallback: fallback,
        height: 1.0,
        fontSize: fontSize,
      ) {
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

  final double fontSize;
  final String family;
  final List<String> fallback;
  final TextStyle style;
  late final double cellWidth;
  late final double cellHeight;
  late final double ascent;
}

/// Paints terminal snapshots on a fixed grid, resizes the emulator to the
/// available cells, and turns finger gestures on that grid into terminal
/// input: drag scrolling, word selection with draggable handles, and pinch
/// zoom.
class TerminalCanvas extends StatefulWidget {
  const TerminalCanvas({
    super.key,
    required this.session,
    this.fontSize = terminalFontDefault,
    this.fontFamily = 'DejaVuSansMono',
    this.fontFallback = terminalFontFallback,
    this.palette = defaultTerminalPalette,
    this.cursor = TerminalCursorId.follow,
    this.cursorBlink = true,
    this.padding = const EdgeInsets.fromLTRB(18, 10, 18, 10),
    this.liveResize = true,
    this.onFontSize,
    this.onBytes,
    this.onMouseSent,
    this.mouseMods = 0,
    this.onOpenUrl,
    this.onPaste,
  });

  final TerminalSession session;
  final double fontSize;

  /// Family, fallback and palette come from Settings → Terminal; the grid
  /// measures the family, so cells change width with it.
  final String fontFamily;
  final List<String> fontFallback;
  final TerminalPalette palette;

  /// Shape and blink of the cursor; [TerminalCursorId.follow] keeps the
  /// program's DECSCUSR request.
  final TerminalCursorId cursor;
  final bool cursorBlink;

  final EdgeInsets padding;

  /// False while the keyboard inset animates: the grid is laid out at each
  /// frame of the tween, but the emulator (and the PTY) resize once, at the
  /// end, so a keyboard animation is one resize and not a dozen.
  final bool liveResize;

  /// The font size a pinch asks for, already inside the zoom limits.
  final ValueChanged<double>? onFontSize;

  /// Bytes a mouse report wrote, for the page to hand to the remote.
  final ValueChanged<Uint8List>? onBytes;

  /// Called once after a click's press and release went out, so the page can
  /// clear the sticky modifier that carried it.
  final VoidCallback? onMouseSent;

  /// GhosttyMods bits a click carries, from the key row's sticky modifiers.
  final int mouseMods;

  /// Opens the URL a selection holds; false when it did not open.
  final Future<bool> Function(String url)? onOpenUrl;

  /// Pastes the clipboard through the emulator's encoder.
  final VoidCallback? onPaste;

  @override
  State<TerminalCanvas> createState() => _TerminalCanvasState();
}

class _TerminalCanvasState extends State<TerminalCanvas>
    with SingleTickerProviderStateMixin {
  late _Metrics _metrics = _measure();
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 530),
  );
  final _gridKey = GlobalKey();
  GridSelection? _selection;
  Offset? _doubleTapAt;
  double _pinchStart = terminalFontDefault;
  bool _pinching = false;
  double _scrollCarry = 0;
  double _height = 0;
  String _notice = '';
  Timer? _noticeTimer;

  _Metrics _measure() =>
      _Metrics(widget.fontSize, widget.fontFamily, widget.fontFallback);

  void _syncBlink() {
    final wanted =
        widget.cursorBlink &&
        widget.session.snapshot.cursorVisible &&
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (!wanted) {
      if (_blink.isAnimating) _blink.stop();
      _blink.value = 1;
      return;
    }
    if (!_blink.isAnimating) _blink.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(TerminalCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fontSize != widget.fontSize ||
        oldWidget.fontFamily != widget.fontFamily ||
        oldWidget.fontFallback != widget.fontFallback) {
      _metrics = _measure();
    }
    if (oldWidget.session != widget.session) _selection = null;
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    _blink.dispose();
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
        if (widget.liveResize) _scheduleResize(cols, rows);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncBlink();
        });
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
                      onLongPressMoveUpdate: (details) =>
                          _extendSelection(details.localPosition),
                      onScaleStart: (_) {
                        _scrollCarry = 0;
                        _pinching = false;
                      },
                      onScaleUpdate: _onScaleUpdate,
                      onScaleEnd: (_) => _scrollCarry = 0,
                      child: CustomPaint(
                        painter: _GridPainter(
                          snapshot: snapshot,
                          metrics: _metrics,
                          palette: widget.palette,
                          origin: Offset(
                            widget.padding.left,
                            widget.padding.top,
                          ),
                        ),
                        size: Size.infinite,
                      ),
                    ),
                  ),
                  // The cursor blinks on its own layer, so a tick never
                  // repaints the grid text.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _CursorPainter(
                          snapshot: snapshot,
                          metrics: _metrics,
                          palette: widget.palette,
                          style: widget.cursor,
                          blink: widget.cursorBlink ? _blink : null,
                          origin: Offset(
                            widget.padding.left,
                            widget.padding.top,
                          ),
                        ),
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
    // A tap is not focus: no keyboard, no input line. It is only a mouse
    // click for a program that tracks the mouse.
    if (_selection != null) {
      _clearSelection();
      return;
    }
    _clickGrid(details.localPosition);
  }

  /// Reports a tap to a program that tracks the mouse (SGR 1006 and the other
  /// protocols the emulator knows), as a left press and release at the cell
  /// under the finger. A terminal without mouse reporting gets no bytes.
  void _clickGrid(Offset local) {
    if (!widget.session.snapshot.mouseTracking) return;
    for (final pressed in const [true, false]) {
      _reportMouse(
        local,
        action: pressed ? 0 : 1,
        button: TerminalMouseButton.left,
        pressed: pressed,
        mods: widget.mouseMods,
      );
    }
    widget.onMouseSent?.call();
  }

  void _reportMouse(
    Offset local, {
    required int action,
    required int button,
    required bool pressed,
    int mods = 0,
  }) {
    final snapshot = widget.session.snapshot;
    final width = (snapshot.cols * _metrics.cellWidth).ceil();
    final height = (snapshot.rows * _metrics.cellHeight).ceil();
    if (width <= 0 || height <= 0) return;
    final bytes = widget.session.term.encodeMouse(
      action: action,
      button: button,
      pressed: pressed,
      x: (local.dx - widget.padding.left).clamp(0.0, width - 1.0),
      y: (local.dy - widget.padding.top).clamp(0.0, height - 1.0),
      width: width,
      height: height,
      cellWidth: _metrics.cellWidth.ceil(),
      cellHeight: _metrics.cellHeight.ceil(),
      mods: mods,
    );
    if (bytes != null && bytes.isNotEmpty) widget.onBytes?.call(bytes);
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
    // A vertical drag never types: the content follows the finger through the
    // scrollback, or a mouse-aware program gets one wheel report per line.
    _scrollCarry += details.focalPointDelta.dy;
    final lines = (_scrollCarry / _metrics.cellHeight).truncate();
    if (lines == 0) return;
    _scrollCarry -= lines * _metrics.cellHeight;
    final snapshot = widget.session.snapshot;
    if (snapshot.mouseTracking) {
      final button = lines > 0
          ? TerminalMouseButton.wheelUp
          : TerminalMouseButton.wheelDown;
      for (var i = 0; i < lines.abs(); i++) {
        _reportMouse(
          details.localFocalPoint,
          action: 0,
          button: button,
          pressed: true,
        );
      }
      return;
    }
    // The alternate screen has no scrollback of its own.
    if (snapshot.alternateScreen) return;
    widget.session.scroll(-lines);
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
    bool inGrid(int column) {
      final index = (y * columns + column) * 4;
      return index + 3 < snapshot.cells.length;
    }

    bool hasText(int column) =>
        inGrid(column) && snapshot.cells[(y * columns + column) * 4] > 32;
    bool spacer(int column) =>
        inGrid(column) &&
        snapshot.cells[(y * columns + column) * 4 + 3] & TermFlags.spacer != 0;

    final range = wordRangeWithSpacers(
      x,
      columns,
      hasText: hasText,
      spacer: spacer,
    );
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
              color: widget.palette.accent,
              shape: BoxShape.circle,
              border: Border.all(color: widget.palette.background, width: 2),
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
              color: widget.palette.surface,
              shape: StadiumBorder(
                side: BorderSide(color: widget.palette.border, width: 0.5),
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
                        style: _metrics.style.copyWith(
                          fontSize: 12,
                          color: widget.palette.success,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    )
                  else ...[
                    _ToolButton(
                      label: l10n.copy,
                      onTap: _copy,
                      palette: widget.palette,
                    ),
                    if (url != null) ...[
                      const SizedBox(width: gap / 2),
                      _ToolButton(
                        label: l10n.terminalOpenLink,
                        onTap: () => unawaited(_open(url)),
                        palette: widget.palette,
                      ),
                    ],
                    if (widget.onPaste != null) ...[
                      const SizedBox(width: gap / 2),
                      _ToolButton(
                        label: l10n.paste,
                        onTap: widget.onPaste!,
                        palette: widget.palette,
                      ),
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
      // A resize (the keyboard opening, a rotation) must leave the cursor on
      // screen, so a viewport parked in the scrollback returns to the live
      // screen.
      final snapshot = widget.session.snapshot;
      final bottom = snapshot.scrollTotal - snapshot.scrollLen;
      if (snapshot.scrollOffset < bottom) {
        widget.session.scroll(bottom - snapshot.scrollOffset);
      }
    });
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.label,
    required this.onTap,
    required this.palette,
  });

  final String label;
  final VoidCallback onTap;
  final TerminalPalette palette;

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
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: palette.foreground,
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
    required this.palette,
    required this.origin,
  });

  final TermSnapshot snapshot;
  final _Metrics metrics;
  final TerminalPalette palette;
  final Offset origin;

  double get _cw => metrics.cellWidth;
  double get _ch => metrics.cellHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final brush = Paint()..isAntiAlias = false;
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.background);
    final gridWidth = math.min(size.width, snapshot.cols * _cw + origin.dx);
    final gridHeight = math.min(size.height, snapshot.rows * _ch + origin.dy);
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, gridWidth, gridHeight));

    _paintBackgrounds(canvas, brush);
    _paintText(canvas);
    _paintScrollbar(canvas, brush, size);
    canvas.restore();
  }

  /// Colors the emulator reports for a cell, with the theme standing in for
  /// the defaults it was created with: a theme change then shows up without
  /// rebuilding the emulator (and losing its scrollback).
  Color _cellColor(int value, int fallback) {
    if (value == snapshot.defaultFg) return palette.foreground;
    if (value == snapshot.defaultBg) return palette.background;
    if (value == fallback) return palette.foreground;
    return Color(value);
  }

  int _bgOf(int x, int y) {
    final flags = snapshot.flagsAt(x, y);
    if (flags & TermFlags.selected != 0) return palette.selection.toARGB32();
    if (flags & TermFlags.inverse != 0) {
      return flags & TermFlags.hasFg != 0
          ? snapshot.fgAt(x, y)
          : palette.foreground.toARGB32();
    }
    return flags & TermFlags.hasBg != 0 &&
            snapshot.bgAt(x, y) != snapshot.defaultBg
        ? snapshot.bgAt(x, y)
        : palette.background.toARGB32();
  }

  Color _fgOf(int x, int y) {
    final flags = snapshot.flagsAt(x, y);
    var color = flags & TermFlags.hasFg != 0
        ? _cellColor(snapshot.fgAt(x, y), snapshot.defaultFg)
        : palette.foreground;
    if (flags & TermFlags.inverse != 0) {
      color = flags & TermFlags.hasBg != 0
          ? Color(snapshot.bgAt(x, y))
          : palette.background;
    }
    if (flags & TermFlags.selected != 0) return palette.selectionText;
    if (flags & TermFlags.faint != 0) {
      return color.withValues(alpha: 0.6);
    }
    return color;
  }

  void _paintBackgrounds(Canvas canvas, Paint brush) {
    final defaultBg = palette.background.toARGB32();
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
    brush.color = palette.foreground.withValues(alpha: 0.4);
    canvas.drawRect(
      Rect.fromLTRB(size.width - 6, top, size.width - 2, bottom),
      brush,
    );
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.snapshot != snapshot ||
      old.metrics != metrics ||
      old.palette != palette ||
      old.origin != origin;
}

class _CursorPainter extends CustomPainter {
  _CursorPainter({
    required this.snapshot,
    required this.metrics,
    required this.palette,
    required this.style,
    required this.blink,
    required this.origin,
  }) : super(repaint: blink);

  final TermSnapshot snapshot;
  final _Metrics metrics;
  final TerminalPalette palette;
  final TerminalCursorId style;
  final Animation<double>? blink;
  final Offset origin;

  double get _cw => metrics.cellWidth;
  double get _ch => metrics.cellHeight;

  @override
  void paint(Canvas canvas, Size size) {
    if (!snapshot.cursorVisible) return;
    final on = blink == null || blink!.value > 0.5;
    if (!on) return;
    final x = snapshot.cursorX;
    final y = snapshot.cursorY;
    if (x < 0 || y < 0 || x >= snapshot.cols || y >= snapshot.rows) return;
    final flags = snapshot.flagsAt(x, y);
    final left = origin.dx + x * _cw;
    final top = origin.dy + y * _ch;
    final right = left + (flags & TermFlags.wide != 0 ? 2 : 1) * _cw;
    final brush = Paint()..isAntiAlias = false;
    final cursor =
        snapshot.cursorColor != 0 &&
            snapshot.cursorColor != palette.cursor.toARGB32()
        ? Color(snapshot.cursorColor | 0xFF000000)
        : palette.cursor;
    brush.color = cursor;
    final bar = math.max(2.0, _cw / 6);
    final shape = terminalCursorStyleOf(style, snapshot.cursorStyle);
    switch (shape) {
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
        if (cp <= 32) return;
        final painter = TextPainter(
          text: TextSpan(
            text: _textOf(),
            style: metrics.style.copyWith(color: palette.background),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        painter.paint(canvas, Offset(left, top));
        painter.dispose();
    }
  }

  String _textOf() =>
      snapshot.graphemeAt(snapshot.cursorX, snapshot.cursorY) ??
      String.fromCharCode(
        snapshot.codepointAt(snapshot.cursorX, snapshot.cursorY),
      );

  @override
  bool shouldRepaint(_CursorPainter old) =>
      old.snapshot != snapshot ||
      old.metrics != metrics ||
      old.palette != palette ||
      old.style != style ||
      old.blink != blink ||
      old.origin != origin;
}
