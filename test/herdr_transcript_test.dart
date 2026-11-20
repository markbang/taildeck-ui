import 'package:flutter_test/flutter_test.dart';
import 'package:taildeck_ui/src/herdr.dart';

HerdrTranscript _read({String file = 'a.jsonl', String turn = 't1'}) =>
    HerdrTranscript(
      messages: const [HerdrMessage(role: 'assistant', id: 'a1', text: 'hi')],
      model: 'claude-opus-4-1-20250805',
      file: file,
      turn: turn,
    );

void main() {
  test('a read from another session file is a different read', () {
    final first = _read();
    final other = _read(file: 'b.jsonl');
    expect(first == other, isFalse);
    expect(first.hashCode == other.hashCode, isFalse);
  });

  test('a read at another turn is a different read', () {
    final first = _read();
    final later = _read(turn: 't2');
    expect(first == later, isFalse);
    expect(first.hashCode == later.hashCode, isFalse);
  });

  test('equal reads stay equal, the poll may skip them', () {
    expect(_read() == _read(), isTrue);
    expect(_read().hashCode, _read().hashCode);
  });
}
