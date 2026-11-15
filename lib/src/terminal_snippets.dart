/// Named commands the user saves and sends with one tap.
///
/// A snippet is local to the device: a name for the drawer, the command line,
/// and whether a Return follows it (a `cd` usually wants one, a `sudo` prefix
/// does not). Nothing is sent by itself; a tap in the terminal writes the text
/// to the live session.
library;

/// A drawer holds a few screens' worth; more stops being one glance.
const maxTerminalSnippets = 40;
const maxSnippetName = 40;
const maxSnippetCommand = 2000;

class TerminalSnippet {
  const TerminalSnippet({
    required this.id,
    required this.name,
    required this.command,
    this.enter = true,
  });

  factory TerminalSnippet.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('snippet');
    final id = value['id'];
    final command = value['command'];
    if (id is! String || id.isEmpty || command is! String) {
      throw const FormatException('snippet');
    }
    return TerminalSnippet(
      id: id,
      name: _trimName(value['name'] is String ? value['name'] as String : ''),
      command: _trimCommand(command),
      enter: value['enter'] is bool ? value['enter'] as bool : true,
    );
  }

  final String id;

  /// What the drawer shows; an empty name falls back to the command.
  final String name;
  final String command;

  /// Whether Return is part of the send.
  final bool enter;

  String get label => name.trim().isEmpty ? command : name.trim();

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'command': command,
    'enter': enter,
  };

  TerminalSnippet copyWith({String? name, String? command, bool? enter}) =>
      TerminalSnippet(
        id: id,
        name: _trimName(name ?? this.name),
        command: _trimCommand(command ?? this.command),
        enter: enter ?? this.enter,
      );

  /// Bytes a tap sends: the command, then Return when asked for.
  String get payload => enter ? '$command\r' : command;
}

String _trimName(String value) {
  final trimmed = value.trim();
  return trimmed.length > maxSnippetName
      ? trimmed.substring(0, maxSnippetName)
      : trimmed;
}

String _trimCommand(String value) {
  final normalized = value.replaceAll('\r\n', '\n');
  return normalized.length > maxSnippetCommand
      ? normalized.substring(0, maxSnippetCommand)
      : normalized;
}

/// Stored JSON: anything malformed is dropped, never half-kept.
List<TerminalSnippet> parseTerminalSnippets(Object? value) {
  if (value is! List) return const [];
  final seen = <String>{};
  final out = <TerminalSnippet>[];
  for (final entry in value) {
    if (out.length >= maxTerminalSnippets) break;
    try {
      final snippet = TerminalSnippet.fromJson(entry);
      if (snippet.command.isEmpty || !seen.add(snippet.id)) continue;
      out.add(snippet);
    } on FormatException {
      continue;
    }
  }
  return out;
}

/// A fresh id; ids only have to be unique inside one drawer.
String newSnippetId([DateTime? now]) =>
    'snip-${(now ?? DateTime.now()).microsecondsSinceEpoch.toRadixString(36)}';

/// Inserts or replaces [snippet], keeping its place in the drawer.
List<TerminalSnippet> upsertSnippet(
  List<TerminalSnippet> snippets,
  TerminalSnippet snippet,
) {
  if (snippet.command.trim().isEmpty) return snippets;
  final index = snippets.indexWhere((item) => item.id == snippet.id);
  if (index >= 0) {
    final next = [...snippets]..[index] = snippet;
    return next;
  }
  if (snippets.length >= maxTerminalSnippets) return snippets;
  return [...snippets, snippet];
}

List<TerminalSnippet> removeSnippet(
  List<TerminalSnippet> snippets,
  String id,
) => [
  for (final snippet in snippets)
    if (snippet.id != id) snippet,
];

/// Moves a snippet one place up or down; edges stay put.
List<TerminalSnippet> moveSnippet(
  List<TerminalSnippet> snippets,
  String id,
  int delta,
) {
  final index = snippets.indexWhere((item) => item.id == id);
  if (index < 0) return snippets;
  final target = index + delta;
  if (target < 0 || target >= snippets.length) return snippets;
  final next = [...snippets];
  final moved = next.removeAt(index);
  next.insert(target, moved);
  return next;
}
