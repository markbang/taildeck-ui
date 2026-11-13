import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../backend.dart';
import '../glyphs.dart';
import '../l10n.dart';
import '../widgets/foundation.dart';

/// `td_logs()` as a monospace, scrollable page.
class LogsPage extends StatefulWidget {
  const LogsPage({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  String _logs = '';
  bool _loaded = false;
  String _notice = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _logs = BackendScope.of(context).logsText();
  }

  void _refresh() {
    setState(() => _logs = BackendScope.of(context).logsText());
  }

  Future<void> _copy() async {
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: _logs));
    if (mounted) setState(() => _notice = l10n.logsCopied);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.colorScheme;
    return PageBody(
      title: l10n.logs,
      leading: IconButton(
        onPressed: widget.onBack,
        icon: const GlyphIcon(Glyphs.chevronBack),
        tooltip: l10n.back,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: _refresh,
            icon: const GlyphIcon(Glyphs2.refresh),
            tooltip: l10n.refresh,
          ),
          IconButton(
            onPressed: _logs.isEmpty ? null : _copy,
            icon: const GlyphIcon(Glyphs.copy),
            tooltip: l10n.copy,
          ),
        ],
      ),
      children: [
        if (_notice.isNotEmpty) ...[
          InlineNotice(text: _notice, tint: scheme.onSurfaceVariant),
          const SizedBox(height: 14),
        ],
        Card(
          radius: AppCorner.xl,
          padding: EdgeInsets.zero,
          child: Container(
            constraints: const BoxConstraints(minHeight: 200),
            padding: const EdgeInsets.all(14),
            child: _logs.isEmpty
                ? Text(
                    l10n.logsEmpty,
                    style: AppTextStyle.footnote
                        .of(context)
                        .copyWith(color: scheme.onSurfaceVariant),
                  )
                : SelectableText(
                    _logs,
                    style: AppTextStyle.footnote.of(context).copyWith(
                      fontFamily: 'DejaVuSansMono',
                      fontSize: 11,
                      height: 1.5,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
