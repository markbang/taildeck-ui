/// What one Send writes: the line the input holds, then the line break the
/// remote needs. The input line buffers keystrokes and sends them as a line,
/// so the byte stream is decided here and not keystroke by keystroke.
library;

/// Whether Send presses Enter after the text.
enum TerminalSendMode {
  /// Text, then Enter: the shell runs it.
  enter,

  /// Text only, so the remote keeps its command line open for editing.
  insert,
}

/// The chunks of one Send, one per line, in order.
///
/// Inner newlines split the text, so a three-line paste runs three commands.
/// The final run of newlines is dropped: the CR that [TerminalSendMode.enter]
/// appends already ends that line, and a second one would only run an empty
/// command. An empty line still sends its Enter, which is how a bare Send
/// presses Enter with nothing typed.
///
/// [TerminalSendMode.insert] keeps the text as typed (newlines included) and
/// appends nothing; an empty line sends nothing at all.
List<String> terminalSendChunks(String text, TerminalSendMode mode) {
  final plain = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  var end = plain.length;
  while (end > 0 && plain[end - 1] == '\n') {
    end--;
  }
  final body = plain.substring(0, end);
  if (mode == TerminalSendMode.insert) {
    return body.isEmpty ? const [] : [body];
  }
  if (body.isEmpty) return const ['\r'];
  return [for (final line in body.split('\n')) '$line\r'];
}
