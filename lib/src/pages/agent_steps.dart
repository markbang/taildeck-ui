import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../glyphs.dart';
import '../herdr.dart';
import '../l10n.dart';
import '../motion.dart';
import '../widgets/controls.dart';
import '../widgets/loading.dart';

/// Everything one turn did before its reply, folded under one row.
class StepsFold {
  const StepsFold({
    required this.key,
    required this.items,
    required this.running,
  });

  /// Stable for the turn across reloads: its prompt and its first tool call.
  final String key;

  /// Tool calls with the thinking and interim text between them, in order.
  final List<HerdrMessage> items;

  /// The turn is the latest one and the agent is still working on it.
  final bool running;

  Iterable<HerdrMessage> get tools => items.where((m) => m.isTool);

  /// The tool name used most, the earliest one on a tie.
  String dominantTool(String fallback) {
    final counts = <String, int>{};
    for (final tool in tools) {
      final name = tool.name.isNotEmpty ? tool.name : fallback;
      counts[name] = (counts[name] ?? 0) + 1;
    }
    String? best;
    for (final entry in counts.entries) {
      if (best == null || entry.value > counts[best]!) best = entry.key;
    }
    return best ?? fallback;
  }
}

/// Transcript rows, one turn per user message. A turn with two or more tool
/// calls folds everything before its final reply into a [StepsFold]; the
/// latest turn folds all of its work while the agent runs, since it has no
/// reply yet. Other turns keep the old rows: a message, or a run of tool
/// calls as a `List<HerdrMessage>`.
List<Object> chatRows(List<HerdrMessage> messages, {required bool working}) {
  final turns = <List<HerdrMessage>>[];
  for (final message in messages) {
    if (message.role == 'user' || turns.isEmpty) turns.add([]);
    turns.last.add(message);
  }
  final rows = <Object>[];
  for (var i = 0; i < turns.length; i++) {
    final turn = turns[i];
    final running = working && i == turns.length - 1;
    final user = turn.first.role == 'user' ? turn.first : null;
    if (user != null) rows.add(user);
    final body = user == null ? turn : turn.sublist(1);
    final reply = body.lastIndexWhere(
      (m) => !m.isTool && m.role == 'assistant' && m.text.trim().isNotEmpty,
    );
    final end = running || reply < 0 ? body.length : reply;
    final work = body.sublist(0, end);
    final tools = work.where((m) => m.isTool).toList();
    if (tools.length >= 2) {
      final first = tools.first;
      rows.add(
        StepsFold(
          key: [
            user?.text ?? '',
            first.call.isNotEmpty
                ? first.call
                : '${first.name}|${first.summary}',
          ].join('\u0000'),
          items: work,
          running: running,
        ),
      );
    } else {
      rows.addAll(_runs(work));
    }
    rows.addAll(_runs(body.sublist(end)));
  }
  return rows;
}

/// Consecutive tool calls as one list; subagent calls keep their own row.
List<Object> _runs(List<HerdrMessage> messages) {
  final rows = <Object>[];
  var group = <HerdrMessage>[];
  for (final message in messages) {
    if (message.isTool && !message.isSubagent) {
      group.add(message);
      continue;
    }
    if (group.isNotEmpty) rows.add(group);
    group = <HerdrMessage>[];
    rows.add(message);
  }
  if (group.isNotEmpty) rows.add(group);
  return rows;
}

/// Which folds the user opened or closed, for as long as the chat page lives:
/// scrolling a fold away and back, or a reload, keeps it as it was. A fold
/// nobody touched follows its turn, open while it runs.
class StepsFoldMemory {
  final _chosen = <String, bool>{};

  bool isOpen(StepsFold fold) => _chosen[fold.key] ?? fold.running;

  bool chosen(StepsFold fold) => _chosen.containsKey(fold.key);

  void choose(StepsFold fold, bool open) => _chosen[fold.key] = open;
}

/// "N steps · Bash" over a turn's work, as the Kotlin timeline's `ToolGroup`.
/// Opening or closing keeps the header where it is; a fold that closes itself
/// above the viewport when its turn ends takes its height out of the scroll
/// offset, so what is on screen does not move.
class StepsBlock extends StatefulWidget {
  const StepsBlock({
    super.key,
    required this.fold,
    required this.memory,
    required this.live,
    required this.itemBuilder,
  });

  final StepsFold fold;
  final StepsFoldMemory memory;

  /// The agent is working: a pending call shows a spinner.
  final bool live;
  final Widget Function(HerdrMessage message) itemBuilder;

  @override
  State<StepsBlock> createState() => _StepsBlockState();
}

class _StepsBlockState extends State<StepsBlock> {
  final _header = GlobalKey();
  late bool _open = widget.memory.isOpen(widget.fold);
  bool _instant = false;

  /// When the fold last opened or closed. Only that animates its height: a
  /// reply typed out inside a running fold grows with the list, unclipped.
  DateTime? _toggledAt;

  bool get _sizing {
    final at = _toggledAt;
    return at != null && DateTime.now().difference(at) < slowSpatial.duration;
  }

  @override
  void didUpdateWidget(StepsBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    final open = widget.memory.isOpen(widget.fold);
    if (open == _open) return;
    if (!open && _aboveViewport()) {
      // Nothing above the viewport animates: this frame lays the fold out at
      // its real height, the next closes it together with the correction.
      _instant = true;
      SchedulerBinding.instance.addPostFrameCallback((_) => _closeAnchored());
      return;
    }
    _open = open;
    _toggledAt = DateTime.now();
  }

  bool _aboveViewport() {
    final header = _header.currentContext?.findRenderObject();
    final scrollable = Scrollable.maybeOf(context);
    final viewport = scrollable?.context.findRenderObject();
    if (header is! RenderBox || viewport is! RenderBox || !header.attached) {
      return false;
    }
    return header.localToGlobal(Offset.zero, ancestor: viewport).dy < 0;
  }

  void _closeAnchored() {
    if (!mounted || widget.memory.isOpen(widget.fold) || !_open) {
      _instant = false;
      return;
    }
    final box = context.findRenderObject();
    final header = _header.currentContext?.findRenderObject();
    final position = Scrollable.maybeOf(context)?.position;
    if (box is RenderBox && header is RenderBox && position != null) {
      final shrink = box.size.height - header.size.height;
      position.jumpTo(
        (position.pixels - shrink).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    }
    setState(() => _open = false);
    SchedulerBinding.instance.addPostFrameCallback((_) => _instant = false);
  }

  void _toggle() {
    widget.memory.choose(widget.fold, !_open);
    setState(() {
      _open = !_open;
      _toggledAt = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final l10n = AppLocalizations.of(context);
    final fold = widget.fold;
    final count = fold.tools.length;
    final running = fold.running && widget.live
        ? fold.items.reversed.where((m) => m.isTool && m.pending).firstOrNull
        : null;
    final title =
        '${l10n.agentToolSteps(count)} · ${fold.dominantTool(l10n.agentTool)}';
    final shown = _open
        ? fold.items
        : running != null
        ? [running]
        : const <HerdrMessage>[];
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          key: _header,
          container: true,
          button: true,
          expanded: _open,
          label: title,
          excludeSemantics: true,
          onTap: _toggle,
          child: TapFeedback(
            onTap: _toggle,
            shape: AppShape.all(AppCorner.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: running != null
                        ? const LoadingIndicator(size: 16)
                        : GlyphIcon(
                            Glyphs2.checklist,
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.caption1
                          .of(context, emphasized: true)
                          .copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  RotatingChevron(
                    open: _open,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (shown.isNotEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 11, bottom: 4),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: BorderDirectional(
                  start: BorderSide(color: scheme.outlineVariant, width: 1.5),
                ),
              ),
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final message in shown) widget.itemBuilder(message),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
    // A fold closed for the scroll correction must not animate: the offset
    // already took its whole height out.
    if (_instant) return body;
    return AnimatedSize(
      // AnimatedSize asserts on a zero duration; 1 ms settles in one frame,
      // and that frame paints unclipped so a new line never shows cut.
      duration: _sizing
          ? motionDuration(context, slowSpatial)
          : const Duration(milliseconds: 1),
      clipBehavior: _sizing ? Clip.hardEdge : Clip.none,
      curve: context.disableAnimations ? Curves.linear : slowSpatial.curve,
      alignment: Alignment.topCenter,
      child: body,
    );
  }
}
