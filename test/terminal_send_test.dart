import 'package:flutter_test/flutter_test.dart';
import 'package:taildeck_ui/src/terminal_send.dart';

void main() {
  const enter = TerminalSendMode.enter;
  const insert = TerminalSendMode.insert;

  test('a single line is sent with one Enter', () {
    expect(terminalSendChunks('ls -la', enter), ['ls -la\r']);
  });

  test('a trailing newline is not doubled', () {
    expect(terminalSendChunks('ls\n', enter), ['ls\r']);
    expect(terminalSendChunks('ls\r\n', enter), ['ls\r']);
    expect(terminalSendChunks('ls\n\n', enter), ['ls\r']);
  });

  test('a three-line paste runs three lines, each with its own Enter', () {
    expect(terminalSendChunks('echo a\necho b\necho c', enter), [
      'echo a\r',
      'echo b\r',
      'echo c\r',
    ]);
    expect(terminalSendChunks('echo a\r\necho b\r\necho c\r\n', enter), [
      'echo a\r',
      'echo b\r',
      'echo c\r',
    ]);
  });

  test('a blank line in the middle still presses Enter', () {
    expect(terminalSendChunks('a\n\nb', enter), ['a\r', '\r', 'b\r']);
  });

  test('an empty line sends Enter alone', () {
    expect(terminalSendChunks('', enter), ['\r']);
    expect(terminalSendChunks('\n', enter), ['\r']);
  });

  test('insert-only appends no Enter', () {
    expect(terminalSendChunks('ls -la', insert), ['ls -la']);
    expect(terminalSendChunks('ls -la\n', insert), ['ls -la']);
    expect(terminalSendChunks('', insert), isEmpty);
  });
}
