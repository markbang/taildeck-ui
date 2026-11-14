import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../herdr.dart';
import '../l10n.dart';
import '../widgets/controls.dart';
import '../widgets/select_row.dart';

typedef NewAgentChoice = ({
  String harness,
  String project,
  String task,
  String promptError,
});

/// With [herdr] the sheet really starts an agent in herdr; without it (web),
/// the page inserts a demo card.
Future<NewAgentChoice?> showNewAgentSheet(
  BuildContext context, {
  HerdrController? herdr,
  List<({String id, String label})> workspaces = const [],
}) {
  return showFormSheet<NewAgentChoice>(
    context: context,
    builder: (context) =>
        _NewAgentSheet(herdr: herdr, workspaces: workspaces),
  );
}

class _NewAgentSheet extends StatefulWidget {
  const _NewAgentSheet({this.herdr, this.workspaces = const []});

  final HerdrController? herdr;
  final List<({String id, String label})> workspaces;

  @override
  State<_NewAgentSheet> createState() => _NewAgentSheetState();
}

class _NewAgentSheetState extends State<_NewAgentSheet> {
  static const _harnesses = ['claude', 'codex', 'pi'];
  static const _liveHarnesses = [
    'claude',
    'codex',
    'pi',
    'opencode',
    'gemini',
    'amp',
  ];
  static const _projects = ['taildeck', 'infra', 'router'];
  static final _namePattern = RegExp(r'^[a-z][a-z0-9_-]{0,31}$');

  String _harness = 'claude';
  String _project = 'taildeck';
  String _workspace = '';
  final _nameInput = TextEditingController();
  final _cwd = TextEditingController();
  final _task = TextEditingController();
  bool _busy = false;
  String _error = '';

  bool get _live => widget.herdr != null;

  Set<String> get _taken => {
    for (final agent in widget.herdr?.agents ?? const <HerdrAgent>[])
      agent.name,
  };

  String get _name {
    final typed = _nameInput.text.trim().toLowerCase();
    if (typed.isNotEmpty) return typed;
    final taken = _taken;
    for (var i = 1; ; i++) {
      final name = i == 1 ? _harness : '$_harness-$i';
      if (!taken.contains(name)) return name;
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.workspaces.isNotEmpty) {
      _workspace = widget.workspaces.first.id;
    }
  }

  @override
  void dispose() {
    _nameInput.dispose();
    _cwd.dispose();
    _task.dispose();
    super.dispose();
  }

  String? _nameError(AppLocalizations l10n) {
    final name = _name;
    if (!_namePattern.hasMatch(_name)) return l10n.agentNameInvalid;
    if (_taken.contains(name)) return l10n.agentNameTaken;
    return null;
  }

  Future<void> _create() async {
    final l10n = AppLocalizations.of(context);
    final herdr = widget.herdr;
    if (herdr == null) {
      Navigator.of(context).pop((
        harness: _harness,
        project: _project,
        task: _task.text.trim(),
        promptError: '',
      ));
      return;
    }
    if (_busy || _nameError(l10n) != null) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final created = await herdr.createAgent(
        kind: _harness,
        name: _name,
        workspaceId: _workspace,
        cwd: _cwd.text,
        prompt: _task.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop((
        harness: _harness,
        project: _workspace,
        task: _task.text.trim(),
        promptError: created.promptError,
      ));
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.colorScheme;
    final nameError = _live ? _nameError(l10n) : null;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        22,
        20,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: SingleChildScrollView(
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
                        _live
                            ? 'herdr · ${widget.herdr?.node ?? ''}'
                            : 'herdr · devbox',
                        style: AppTextStyle.footnote
                            .of(context)
                            .copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
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
                  SelectRow<String>(
                    label: l10n.harness,
                    value: _harness,
                    options: [
                      for (final kind in _live ? _liveHarnesses : _harnesses)
                        (kind, kind),
                    ],
                    onChanged: (value) => setState(() => _harness = value),
                  ),
                  const _RowDivider(),
                  if (_live) ...[
                    _TextFieldRow(
                      label: l10n.agentName,
                      controller: _nameInput,
                      hint: _name,
                      onChanged: (_) => setState(() {}),
                      error: nameError,
                    ),
                    const _RowDivider(),
                    SelectRow<String>(
                      label: l10n.agentWorkspace,
                      value: _workspace,
                      options: [
                        for (final workspace in widget.workspaces)
                          (workspace.id, workspace.label),
                        ('', l10n.agentNewWorkspace),
                      ],
                      onChanged: (value) => setState(() => _workspace = value),
                    ),
                    const _RowDivider(),
                    _TextFieldRow(
                      label: l10n.agentDir,
                      controller: _cwd,
                      hint: l10n.agentDirHint,
                    ),
                  ] else
                    SelectRow<String>(
                      label: l10n.project,
                      value: _project,
                      options: [for (final p in _projects) (p, p)],
                      onChanged: (value) => setState(() => _project = value),
                    ),
                  const _RowDivider(),
                  _TextFieldRow(
                    label: l10n.task,
                    controller: _task,
                    hint: l10n.taskHint,
                  ),
                ],
              ),
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                _error,
                style: AppTextStyle.footnote
                    .of(context)
                    .copyWith(color: scheme.error),
              ),
            ],
            const SizedBox(height: 16),
            LoadingButton(
              label: l10n.create,
              loading: _busy,
              onPressed: nameError == null ? _create : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _TextFieldRow extends StatelessWidget {
  const _TextFieldRow({
    required this.label,
    required this.controller,
    required this.hint,
    this.onChanged,
    this.error,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.listTitleStyle),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            onChanged: onChanged,
            style: context.listSubtitleStyle,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: context.listCaptionStyle,
              filled: true,
              fillColor: SurfaceLevel.block.colorOf(scheme),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 11,
              ),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                error!,
                style: AppTextStyle.caption1
                    .of(context)
                    .copyWith(color: scheme.error),
              ),
            ),
        ],
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 16),
      child: Divider(height: 0.5, thickness: 0.5),
    );
  }
}
