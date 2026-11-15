import 'package:flutter_test/flutter_test.dart';
import 'package:taildeck_ui/src/terminal_snippets.dart';

void main() {
  TerminalSnippet snippet(String id, String command, {String name = ''}) =>
      TerminalSnippet(
        id: id,
        name: name,
        command: command,
        enter: true,
      );

  test('a tap sends the command and, when asked, Return', () {
    const withEnter = TerminalSnippet(id: 'a', name: 'Disk', command: 'df -h');
    const without = TerminalSnippet(
      id: 'b',
      name: 'Sudo',
      command: 'sudo ',
      enter: false,
    );
    expect(withEnter.payload, 'df -h\r');
    expect(without.payload, 'sudo ');
  });

  test('a nameless snippet shows its command', () {
    expect(snippet('a', 'uptime').label, 'uptime');
    expect(snippet('a', 'uptime', name: '  Up  ').label, 'Up');
  });

  test('stored JSON drops what it cannot use', () {
    final parsed = parseTerminalSnippets([
      {'id': 'one', 'name': 'Disk', 'command': 'df -h', 'enter': false},
      {'id': 'one', 'command': 'duplicate id'},
      {'id': 'two'},
      {'command': 'no id'},
      'not a map',
    ]);
    expect(parsed, hasLength(1));
    expect(parsed.single.command, 'df -h');
    expect(parsed.single.enter, isFalse);
  });

  test('upsert keeps the place and the cap holds', () {
    var list = [snippet('a', 'ls'), snippet('b', 'pwd')];
    list = upsertSnippet(list, snippet('a', 'ls -la'));
    expect(list.map((item) => item.command), ['ls -la', 'pwd']);

    final full = [
      for (var i = 0; i < maxTerminalSnippets; i++) snippet('s$i', 'cmd $i'),
    ];
    expect(upsertSnippet(full, snippet('new', 'x')), hasLength(maxTerminalSnippets));
    expect(upsertSnippet(list, snippet('blank', '   ')), hasLength(2));
  });

  test('reorder moves one place and stops at the edges', () {
    final list = [snippet('a', 'ls'), snippet('b', 'pwd'), snippet('c', 'id')];
    expect(moveSnippet(list, 'a', 1).map((s) => s.id), ['b', 'a', 'c']);
    expect(moveSnippet(list, 'c', 1).map((s) => s.id), ['a', 'b', 'c']);
    expect(moveSnippet(list, 'a', -1).map((s) => s.id), ['a', 'b', 'c']);
  });

  test('remove drops one entry and nothing else', () {
    final list = [snippet('a', 'ls'), snippet('b', 'pwd')];
    expect(removeSnippet(list, 'a').map((s) => s.id), ['b']);
    expect(removeSnippet(list, 'missing'), hasLength(2));
  });
}
