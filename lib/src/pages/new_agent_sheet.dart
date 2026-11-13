import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../l10n.dart';

typedef NewAgentChoice = ({String harness, String project, String task});

Future<NewAgentChoice?> showNewAgentSheet(BuildContext context) {
  return showFormSheet<NewAgentChoice>(
    context: context,
    builder: (context) => const _NewAgentSheet(),
  );
}

class _NewAgentSheet extends StatefulWidget {
  const _NewAgentSheet();

  @override
  State<_NewAgentSheet> createState() => _NewAgentSheetState();
}

class _NewAgentSheetState extends State<_NewAgentSheet> {
  static const _harnesses = ['claude', 'codex', 'pi'];
  static const _projects = ['taildeck', 'infra', 'router'];

  String _harness = 'claude';
  String _project = 'taildeck';
  final _task = TextEditingController();

  @override
  void dispose() {
    _task.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        22,
        20,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.newAgent,
                      style: AppTextStyle.title2.of(context, emphasized: true),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'herdr · devbox',
                      style: AppTextStyle.footnote
                          .of(context)
                          .copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const GlyphIcon(Glyphs.close),
                tooltip: l10n.close,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Card(
            radius: AppCorner.xl,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SelectRow<String>(
                  label: l10n.harness,
                  value: _harness,
                  options: [for (final h in _harnesses) (h, h)],
                  onChanged: (value) => setState(() => _harness = value),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Divider(height: 0.5, thickness: 0.5),
                ),
                _SelectRow<String>(
                  label: l10n.project,
                  value: _project,
                  options: [for (final p in _projects) (p, p)],
                  onChanged: (value) => setState(() => _project = value),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Divider(height: 0.5, thickness: 0.5),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.task, style: context.listTitleStyle),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _task,
                        style: context.listSubtitleStyle,
                        decoration: InputDecoration(
                          hintText: l10n.taskHint,
                          hintStyle: context.listCaptionStyle,
                          filled: true,
                          fillColor: SurfaceLevel.block.colorOf(scheme),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(
              (
                harness: _harness,
                project: _project,
                task: _task.text.trim(),
              ),
            ),
            child: Text(l10n.create),
          ),
        ],
      ),
    );
  }
}

class _SelectRow<T> extends StatelessWidget {
  const _SelectRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final current = options.firstWhere((o) => o.$1 == value).$2;
    return PopupAnchor(
      targetBuilder: (open) => PressRegion(
        onTap: open,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              Expanded(child: Text(label, style: context.listTitleStyle)),
              Text(
                current,
                style: AppTextStyle.body
                    .of(context)
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 4),
              GlyphIcon(
                Glyphs.chevronDown,
                size: 14,
                color: scheme.onSurfaceVariant.opacity50,
              ),
            ],
          ),
        ),
      ),
      popupBuilder: (context) => PopupMenu(
        items: [
          for (final (option, text) in options)
            PopupMenuItem(
              label: text,
              checked: option == value,
              onPressed: () => onChanged(option),
            ),
        ],
      ),
    );
  }
}
