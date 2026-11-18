import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../backend.dart';
import '../l10n.dart';
import '../service_open.dart';
import '../services.dart';
import '../widgets/snackbar.dart';

enum MarkdownLinkKind {
  /// http(s) on the public internet: the system browser.
  web,

  /// http(s) on a tailnet address: only the in-app node can reach it.
  tailnet,
  mail,

  /// `img:<id>`, a transcript image the agent's node serves.
  image,

  /// A file path on the agent's node; there is no file viewer, so it copies.
  path,

  /// Anything else (javascript:, data:, intent:, ...) stays plain text.
  blocked,
}

@immutable
class MarkdownLink {
  const MarkdownLink(this.kind, this.target);

  final MarkdownLinkKind kind;
  final String target;

  bool get tappable => kind != MarkdownLinkKind.blocked;
}

final _scheme = RegExp(r'^([A-Za-z][A-Za-z0-9+.\-]*):');

/// What tapping [href] does. Only http(s), mailto, `img:` refs and paths are
/// ever acted on; everything else is inert.
MarkdownLink classifyLink(String href) {
  // Browsers drop ASCII whitespace and controls inside a scheme, so a
  // `java\tscript:` must be judged with them removed.
  final raw = href.trim();
  final squeezed = raw.replaceAll(RegExp(r'[\x00-\x20\x7F]'), '');
  if (squeezed.isEmpty || squeezed.startsWith('#')) {
    return MarkdownLink(MarkdownLinkKind.blocked, raw);
  }
  final scheme = _scheme.firstMatch(squeezed)?.group(1)?.toLowerCase();
  if (scheme == null || scheme.length == 1) {
    // No scheme, or a Windows drive letter.
    return MarkdownLink(MarkdownLinkKind.path, raw);
  }
  switch (scheme) {
    case 'img':
      return MarkdownLink(MarkdownLinkKind.image, raw);
    case 'file':
      final path = Uri.tryParse(raw)?.toFilePath(windows: false);
      return path == null || path.isEmpty
          ? MarkdownLink(MarkdownLinkKind.blocked, raw)
          : MarkdownLink(MarkdownLinkKind.path, path);
    case 'mailto':
      return Uri.tryParse(raw) == null
          ? MarkdownLink(MarkdownLinkKind.blocked, raw)
          : MarkdownLink(MarkdownLinkKind.mail, raw);
    case 'http' || 'https':
      final uri = Uri.tryParse(raw);
      if (uri == null || uri.host.isEmpty || raw != squeezed) {
        return MarkdownLink(MarkdownLinkKind.blocked, raw);
      }
      return MarkdownLink(
        isTailnetHost(uri.host)
            ? MarkdownLinkKind.tailnet
            : MarkdownLinkKind.web,
        raw,
      );
  }
  return MarkdownLink(MarkdownLinkKind.blocked, raw);
}

/// 100.64.0.0/10, Tailscale's IPv6 ULA, MagicDNS names and bare peer names.
bool isTailnetHost(String host) {
  final h = host.toLowerCase().replaceAll(RegExp(r'^\[|\]$'), '');
  if (h.endsWith('.ts.net')) return true;
  if (h.startsWith('fd7a:115c:a1e0:')) return true;
  final v4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.\d{1,3}\.\d{1,3}$').firstMatch(h);
  if (v4 != null) {
    final a = int.parse(v4.group(1)!);
    final b = int.parse(v4.group(2)!);
    return a == 100 && b >= 64 && b <= 127;
  }
  return !h.contains('.') && !h.contains(':') && h != 'localhost';
}

/// Opens [link] from a chat message; failures become a snack, never a throw.
Future<void> openMarkdownLink(
  BuildContext context,
  MarkdownLink link, {
  ValueChanged<String>? onOpenImage,
}) async {
  final l10n = AppLocalizations.of(context);
  switch (link.kind) {
    case MarkdownLinkKind.blocked:
      return;
    case MarkdownLinkKind.image:
      onOpenImage?.call(link.target);
      return;
    case MarkdownLinkKind.path:
      await Clipboard.setData(ClipboardData(text: link.target));
      if (context.mounted) showMotionSnack(context, l10n.agentPathCopied);
      return;
    case MarkdownLinkKind.tailnet:
      final uri = Uri.parse(link.target);
      final service = Service(
        id: '',
        node: uri.host,
        name: uri.host,
        url: link.target,
      );
      if (context.getInheritedWidgetOfExactType<BackendScope>() == null) {
        return _launch(context, link.target);
      }
      final result = await openService(context, service);
      if (!context.mounted) return;
      final notice = switch (result) {
        ServiceOpen.needsGateway => l10n.serviceNeedsGateway,
        ServiceOpen.openFailed => l10n.serviceOpenFailed,
        _ => '',
      };
      if (notice.isNotEmpty) showMotionSnack(context, notice);
    case MarkdownLinkKind.web || MarkdownLinkKind.mail:
      return _launch(context, link.target);
  }
}

Future<void> _launch(BuildContext context, String target) async {
  final opened = await launchUrl(
    Uri.parse(target),
    mode: LaunchMode.externalApplication,
  ).catchError((Object _) => false);
  if (!opened && context.mounted) {
    showMotionSnack(context, AppLocalizations.of(context).terminalOpenFailed);
  }
}
