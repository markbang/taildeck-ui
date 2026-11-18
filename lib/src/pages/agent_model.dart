import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../glyphs.dart';
import '../herdr.dart';
import '../l10n.dart';
import '../motion.dart';
import '../widgets/bottom_sheet.dart';
import '../widgets/controls.dart';
import '../widgets/foundation.dart';
import '../widgets/loading.dart';

/// The model and reasoning level a session runs with.
typedef ModelSettings = ({String model, String effort});

/// What the picker hands back: a model, a level, or the agent's restart.
typedef ModelPick = ({String? model, String? effort, bool restart});

/// The header's model capsule: the session's model by its short name, a
/// spinner while a switch is on its way, and the error tint when one failed.
class ModelCapsule extends StatelessWidget {
  const ModelCapsule({
    super.key,
    required this.settings,
    required this.onTap,
    required this.onLongPress,
    this.busyLabel,
    this.failed = false,
  });

  final ModelSettings settings;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// Shown with a spinner while a switch or a restart runs.
  final String? busyLabel;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.colorScheme;
    final busy = busyLabel;
    final name = settings.model.isEmpty
        ? l10n.agentModel
        : modelShortName(settings.model);
    final tint = failed ? scheme.error : scheme.onSurface;
    final label = busy ?? name;
    return Semantics(
      container: true,
      button: true,
      label:
          busy ??
          l10n.agentModelCapsule(name, effortLabel(l10n, settings.effort)),
      value: failed ? l10n.agentModelSwitchFailedShort : null,
      onLongPressHint: l10n.agentModelDetails,
      excludeSemantics: true,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: TapFeedback(
          onTap: onTap,
          shape: AppShape.full,
          child: Container(
            key: const ValueKey('model-capsule'),
            constraints: const BoxConstraints(maxWidth: 150, minHeight: 36),
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
            decoration: ShapeDecoration(
              color: failed
                  ? scheme.error.withValues(alpha: 0.14)
                  : SurfaceLevel.block.colorOf(scheme),
              shape: AppShape.full,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy != null) ...[
                  const LoadingIndicator(size: 14),
                  const SizedBox(width: 6),
                ] else if (failed) ...[
                  GlyphIcon(Glyphs2.bolt, size: 13, color: tint),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: FadeThrough(
                    child: Text(
                      label,
                      key: ValueKey(label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.subheadline
                          .of(context, emphasized: true)
                          .copyWith(color: tint),
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                GlyphIcon(
                  Glyphs.chevronDown,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String effortLabel(AppLocalizations l10n, String effort) => switch (effort) {
  'off' || 'none' => l10n.effortOff,
  'minimal' => l10n.effortMinimal,
  'low' => l10n.effortLow,
  'medium' => l10n.effortMedium,
  'high' => l10n.effortHigh,
  'xhigh' => l10n.effortXhigh,
  'max' => l10n.effortMax,
  'ultra' => l10n.effortUltra,
  'auto' => l10n.effortAuto,
  _ => effort,
};

/// The grouped picker: the models herdr reports for this agent, its reasoning
/// levels, and the agent's restart. Each choice is the agent's own command and
/// takes effect from its next turn.
Future<ModelPick?> showModelPanel(
  BuildContext context, {
  required Future<HerdrModels> options,
  required String kind,
  required ModelSettings current,
  required bool busy,
}) => showMotionSheet<ModelPick>(
  context: context,
  builder: (context) =>
      _ModelPanel(options: options, kind: kind, current: current, busy: busy),
);

class _ModelPanel extends StatelessWidget {
  const _ModelPanel({
    required this.options,
    required this.kind,
    required this.current,
    required this.busy,
  });

  final Future<HerdrModels> options;
  final String kind;
  final ModelSettings current;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.colorScheme;
    final switchable = canSwitchModel(kind);
    final caption = AppTextStyle.footnote
        .of(context)
        .copyWith(color: scheme.onSurfaceVariant);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.agentModelPanel,
              style: AppTextStyle.title2.of(context, emphasized: true),
            ),
            const SizedBox(height: 4),
            Text(
              switchable ? l10n.agentModelNextTurn : l10n.agentModelFixed,
              style: caption,
            ),
            if (busy && switchable) ...[
              const SizedBox(height: 10),
              InlineNotice(
                text: l10n.agentModelBusy,
                tint: const Color(0xFFE3B341),
              ),
            ],
            if (switchable)
              FutureBuilder<HerdrModels>(
                future: options,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: InlineNotice(
                        text: l10n.agentActionFailed('${snapshot.error}'),
                      ),
                    );
                  }
                  final data = snapshot.data;
                  if (data == null) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Center(
                        child: LoadingIndicator(
                          size: 22,
                          semanticLabel: l10n.pleaseWait,
                        ),
                      ),
                    );
                  }
                  return _Choices(
                    options: data,
                    kind: kind,
                    current: current,
                    enabled: !busy,
                  );
                },
              ),
            const SizedBox(height: 14),
            GroupCard(
              dividerInset: 16,
              header: Text(l10n.agentModelSession),
              children: [
                _Row(
                  title: l10n.agentRestart,
                  subtitle: l10n.agentRestartBody,
                  onTap: () =>
                      Navigator.of(context)
                          .pop((model: null, effort: null, restart: true)),
                  trailing: GlyphIcon(
                    Glyphs2.refresh,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Choices extends StatelessWidget {
  const _Choices({
    required this.options,
    required this.kind,
    required this.current,
    required this.enabled,
  });

  final HerdrModels options;
  final String kind;
  final ModelSettings current;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = context.colorScheme;
    HerdrModel? selected;
    for (final model in options.models) {
      if (isCurrentModel(kind, current.model, model.id)) selected = model;
    }
    final efforts = options.effortsFor(selected);
    void pick(ModelPick choice) => Navigator.of(context).pop(choice);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        GroupCard(
          dividerInset: 16,
          header: Text(l10n.agentModel),
          children: [
            if (options.models.isEmpty)
              _Row(
                title: current.model.isEmpty
                    ? l10n.agentModelEmpty
                    : modelShortName(current.model),
                subtitle: current.model.isEmpty ? null : current.model,
              ),
            for (final model in options.models)
              _Row(
                title: model.name,
                subtitle: [
                  model.id,
                  if (model.efforts.isNotEmpty)
                    model.efforts.map((e) => effortLabel(l10n, e)).join(' / '),
                  if (model.defaultEffort.isNotEmpty)
                    l10n.agentModelDefault(
                      effortLabel(l10n, model.defaultEffort),
                    ),
                ].join(' · '),
                mono: true,
                selected: model == selected,
                onTap: enabled && model != selected
                    ? () {
                        final keep = model.efforts.contains(current.effort)
                            ? current.effort
                            : null;
                        pick((
                          model: model.id,
                          effort:
                              keep ??
                              (model.defaultEffort.isEmpty
                                  ? null
                                  : model.defaultEffort),
                          restart: false,
                        ));
                      }
                    : null,
              ),
          ],
        ),
        if (efforts.isNotEmpty) ...[
          const SizedBox(height: 14),
          GroupCard(
            dividerInset: 16,
            header: Text(l10n.agentEffort),
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final effort in efforts)
                      Chip(
                        label: effortLabel(l10n, effort),
                        selected:
                            effort.toLowerCase() ==
                            current.effort.toLowerCase(),
                        onPressed:
                            enabled &&
                                effort.toLowerCase() !=
                                    current.effort.toLowerCase()
                            ? () => pick((
                                model: null,
                                effort: effort,
                                restart: false,
                              ))
                            : null,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
        if (!enabled)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              l10n.agentModelBusy,
              style: AppTextStyle.caption1
                  .of(context)
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    this.subtitle,
    this.mono = false,
    this.selected = false,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final bool mono;
  final bool selected;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final subtitle = this.subtitle;
    return Semantics(
      selected: selected,
      child: TapFeedback(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyle.body.of(context)),
                    if (subtitle != null && subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.caption1
                            .of(context)
                            .copyWith(
                              color: scheme.onSurfaceVariant,
                              fontFamily: mono ? 'DejaVuSansMono' : null,
                            ),
                      ),
                  ],
                ),
              ),
              if (selected)
                GlyphIcon(Glyphs.check, size: 16, color: scheme.primary)
              else
                ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// Long-press on the capsule: what this session runs with.
Future<void> showModelDetails(
  BuildContext context, {
  required String kind,
  required String pane,
  required ModelSettings recorded,
  required ModelSettings shown,
  required int contextUsed,
  required int contextWindow,
}) {
  final l10n = AppLocalizations.of(context);
  final pending = shown != recorded;
  return showMotionSheet<void>(
    context: context,
    builder: (context) => Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.agentModelDetails,
            style: AppTextStyle.title2.of(context, emphasized: true),
          ),
          const SizedBox(height: 10),
          GroupCard(
            dividerInset: 16,
            children: [
              _Row(
                title: recorded.model.isEmpty
                    ? l10n.agentModelUnknown
                    : modelShortName(recorded.model),
                subtitle: recorded.model.isEmpty
                    ? l10n.agentModel
                    : recorded.model,
                mono: recorded.model.isNotEmpty,
              ),
              _Row(
                title: recorded.effort.isEmpty
                    ? l10n.agentModelUnknown
                    : effortLabel(l10n, recorded.effort),
                subtitle: l10n.agentEffort,
              ),
              if (contextWindow > 0)
                _Row(
                  title:
                      '${contextLabel(contextUsed)} / ${contextLabel(contextWindow)}'
                      ' · ${(contextUsed * 100 / contextWindow).round()}%',
                  subtitle: l10n.agentContext,
                ),
              _Row(title: kind, subtitle: '${l10n.agentKind} · $pane'),
            ],
          ),
          if (pending) ...[
            const SizedBox(height: 10),
            InlineNotice(
              text: l10n.agentModelPending(
                [
                  if (shown.model != recorded.model)
                    modelShortName(shown.model),
                  if (shown.effort != recorded.effort)
                    effortLabel(l10n, shown.effort),
                ].join(' · '),
              ),
              tint: context.colorScheme.primary,
            ),
          ],
        ],
      ),
    ),
  );
}

String contextLabel(int tokens) {
  if (tokens >= 1000000) return '${(tokens / 1000000).toStringAsFixed(1)}M';
  if (tokens >= 1000) return '${(tokens / 1000).round()}k';
  return '$tokens';
}
