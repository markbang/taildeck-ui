import 'dart:convert';

import 'package:flutter/material.dart' hide SelectionArea;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taildeck_ui/src/l10n.dart';
import 'package:taildeck_ui/src/markdown/highlight.dart';
import 'package:taildeck_ui/src/markdown/links.dart';
import 'package:taildeck_ui/src/markdown/markdown_view.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

Widget _app(Widget child, {double width = 360}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [AppLocalizations.delegate],
  supportedLocales: const [Locale('en'), Locale('zh')],
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        child: SingleChildScrollView(child: child),
      ),
    ),
  ),
);

/// Every span under [finder], flattened, with the style it inherits.
List<(String, TextStyle)> _spans(WidgetTester tester, [Finder? finder]) {
  final out = <(String, TextStyle)>[];
  void walk(InlineSpan span, TextStyle inherited) {
    if (span is! TextSpan) return;
    final style = inherited.merge(span.style);
    if (span.text != null) out.add((span.text!, style));
    for (final child in span.children ?? const <InlineSpan>[]) {
      walk(child, style);
    }
  }

  for (final rich in tester.widgetList<RichText>(
    finder ?? find.byType(RichText),
  )) {
    walk(rich.text, const TextStyle());
  }
  return out;
}

TextStyle _styleOf(WidgetTester tester, String text) =>
    _spans(tester).firstWhere((s) => s.$1 == text).$2;

TextSpan? _spanOf(WidgetTester tester, String text) {
  TextSpan? hit;
  void walk(InlineSpan span) {
    if (span is! TextSpan) return;
    if (span.text == text) hit = span;
    span.children?.forEach(walk);
  }

  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    walk(rich.text);
  }
  return hit;
}

void main() {
  testWidgets('headings are headers and step down in size', (tester) async {
    await tester.pumpWidget(
      _app(const MarkdownView('# One\n\n## Two\n\n### Three\n\nbody')),
    );
    final one = _styleOf(tester, 'One');
    final two = _styleOf(tester, 'Two');
    final three = _styleOf(tester, 'Three');
    final body = _styleOf(tester, 'body');
    expect(one.fontSize, greaterThan(two.fontSize!));
    expect(two.fontSize, greaterThan(three.fontSize!));
    expect(three.fontSize, greaterThan(body.fontSize!));
    expect(one.fontWeight, FontWeight.w700);
    expect(
      tester.getSemantics(find.text('One')),
      matchesSemantics(isHeader: true, label: 'One'),
    );
  });

  testWidgets('bold, italic, strikethrough and inline code', (tester) async {
    await tester.pumpWidget(
      _app(const MarkdownView('a **bold** and *it* and ~~gone~~ and `code`')),
    );
    expect(find.textContaining('**'), findsNothing);
    expect(_styleOf(tester, 'bold').fontWeight, FontWeight.w700);
    expect(_styleOf(tester, 'it').fontStyle, FontStyle.italic);
    expect(_styleOf(tester, 'gone').decoration, TextDecoration.lineThrough);
    final code = _styleOf(tester, 'code');
    expect(code.fontFamily, 'DejaVuSansMono');
    expect(code.backgroundColor, isNotNull);
  });

  testWidgets('a fenced block highlights, scrolls inside and copies', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    const code =
        'func main() {\n\treturn "a very long string that does not fit on a phone line at all"\n}';
    await tester.pumpWidget(
      _app(const MarkdownView('```go\n$code\n```'), width: 300),
    );
    expect(find.text('go'), findsOneWidget);
    expect(
      _styleOf(tester, 'func').color,
      isNot(_styleOf(tester, 'main').color),
    );
    expect(_styleOf(tester, 'return').fontFamily, 'DejaVuSansMono');
    final scroll = find.ancestor(
      of: find.textContaining('very long', findRichText: true),
      matching: find.byType(SingleChildScrollView),
    );
    expect(
      tester.widget<SingleChildScrollView>(scroll.first).scrollDirection,
      Axis.horizontal,
    );
    expect(tester.takeException(), isNull);
    // Its own node, not merged into the reply, so TalkBack and uiautomator
    // can reach it.
    expect(
      tester.getSemantics(find.bySemanticsLabel('Copy code')),
      isSemantics(isButton: true, hasTapAction: true, label: 'Copy code'),
    );
    await tester.tap(find.bySemanticsLabel('Copy code'));
    await tester.pump();
    expect(copied, code);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('ordered, unordered, nested and task lists', (tester) async {
    await tester.pumpWidget(
      _app(
        const MarkdownView(
          '3. three\n4. four\n\n- top\n  - inner\n\n- [x] done\n- [ ] todo',
        ),
      ),
    );
    expect(find.text('3.'), findsOneWidget);
    expect(find.text('4.'), findsOneWidget);
    expect(find.text('•'), findsOneWidget);
    expect(find.text('◦'), findsOneWidget);
    expect(find.text('[x]'), findsNothing);
    final boxes = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.checked != null,
    );
    expect(boxes, findsNWidgets(2));
    final checked = tester
        .widgetList<Semantics>(boxes)
        .map((s) => s.properties.checked)
        .toList();
    expect(checked, [true, false]);
  });

  testWidgets('a blockquote keeps its inline marks', (tester) async {
    await tester.pumpWidget(_app(const MarkdownView('> quoted **text**')));
    expect(find.textContaining('>'), findsNothing);
    expect(_styleOf(tester, 'text').fontWeight, FontWeight.w700);
    expect(find.byType(DecoratedBox), findsWidgets);
  });

  testWidgets('a wide table scrolls inside its block only', (tester) async {
    final row = List.filled(8, 'a-rather-wide-cell').join(' | ');
    await tester.pumpWidget(
      _app(
        MarkdownView(
          '| ${List.filled(8, 'head').join(' | ')} |\n|${List.filled(8, '---').join('|')}|\n| $row |',
        ),
        width: 320,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(Table), findsOneWidget);
    final scroll = find
        .ancestor(
          of: find.byType(Table),
          matching: find.byType(SingleChildScrollView),
        )
        .first;
    expect(
      tester.widget<SingleChildScrollView>(scroll).scrollDirection,
      Axis.horizontal,
    );
    expect(tester.getSize(scroll).width, lessThanOrEqualTo(320));
    expect(tester.getSize(find.byType(Table)).width, greaterThan(320));
    expect(_styleOf(tester, 'head').fontWeight, FontWeight.w600);
  });

  testWidgets('an img: ref loads from the node and opens on tap', (
    tester,
  ) async {
    final asked = <String>[];
    Uint8List? opened;
    await tester.pumpWidget(
      _app(
        MarkdownView(
          'see ![shot](img:42)',
          loadImage: (ref) async {
            asked.add(ref);
            return _png;
          },
          onOpenImage: (bytes) => opened = bytes,
        ),
      ),
    );
    await tester.pump();
    expect(asked, ['img:42']);
    expect(find.byType(Image), findsOneWidget);
    await tester.runAsync(
      () =>
          precacheImage(MemoryImage(_png), tester.element(find.byType(Image))),
    );
    await tester.pump();
    await tester.tap(find.byType(Image));
    expect(opened, _png);
  });

  testWidgets('an image the app cannot read shows its alt text', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const MarkdownView('![diagram](/tmp/a.png)')));
    expect(find.text('diagram'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('links open the right place; unsafe ones are inert', (
    tester,
  ) async {
    final taps = <MarkdownLink>[];
    await tester.pumpWidget(
      _app(
        MarkdownView(
          '[docs](https://tailscale.com/kb) [grafana](http://devbox.tail4a2c.ts.net:3000/d) '
          '[mail](mailto:a@b.c) [file](lib/src/app.dart) [bad](javascript:alert(1)) '
          'https://example.com/x',
          onLink: taps.add,
        ),
      ),
    );
    for (final label in [
      'docs',
      'grafana',
      'mail',
      'file',
      'bad',
      'https://example.com/x',
    ]) {
      await tester.tapOnText(find.textRange.ofSubstring(label));
    }
    expect(taps.map((l) => l.kind), [
      MarkdownLinkKind.web,
      MarkdownLinkKind.tailnet,
      MarkdownLinkKind.mail,
      MarkdownLinkKind.path,
      MarkdownLinkKind.web,
    ]);
    expect(_spanOf(tester, 'bad')!.recognizer, isNull);
    expect(_styleOf(tester, 'bad').decoration, isNot(TextDecoration.underline));
  });

  test('only http(s), mailto, img: and paths are acted on', () {
    for (final href in [
      'javascript:alert(1)',
      'JavaScript:alert(1)',
      ' javascript:alert(1)',
      'java\tscript:alert(1)',
      'java\nscript:alert(1)',
      'data:text/html,<script>alert(1)</script>',
      'vbscript:msgbox',
      'intent://scan/#Intent;scheme=zxing;end',
      'tel:123',
      'ftp://x.y/z',
      'http://',
      '#top',
      '',
    ]) {
      expect(classifyLink(href).kind, MarkdownLinkKind.blocked, reason: href);
    }
    expect(classifyLink('HTTPS://Example.com').kind, MarkdownLinkKind.web);
    expect(
      classifyLink('http://100.101.4.2:8080').kind,
      MarkdownLinkKind.tailnet,
    );
    expect(classifyLink('http://100.128.0.1').kind, MarkdownLinkKind.web);
    expect(
      classifyLink('http://[fd7a:115c:a1e0::1]:80').kind,
      MarkdownLinkKind.tailnet,
    );
    expect(classifyLink('http://nas:5000').kind, MarkdownLinkKind.tailnet);
    expect(classifyLink('http://localhost:3000').kind, MarkdownLinkKind.web);
    expect(classifyLink('file:///etc/hosts').target, '/etc/hosts');
    expect(classifyLink('C:\\x\\y.txt').kind, MarkdownLinkKind.path);
    expect(classifyLink('img:7').kind, MarkdownLinkKind.image);
  });

  testWidgets('raw HTML is shown as text, never rendered', (tester) async {
    await tester.pumpWidget(
      _app(
        const MarkdownView(
          'a <b>x</b> <script>alert(1)</script>\n\n<div onclick="x">block</div>',
        ),
      ),
    );
    final text = _spans(tester).map((s) => s.$1).join();
    expect(text, contains('<b>x</b>'));
    expect(text, contains('<script>alert(1)</script>'));
    expect(text, contains('<div onclick="x">block</div>'));
    expect(
      _styleOf(tester, 'a <b>x</b> <script>alert(1)</script>').fontWeight,
      isNot(FontWeight.w700),
    );
  });

  testWidgets('long paths and URLs wrap inside the page width', (tester) async {
    const path =
        '/home/bang/.local/state/herdr/sessions/default/panes/w3-p4/claude-2026-11-18T09-14-03.jsonl';
    const url =
        'https://github.com/markbang/taildeck-ui/blob/main/native/bridge/transcript_resolution_for_claude_sessions.go#L120';
    await tester.pumpWidget(
      _app(MarkdownView('Log `$path` and $url and [$path]($path)'), width: 280),
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(MarkdownView)).width,
      lessThanOrEqualTo(280),
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText).first,
    );
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(paragraph.size.width, lessThanOrEqualTo(280));
    expect(paragraph.size.height, greaterThan(100));
  });

  test('the highlighter colours keywords, strings, comments and numbers', () {
    const palette = CodePalette(
      keyword: Color(0xFF000001),
      string: Color(0xFF000002),
      number: Color(0xFF000003),
      comment: Color(0xFF000004),
      type: Color(0xFF000005),
      added: Color(0xFF000006),
      removed: Color(0xFF000007),
    );
    Color? colorOf(List<TextSpan> spans, String text) =>
        spans.firstWhere((s) => s.text == text).style?.color;
    final dart = highlightCode(
      'final x = "s" + 42; // note\nString y;',
      'dart',
      palette,
    );
    expect(colorOf(dart, 'final'), palette.keyword);
    expect(colorOf(dart, '"s"'), palette.string);
    expect(colorOf(dart, '42'), palette.number);
    expect(colorOf(dart, '// note'), palette.comment);
    expect(colorOf(dart, 'String'), palette.type);
    final sh = highlightCode('echo "\$HOME" # go\nexport A=1', 'bash', palette);
    expect(colorOf(sh, 'echo'), palette.keyword);
    expect(colorOf(sh, '# go'), palette.comment);
    final diff = highlightCode('+a\n-b', 'diff', palette);
    expect(diff.first.style?.color, palette.added);
    expect(diff.last.style?.color, palette.removed);
    expect(highlightCode('plain', 'unknown', palette).single.style, isNull);
  });
}
