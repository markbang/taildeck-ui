import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import '../herdr.dart';
import '../motion.dart';

/// How much of each agent message the reader has already seen, for as long as
/// the chat page lives. A message that moves (out of a steps fold once its
/// turn ends) or is rebuilt picks its reveal up where it stopped.
class RevealMemory {
  final _shown = <String, int>{};
  final _arrived = <String, DateTime>{};

  /// A reply is typed out only this long after it arrived; one first built
  /// later (a fold opened afterwards) shows whole.
  static const window = Duration(seconds: 4);

  /// Characters of [key] to start from, or null to show it whole.
  int? start(String key, int length) {
    final shown = _shown[key];
    if (shown == null || shown >= length) return null;
    final arrived = _arrived[key];
    if (arrived == null || DateTime.now().difference(arrived) > window) {
      return null;
    }
    return shown;
  }

  void record(String key, int length) => _shown[key] = length;

  bool knows(String key) => _shown.containsKey(key);

  /// A reply that just landed: typed out from its first character.
  void arrive(String key) {
    _shown[key] = 0;
    _arrived[key] = DateTime.now();
  }

  /// Marks messages as read in full.
  void settle(Iterable<HerdrMessage> messages) {
    for (final message in messages) {
      if (message.key.isNotEmpty) _shown[message.key] = message.text.length;
    }
  }
}

/// Session files hold whole messages, so a reply lands in one piece. This
/// types out the part the reader has not seen yet, at a steady pace that
/// catches up within [catchUp], so a reply grows on screen instead of
/// appearing in one jump.
class RevealText extends StatefulWidget {
  const RevealText({
    super.key,
    required this.id,
    required this.text,
    required this.memory,
    required this.builder,
    this.onGrow,
  });

  /// [HerdrMessage.key]; an empty id shows the text at once.
  final String id;
  final String text;
  final RevealMemory memory;
  final Widget Function(BuildContext context, String visible) builder;

  /// Called after each step that made the text longer on screen.
  final VoidCallback? onGrow;

  static const minRate = 320.0;
  static const catchUp = Duration(milliseconds: 1100);

  @override
  State<RevealText> createState() => _RevealTextState();
}

class _RevealTextState extends State<RevealText>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  double _shown = 0;
  int _cut = 0;
  double _rate = RevealText.minRate;
  Duration _last = Duration.zero;

  int get _length => widget.text.length;

  @override
  void initState() {
    super.initState();
    final start = widget.id.isEmpty
        ? null
        : widget.memory.start(widget.id, _length);
    _shown = (start ?? _length).toDouble();
    _cut = _boundary(_shown.floor());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resume();
  }

  @override
  void didUpdateWidget(covariant RevealText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text == widget.text) return;
    final old = oldWidget.text;
    if (widget.id.isEmpty) {
      _shown = _length.toDouble();
    } else if (!widget.text.startsWith(
      old.substring(0, _cut.clamp(0, old.length)),
    )) {
      // Rewritten rather than extended: keep what still matches.
      var same = 0;
      final limit = [_cut, _length, old.length].reduce((a, b) => a < b ? a : b);
      while (same < limit &&
          widget.text.codeUnitAt(same) == old.codeUnitAt(same)) {
        same++;
      }
      _shown = same.toDouble();
    }
    if (_shown > _length) _shown = _length.toDouble();
    _cut = _boundary(_shown.floor());
    _resume();
  }

  void _resume() {
    if (_shown >= _length || context.disableAnimations) {
      _shown = _length.toDouble();
      _finish();
      return;
    }
    final seconds =
        RevealText.catchUp.inMicroseconds / Duration.microsecondsPerSecond;
    final steady = (_length - _shown) / seconds;
    _rate = steady > RevealText.minRate ? steady : RevealText.minRate;
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _finish() {
    _cut = _length;
    if (widget.id.isNotEmpty) widget.memory.record(widget.id, _length);
    if (_ticker.isActive) _ticker.stop();
  }

  void _tick(Duration elapsed) {
    final dt =
        (elapsed - _last).inMicroseconds / Duration.microsecondsPerSecond;
    _last = elapsed;
    _shown += _rate * dt;
    if (_shown >= _length) _shown = _length.toDouble();
    widget.memory.record(widget.id, _shown.floor());
    final cut = _boundary(_shown.floor());
    if (_shown >= _length) _ticker.stop();
    if (cut == _cut) return;
    setState(() => _cut = cut);
    widget.onGrow?.call();
  }

  /// Ends a step between words for Latin text, so a half word never flashes,
  /// and never inside a surrogate pair. CJK text has no spaces and steps by
  /// character.
  int _boundary(int at) {
    final text = widget.text;
    if (at >= text.length) return text.length;
    if (at <= 0) return 0;
    var cut = at;
    for (var back = 0; back < 12 && cut > 0; back++) {
      if (!_isWordUnit(text.codeUnitAt(cut - 1)) ||
          !_isWordUnit(text.codeUnitAt(cut))) {
        break;
      }
      cut--;
    }
    if (cut == 0) cut = at;
    final unit = text.codeUnitAt(cut - 1);
    if (unit >= 0xD800 && unit <= 0xDBFF) cut--;
    return cut;
  }

  static bool _isWordUnit(int unit) =>
      (unit >= 0x30 && unit <= 0x39) ||
      (unit >= 0x41 && unit <= 0x5A) ||
      (unit >= 0x61 && unit <= 0x7A);

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(
    context,
    _cut >= _length
        ? widget.text
        : settledMarkdown(widget.text.substring(0, _cut)),
  );
}

/// [text] cut back to before the first inline span its last line leaves open
/// (a code span, bold, italic or link), so a half-typed reply never flashes
/// raw `**` or `[`. Inside an open code fence everything is literal.
String settledMarkdown(String text) {
  final fences = RegExp(r'^\s*```', multiLine: true).allMatches(text).length;
  if (fences.isOdd) return text;
  final start = text.lastIndexOf('\n') + 1;
  int? open;
  var code = false;
  int? codeAt;
  int? boldAt;
  int? italicAt;
  int? linkAt;
  var url = false;
  for (var i = start; i < text.length; i++) {
    final c = text[i];
    if (code) {
      if (c == '`') {
        code = false;
        codeAt = null;
      }
      continue;
    }
    if (url) {
      if (c == ')') {
        url = false;
        linkAt = null;
      }
      continue;
    }
    switch (c) {
      case '`':
        code = true;
        codeAt = i;
      case '*':
        if (i + 1 < text.length && text[i + 1] == '*') {
          boldAt = boldAt == null ? i : null;
          i++;
        } else if (i + 1 < text.length && text[i + 1] != ' ' ||
            italicAt != null) {
          italicAt = italicAt == null ? i : null;
        } else if (i + 1 == text.length) {
          italicAt = i;
        }
      case '[':
        linkAt ??= i;
      case ']':
        if (linkAt != null) {
          if (i + 1 < text.length && text[i + 1] == '(') {
            url = true;
            i++;
          } else if (i + 1 < text.length) {
            linkAt = null;
          }
        }
    }
  }
  for (final at in [codeAt, boldAt, italicAt, linkAt]) {
    if (at != null && (open == null || at < open)) open = at;
  }
  if (open == null) return text;
  return text.substring(0, open).trimRight();
}

/// The end of a transcript while the agent works: one pulsing dot where its
/// next words will appear.
class LiveCaret extends StatelessWidget {
  const LiveCaret({super.key});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 10, 0, 10),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: PulsingDot(
            color: context.colorScheme.primary,
            size: 9,
            pulse: true,
          ),
        ),
      ),
    );
  }
}
