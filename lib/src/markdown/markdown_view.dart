import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../backend.dart';
import '../glyphs.dart';
import '../l10n.dart';
import '../terminal_appearance.dart';
import '../widgets/controls.dart';
import '../widgets/snackbar.dart';
import 'highlight.dart';
import 'links.dart';

/// An agent's reply as GitHub-flavoured Markdown, drawn with the app's own
/// type, colours and terminal font. Raw HTML stays literal text and only the
/// links [classifyLink] allows are tappable; code blocks and tables scroll
/// inside themselves so the page never scrolls sideways.
class MarkdownView extends StatefulWidget {
  const MarkdownView(
    this.data, {
    super.key,
    this.style,
    this.loadImage,
    this.onOpenImage,
    this.onLink,
  });

  final String data;

  /// Paragraph text; headings, lists and code scale from it.
  final TextStyle? style;

  /// Bytes for an `img:` ref, from the agent's node.
  final Future<Uint8List> Function(String ref)? loadImage;
  final ValueChanged<Uint8List>? onOpenImage;

  /// Replaces [openMarkdownLink]; tests use it to see what a tap would open.
  final ValueChanged<MarkdownLink>? onLink;

  @override
  State<MarkdownView> createState() => _MarkdownViewState();
}

final _parsed = <String, List<md.Node>>{};

List<md.Node> parseMarkdown(String data) {
  final hit = _parsed.remove(data);
  if (hit != null) return _parsed[data] = hit;
  final nodes = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  ).parse(data.replaceAll('\r\n', '\n'));
  if (_parsed.length >= 96) _parsed.remove(_parsed.keys.first);
  return _parsed[data] = nodes;
}

class _MarkdownViewState extends State<MarkdownView> {
  final _recognizers = <GestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  Future<void> _tap(MarkdownLink link) async {
    final onLink = widget.onLink;
    if (onLink != null) return onLink(link);
    if (link.kind == MarkdownLinkKind.image) {
      final load = widget.loadImage;
      final open = widget.onOpenImage;
      if (load == null || open == null) return;
      try {
        open(await load(link.target));
      } on Object {
        if (mounted) {
          showMotionSnack(
            context,
            AppLocalizations.of(context).agentImageUnavailable,
          );
        }
      }
      return;
    }
    await openMarkdownLink(context, link);
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final scheme = context.colorScheme;
    final base = (widget.style ?? AppTextStyle.body.of(context)).copyWith(
      color: widget.style?.color ?? scheme.onSurface,
    );
    final backend = context
        .getInheritedWidgetOfExactType<BackendScope>()
        ?.notifier;
    final family = terminalFontFamily(
      backend?.terminalFont ?? TerminalFontId.dejavu,
    );
    final renderer = _Renderer(
      context: context,
      base: base,
      mono: TextStyle(
        fontFamily: family,
        fontFamilyFallback: terminalFontFallback,
      ),
      recognizers: _recognizers,
      onTap: (link) => unawaited(_tap(link)),
      image: (src, alt) => _MarkdownImage(
        src: src,
        alt: alt,
        loadImage: widget.loadImage,
        onOpen: widget.onOpenImage,
      ),
    );
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: renderer.blocks(parseMarkdown(widget.data)),
      ),
    );
  }
}

final _blockTags =
    ('h1 h2 h3 h4 h5 h6 p pre ul ol blockquote table hr section div')
        .split(' ')
        .toSet();

class _Renderer {
  _Renderer({
    required this.context,
    required this.base,
    required this.mono,
    required this.recognizers,
    required this.onTap,
    required this.image,
  });

  final BuildContext context;
  final TextStyle base;
  final TextStyle mono;
  final List<GestureRecognizer> recognizers;
  final ValueChanged<MarkdownLink> onTap;
  final Widget Function(String src, String alt) image;

  ColorScheme get scheme => context.colorScheme;

  List<Widget> blocks(List<md.Node> nodes, {TextStyle? style, int depth = 0}) {
    final out = <Widget>[];
    final inline = <md.Node>[];
    void flush() {
      if (inline.any((n) => n is! md.Text || n.text.trim().isNotEmpty)) {
        out.add(_paragraph(inline, style ?? base));
      }
      inline.clear();
    }

    for (final node in nodes) {
      if (node is md.Element && _blockTags.contains(node.tag)) {
        flush();
        out.add(_block(node, style ?? base, depth));
      } else {
        inline.add(node);
      }
    }
    flush();
    return [
      for (var i = 0; i < out.length; i++)
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
          child: out[i],
        ),
    ];
  }

  Widget _block(md.Element e, TextStyle style, int depth) {
    switch (e.tag) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        final level = int.parse(e.tag.substring(1));
        final heading = style.copyWith(
          fontSize: switch (level) {
            1 => 22.0,
            2 => 20.0,
            3 => 18.0,
            4 => style.fontSize,
            _ => 15.0,
          },
          fontWeight: level <= 2 ? FontWeight.w700 : FontWeight.w600,
          height: 1.3,
          color: level >= 5 ? scheme.onSurfaceVariant : style.color,
        );
        return Semantics(
          container: true,
          header: true,
          child: Padding(
            padding: EdgeInsets.only(top: level <= 2 ? 6 : 2),
            child: _paragraph(e.children ?? const [], heading),
          ),
        );
      case 'p':
        return _paragraph(e.children ?? const [], style);
      case 'pre':
        final code = e.children?.whereType<md.Element>().firstOrNull;
        final cls = code?.attributes['class'] ?? '';
        final text = (code ?? e).textContent.replaceFirst(RegExp(r'\n$'), '');
        return _CodeBlock(
          code: text,
          lang: cls.startsWith('language-') ? cls.substring(9) : '',
          mono: mono,
        );
      case 'ul' || 'ol':
        return _list(e, style, depth);
      case 'blockquote':
        final quote = style.copyWith(color: scheme.onSurfaceVariant);
        return DecoratedBox(
          decoration: BoxDecoration(
            color: _blockFill(scheme).withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(8),
            border: BorderDirectional(
              start: BorderSide(color: scheme.outlineVariant, width: 3),
            ),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: blocks(e.children ?? const [], style: quote),
            ),
          ),
        );
      case 'table':
        return _table(e, style);
      case 'hr':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: SizedBox(
            height: 1,
            child: ColoredBox(color: scheme.outlineVariant),
          ),
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: blocks(e.children ?? const [], style: style, depth: depth),
        );
    }
  }

  Widget _paragraph(List<md.Node> nodes, TextStyle style) {
    final spans = this.spans(nodes, style);
    _trimEdges(spans);
    return Text.rich(TextSpan(children: spans), style: style);
  }

  // Block-level raw text keeps the newline it followed; it is not content.
  void _trimEdges(List<InlineSpan> spans) {
    if (spans.isEmpty) return;
    final first = spans.first;
    if (first is TextSpan && first.text != null && first.recognizer == null) {
      spans[0] = _withText(first, first.text!.trimLeft());
    }
    final last = spans.last;
    if (last is TextSpan && last.text != null && last.recognizer == null) {
      spans[spans.length - 1] = _withText(last, last.text!.trimRight());
    }
  }

  TextSpan _withText(TextSpan span, String text) =>
      TextSpan(text: text, style: span.style, children: span.children);

  List<InlineSpan> spans(
    List<md.Node> nodes,
    TextStyle style, {
    GestureRecognizer? link,
  }) {
    final out = <InlineSpan>[];
    for (final node in nodes) {
      if (node is md.Text) {
        out.add(TextSpan(text: node.text, style: style, recognizer: link));
        continue;
      }
      if (node is! md.Element) continue;
      final children = node.children ?? const <md.Node>[];
      switch (node.tag) {
        case 'strong' || 'b':
          out.addAll(
            spans(
              children,
              style.copyWith(fontWeight: FontWeight.w700),
              link: link,
            ),
          );
        case 'em' || 'i':
          out.addAll(
            spans(
              children,
              style.copyWith(fontStyle: FontStyle.italic),
              link: link,
            ),
          );
        case 'del' || 's':
          out.addAll(
            spans(
              children,
              style.copyWith(decoration: TextDecoration.lineThrough),
              link: link,
            ),
          );
        case 'code':
          out.add(
            TextSpan(
              text: node.textContent,
              recognizer: link,
              style: style
                  .merge(mono)
                  .copyWith(
                    fontSize: (style.fontSize ?? 17) * 0.86,
                    backgroundColor: SurfaceLevel.inset.colorOf(scheme),
                  ),
            ),
          );
        case 'a':
          final target = classifyLink(node.attributes['href'] ?? '');
          if (!target.tappable || link != null) {
            out.addAll(spans(children, style, link: link));
            break;
          }
          final recognizer = TapGestureRecognizer()
            ..onTap = () => onTap(target);
          recognizers.add(recognizer);
          out.addAll(
            spans(
              children,
              style.copyWith(
                color: scheme.primary,
                decoration: TextDecoration.underline,
                decorationColor: scheme.primary.withValues(alpha: 0.5),
              ),
              link: recognizer,
            ),
          );
        case 'img':
          out.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: image(
                node.attributes['src'] ?? '',
                node.attributes['alt'] ?? '',
              ),
            ),
          );
        case 'br':
          out.add(TextSpan(text: '\n', style: style));
        case 'input':
          break;
        default:
          out.addAll(spans(children, style, link: link));
      }
    }
    return out;
  }

  Widget _list(md.Element e, TextStyle style, int depth) {
    final ordered = e.tag == 'ol';
    final start = int.tryParse(e.attributes['start'] ?? '') ?? 1;
    final items = (e.children ?? const <md.Node>[])
        .whereType<md.Element>()
        .where((c) => c.tag == 'li')
        .toList();
    final markerStyle = style.copyWith(color: scheme.onSurfaceVariant);
    final line = (style.fontSize ?? 17) * (style.height ?? 1.3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 4),
            child: Semantics(
              container: _taskBox(items[i]) != null,
              checked: _taskBox(items[i])?.attributes.containsKey('checked'),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 22),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: _marker(
                        items[i],
                        ordered,
                        start + i,
                        depth,
                        markerStyle,
                        line,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: blocks(
                        items[i].children ?? const [],
                        style: style,
                        depth: depth + 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // A loose list wraps the item, checkbox included, in a paragraph.
  md.Element? _taskBox(md.Element item) {
    final children = item.children ?? const <md.Node>[];
    final first = children.whereType<md.Element>().firstOrNull;
    return [
      ...children,
      if (first?.tag == 'p') ...?first!.children,
    ].whereType<md.Element>().where((c) => c.tag == 'input').firstOrNull;
  }

  Widget _marker(
    md.Element item,
    bool ordered,
    int number,
    int depth,
    TextStyle style,
    double line,
  ) {
    final box = _taskBox(item);
    if (box != null) {
      final checked = box.attributes['checked'] == 'true';
      return Padding(
        padding: EdgeInsets.only(top: (line - 15) / 2),
        child: ExcludeSemantics(
          child: Container(
            width: 15,
            height: 15,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: checked ? scheme.primary : null,
              borderRadius: BorderRadius.circular(4),
              border: checked
                  ? null
                  : Border.all(color: scheme.outline, width: 1.4),
            ),
            child: checked
                ? GlyphIcon(Glyphs.check, size: 12, color: scheme.onPrimary)
                : null,
          ),
        ),
      );
    }
    final bullet = const ['•', '◦', '▪'][depth % 3];
    return Text(ordered ? '$number.' : bullet, style: style);
  }

  Widget _table(md.Element e, TextStyle style) {
    final rows = <(bool, md.Element)>[];
    for (final section
        in (e.children ?? const <md.Node>[]).whereType<md.Element>()) {
      for (final row
          in (section.children ?? const <md.Node>[])
              .whereType<md.Element>()
              .where((r) => r.tag == 'tr')) {
        rows.add((section.tag == 'thead', row));
      }
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    final columns = rows
        .map((r) => (r.$2.children ?? const []).length)
        .reduce((a, b) => a > b ? a : b);
    final cellStyle = style.copyWith(
      fontSize: (style.fontSize ?? 17) - 2,
      height: 1.35,
    );
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: _blockFill(scheme),
          shape: AppShape.all(AppCorner.md),
        ),
        child: ClipPath(
          clipper: ShapeBorderClipper(shape: AppShape.all(AppCorner.md)),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              defaultVerticalAlignment: TableCellVerticalAlignment.top,
              children: [
                for (final (head, row) in rows)
                  TableRow(
                    decoration: head
                        ? BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: scheme.outlineVariant),
                            ),
                          )
                        : null,
                    children: [
                      for (var c = 0; c < columns; c++)
                        _cell(row, c, head, cellStyle),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cell(md.Element row, int column, bool head, TextStyle style) {
    final cells = (row.children ?? const <md.Node>[])
        .whereType<md.Element>()
        .toList();
    final cell = column < cells.length ? cells[column] : null;
    final align = switch (cell?.attributes['align']) {
      'center' => TextAlign.center,
      'right' => TextAlign.end,
      _ => TextAlign.start,
    };
    final cellStyle = head
        ? style.copyWith(fontWeight: FontWeight.w600)
        : style;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Text.rich(
          TextSpan(children: spans(cell?.children ?? const [], cellStyle)),
          textAlign: align,
          style: cellStyle,
        ),
      ),
    );
  }
}

class _CodeBlock extends StatefulWidget {
  const _CodeBlock({
    required this.code,
    required this.lang,
    required this.mono,
  });

  final String code;
  final String lang;
  final TextStyle mono;

  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  bool _copied = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    showMotionSnack(context, AppLocalizations.of(context).agentCodeCopied);
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final l10n = AppLocalizations.of(context);
    final dark = scheme.brightness == Brightness.dark;
    final palette = CodePalette(
      keyword: scheme.primary,
      string: dark ? const Color(0xFF8FD6A4) : const Color(0xFF1E7F45),
      number: dark ? const Color(0xFFF2B37A) : const Color(0xFFA85A10),
      comment: scheme.onSurfaceVariant.withValues(alpha: 0.85),
      type: scheme.tertiary,
      added: dark ? const Color(0xFF8FD6A4) : const Color(0xFF1E7F45),
      removed: scheme.error,
    );
    final caption = AppTextStyle.caption1
        .of(context)
        .copyWith(color: scheme.onSurfaceVariant);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: _blockFill(scheme),
        shape: AppShape.all(AppCorner.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectionContainer.disabled(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.lang,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: caption,
                    ),
                  ),
                  Semantics(
                    container: true,
                    button: true,
                    label: l10n.agentCopyCode,
                    excludeSemantics: true,
                    onTap: () => unawaited(_copy()),
                    child: TapFeedback(
                      onTap: () => unawaited(_copy()),
                      shape: const CircleBorder(),
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: Center(
                          child: GlyphIcon(
                            _copied ? Glyphs.check : Glyphs.copy,
                            size: 15,
                            color: _copied
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Text.rich(
              TextSpan(
                children: highlightCode(
                  widget.code.replaceAll('\t', '    '),
                  widget.lang,
                  palette,
                ),
              ),
              softWrap: false,
              style: widget.mono.copyWith(
                fontSize: 12.5,
                height: 1.4,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `img:` refs load from the node, `data:image/*` decodes in place, public
/// http(s) loads directly; anything else shows its alt text.
class _MarkdownImage extends StatefulWidget {
  const _MarkdownImage({
    required this.src,
    required this.alt,
    required this.loadImage,
    required this.onOpen,
  });

  final String src;
  final String alt;
  final Future<Uint8List> Function(String ref)? loadImage;
  final ValueChanged<Uint8List>? onOpen;

  @override
  State<_MarkdownImage> createState() => _MarkdownImageState();
}

final _dataImage = RegExp(r'^data:image/(png|jpe?g|gif|webp);base64,(.+)$');

class _MarkdownImageState extends State<_MarkdownImage> {
  Uint8List? _bytes;
  bool _failed = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  void _resolve() {
    final src = widget.src.trim();
    final data = _dataImage.firstMatch(src);
    if (data != null) {
      try {
        _bytes = base64Decode(data.group(2)!);
      } on FormatException {
        _failed = true;
      }
      return;
    }
    final link = classifyLink(src);
    final load = widget.loadImage;
    if (link.kind == MarkdownLinkKind.image && load != null) {
      _loading = true;
      load(src).then(
        (bytes) {
          if (!mounted) return;
          setState(() {
            _bytes = bytes;
            _loading = false;
          });
        },
        onError: (Object _) {
          if (!mounted) return;
          setState(() {
            _failed = true;
            _loading = false;
          });
        },
      );
      return;
    }
    if (link.kind != MarkdownLinkKind.web) _failed = true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bytes = _bytes;
    Widget frame(Widget child) => ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280),
        child: child,
      ),
    );
    if (bytes != null) {
      final open = widget.onOpen;
      return Semantics(
        container: true,
        image: true,
        button: open != null,
        label: widget.alt.isEmpty ? l10n.agentImageOpen : widget.alt,
        child: TapFeedback(
          onTap: open == null ? null : () => open(bytes),
          child: frame(
            Image.memory(
              bytes,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (context, _, _) => _placeholder(context),
            ),
          ),
        ),
      );
    }
    if (!_failed && !_loading) {
      return Semantics(
        container: true,
        image: true,
        label: widget.alt,
        child: frame(
          Image.network(
            widget.src.trim(),
            fit: BoxFit.contain,
            errorBuilder: (context, _, _) => _placeholder(context),
          ),
        ),
      );
    }
    return _placeholder(context, busy: _loading);
  }

  Widget _placeholder(BuildContext context, {bool busy = false}) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.colorScheme;
    final tint = scheme.onSurfaceVariant;
    return Container(
      constraints: const BoxConstraints(minWidth: 132, maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: ShapeDecoration(
        color: _blockFill(scheme),
        shape: AppShape.all(AppCorner.md),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlyphIcon(Glyphs2.photo, size: 18, color: tint),
          const SizedBox(height: 4),
          Text(
            busy
                ? l10n.agentImageLoading
                : widget.alt.isNotEmpty
                ? widget.alt
                : l10n.agentImageUnavailable,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.caption2.of(context).copyWith(color: tint),
          ),
        ],
      ),
    );
  }
}

/// Code, tables and quotes sit on the page like a card does: a raised grey
/// in dark mode, white on the grey light page.
Color _blockFill(ColorScheme scheme) =>
    SurfaceLevel.floatingOf(scheme).colorOf(scheme);
