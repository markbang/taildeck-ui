import 'dart:convert';

/// What the Logs row says at a glance: how many lines the ring holds and when
/// the newest timestamped one landed.
class LogSummary {
  const LogSummary({required this.lines, this.lastTime});

  final int lines;

  /// 'HH:MM' of the newest timestamped line, or null when none has one.
  final String? lastTime;
}

/// The bridge stamps lines `15:04:05 node: message`.
final _stamp = RegExp(r'^(\d{1,2}:\d{2})(?::\d{2})?');

LogSummary summarizeLogs(String text) {
  var lines = 0;
  String? lastTime;
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trimRight();
    if (line.isEmpty) continue;
    lines++;
    final match = _stamp.firstMatch(line);
    if (match != null) lastTime = match.group(1)!.padLeft(5, '0');
  }
  return LogSummary(lines: lines, lastTime: lastTime);
}
