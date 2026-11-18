import 'package:flutter/widgets.dart';

/// Colours a code block paints its tokens with.
@immutable
class CodePalette {
  const CodePalette({
    required this.keyword,
    required this.string,
    required this.number,
    required this.comment,
    required this.type,
    required this.added,
    required this.removed,
  });

  final Color keyword;
  final Color string;
  final Color number;
  final Color comment;
  final Color type;
  final Color added;
  final Color removed;
}

enum _Family { cLike, hash, sql, json, diff, none }

final _cLikeKeywords =
    ('abstract as async await bool boolean break case catch chan char class '
            'companion const continue data default defer define do double else enum '
            'export extends false final finally float fn for from fun func function '
            'go if impl implements import in include instanceof int interface is '
            'late let long map match mod mut namespace new nil null object of '
            'override package private protected pub public range required return '
            'sealed select self static string struct super suspend switch template '
            'this throw trait true try type typename typeof undefined unsigned use '
            'val var void when where while with yield')
        .split(' ')
        .toSet();

final _hashKeywords =
    ('False None True and as assert async await begin break case cd class '
            'continue def del do done echo elif else end esac except exit export '
            'false fi finally for from function global if import in is lambda local '
            'module nonlocal not null or pass raise require rescue return self set '
            'source sudo then true try unless unset until while with yield')
        .split(' ')
        .toSet();

final _sqlKeywords =
    ('all alter and as by case create delete distinct do drop else end false '
            'for foreign from function group having if in index inner insert into '
            'is join key left like limit local nil not null offset on or order '
            'outer primary references return right select set table then true union '
            'update values when where while')
        .split(' ')
        .toSet();

_Family _familyOf(String lang) => switch (lang.toLowerCase()) {
  'dart' ||
  'kotlin' ||
  'kt' ||
  'kts' ||
  'java' ||
  'js' ||
  'javascript' ||
  'jsx' ||
  'ts' ||
  'typescript' ||
  'tsx' ||
  'go' ||
  'golang' ||
  'rust' ||
  'rs' ||
  'c' ||
  'h' ||
  'cpp' ||
  'c++' ||
  'cc' ||
  'hpp' ||
  'cs' ||
  'csharp' ||
  'swift' ||
  'scala' ||
  'groovy' ||
  'gradle' ||
  'css' ||
  'scss' ||
  'zig' ||
  'proto' ||
  'objc' => _Family.cLike,
  'sh' ||
  'bash' ||
  'zsh' ||
  'shell' ||
  'console' ||
  'fish' ||
  'python' ||
  'py' ||
  'ruby' ||
  'rb' ||
  'perl' ||
  'yaml' ||
  'yml' ||
  'toml' ||
  'ini' ||
  'dockerfile' ||
  'docker' ||
  'make' ||
  'makefile' ||
  'nix' ||
  'r' ||
  'conf' ||
  'nginx' ||
  'ps1' ||
  'powershell' => _Family.hash,
  'sql' || 'lua' || 'haskell' || 'hs' => _Family.sql,
  'json' || 'jsonc' || 'json5' => _Family.json,
  'diff' || 'patch' => _Family.diff,
  _ => _Family.none,
};

// Groups: 1 comment, 2 string, 3 number (or a shell variable), 4 word.
final _cLikeToken = RegExp(
  r'(//[^\n]*|/\*[\s\S]*?(?:\*/|$))'
  r'''|("(?:[^"\\\n]|\\.)*"?|'(?:[^'\\\n]|\\.)*'?|`(?:[^`\\]|\\.)*`?)'''
  r'|(\b0[xX][0-9a-fA-F_]+\b|\b\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?[fFLuU]?\b)'
  r'|(@?[A-Za-z_$][\w$]*)',
);

final _hashToken = RegExp(
  r'((?:^|(?<=\s))#[^\n]*)'
  r'''|("(?:[^"\\]|\\.)*"?|'[^'\n]*'?|`[^`]*`?)'''
  r'|(\b\d+(?:\.\d+)?\b|\$\{[^}\n]*\}|\$[\w@#?*!$-]+)'
  r'|([A-Za-z_][\w-]*:(?=\s|$)|[A-Za-z_]\w*)',
  multiLine: true,
);

final _sqlToken = RegExp(
  r'(--[^\n]*|/\*[\s\S]*?(?:\*/|$))'
  r'''|("(?:[^"\\\n]|\\.)*"?|'(?:[^'\n]|'')*'?)'''
  r'|(\b\d+(?:\.\d+)?\b)'
  r'|([A-Za-z_]\w*)',
);

// Groups: 1 key, 2 string, 3 number, 4 literal.
final _jsonToken = RegExp(
  r'("(?:[^"\\\n]|\\.)*"(?=\s*:))'
  r'|("(?:[^"\\\n]|\\.)*"?)'
  r'|(-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b)'
  r'|(\btrue\b|\bfalse\b|\bnull\b)',
);

/// Spans for [code] in [lang]; an unknown language comes back as one span.
/// A tokenizer, not a grammar: comments, strings, numbers, keywords and type
/// names are what make a snippet readable in a chat.
List<TextSpan> highlightCode(String code, String lang, CodePalette palette) {
  final family = _familyOf(lang);
  if (family == _Family.none) return [TextSpan(text: code)];
  if (family == _Family.diff) return _diff(code, palette);
  final pattern = switch (family) {
    _Family.cLike => _cLikeToken,
    _Family.hash => _hashToken,
    _Family.sql => _sqlToken,
    _ => _jsonToken,
  };
  final spans = <TextSpan>[];
  var at = 0;
  for (final match in pattern.allMatches(code)) {
    if (match.start > at) {
      spans.add(TextSpan(text: code.substring(at, match.start)));
    }
    final text = match[0]!;
    final color = family == _Family.json
        ? _jsonColor(match, palette)
        : _tokenColor(family, match, text, palette);
    final comment = match[1] != null && family != _Family.json;
    spans.add(
      TextSpan(
        text: text,
        style: color == null
            ? null
            : TextStyle(
                color: color,
                fontStyle: comment ? FontStyle.italic : null,
              ),
      ),
    );
    at = match.end;
  }
  if (at < code.length) spans.add(TextSpan(text: code.substring(at)));
  return spans;
}

Color _jsonColor(RegExpMatch match, CodePalette palette) {
  if (match[1] != null) return palette.type;
  if (match[2] != null) return palette.string;
  if (match[3] != null) return palette.number;
  return palette.keyword;
}

Color? _tokenColor(
  _Family family,
  RegExpMatch match,
  String text,
  CodePalette palette,
) {
  if (match[1] != null) return palette.comment;
  if (match[2] != null) return palette.string;
  if (match[3] != null) {
    return text.startsWith(r'$') ? palette.type : palette.number;
  }
  final keywords = switch (family) {
    _Family.cLike => _cLikeKeywords,
    _Family.hash => _hashKeywords,
    _ => _sqlKeywords,
  };
  if (keywords.contains(family == _Family.sql ? text.toLowerCase() : text)) {
    return palette.keyword;
  }
  if (family == _Family.hash && text.endsWith(':')) return palette.type;
  if (family == _Family.cLike) {
    if (text.startsWith('@')) return palette.keyword;
    final first = text.codeUnitAt(0);
    if (first >= 0x41 && first <= 0x5A) return palette.type;
  }
  return null;
}

List<TextSpan> _diff(String code, CodePalette palette) {
  final lines = code.split('\n');
  return [
    for (var i = 0; i < lines.length; i++)
      TextSpan(
        text: i == lines.length - 1 ? lines[i] : '${lines[i]}\n',
        style: _diffStyle(lines[i], palette),
      ),
  ];
}

TextStyle? _diffStyle(String line, CodePalette palette) {
  if (line.startsWith('+++') ||
      line.startsWith('---') ||
      line.startsWith('@@')) {
    return TextStyle(color: palette.keyword);
  }
  if (line.startsWith('+')) return TextStyle(color: palette.added);
  if (line.startsWith('-')) return TextStyle(color: palette.removed);
  return null;
}
