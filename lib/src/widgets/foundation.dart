import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../data.dart';
import '../l10n.dart';
import '../glyphs.dart';
import '../motion.dart';
import '../services.dart';
import 'controls.dart';
import 'pull_to_refresh.dart';
import 'service_avatar.dart';
import 'loading.dart';
import 'header.dart';

/// Room a page leaves at its foot: what floats over it (the navigation dock)
/// plus the system gesture area, and a gap. Every scrollable page ends with
/// this, so no row can sit under the dock.
double pageBottomPadding(BuildContext context) => 40 + context.bottomInset;

/// The value at the end of a row: one line, [maxWidth] at most, so a long
/// value (a control server URL) ellipsizes instead of wrapping into two
/// centred lines.
class RowValue extends StatelessWidget {
  const RowValue(
    this.text, {
    super.key,
    this.maxWidth = 160,
    this.style,
    this.tint,
  });

  final String text;
  final double maxWidth;
  final TextStyle? style;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Text(
        text,
        textAlign: TextAlign.end,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: (style ?? AppTextStyle.body.of(context)).copyWith(
          color: tint ?? context.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class PageBody extends StatefulWidget {
  const PageBody({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onBack,
    this.children,
    this.maxWidth = 720,
    this.padding,
    this.onRefresh,
    this.animateSize = false,
    this.bottomExtra = 0,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  /// A subpage: its bar carries the back button and the title, and the body
  /// has no large title of its own, as FlClash's second-level pages.
  final VoidCallback? onBack;

  final List<Widget>? children;
  final double maxWidth;
  final EdgeInsets? padding;

  /// Pull to refresh, as the Kotlin app's `RefreshBox` offers on lists.
  final Future<void> Function()? onRefresh;

  /// More room at the foot, for a button floating above the dock.
  final double bottomExtra;

  /// Resizes the page's sections with `animateContentSize(Motion.slow())`, as
  /// the Kotlin settings page does.
  final bool animateSize;

  /// How far the list scrolls before the bar is compact: one title line, so
  /// the material is in by the time content reaches the bar.
  static const _collapseDistance = 32.0;

  @override
  State<PageBody> createState() => _PageBodyState();
}

class _PageBodyState extends State<PageBody> {
  final _controller = ScrollController();

  /// 0 is a first-level page's title at rest, 1 the compact bar a subpage
  /// opens with.
  final _collapse = ValueNotifier<double>(1);

  @override
  void initState() {
    super.initState();
    _collapse.value = widget.onBack == null ? 0 : 1;
    _controller.addListener(_handleScroll);
  }

  @override
  void didUpdateWidget(PageBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onBack != widget.onBack) _handleScroll();
  }

  @override
  void dispose() {
    _controller.dispose();
    _collapse.dispose();
    super.dispose();
  }

  void _handleScroll() {
    final offset = widget.onBack != null
        ? PageBody._collapseDistance
        : (_controller.hasClients ? _controller.offset : 0.0);
    final collapse = (offset / PageBody._collapseDistance).clamp(0.0, 1.0);
    if ((collapse - _collapse.value).abs() > 0.004) _collapse.value = collapse;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: widget.maxWidth),
              child: _refreshable(
                context,
                ListView(
                  controller: _controller,
                  physics: widget.onRefresh == null
                      ? null
                      : const AlwaysScrollableScrollPhysics(),
                  padding:
                      widget.padding ??
                      EdgeInsets.fromLTRB(
                        20,
                        context.contentTopPadding,
                        20,
                        pageBottomPadding(context) + widget.bottomExtra,
                      ),
                  children: [
                    if (widget.animateSize)
                      AnimatedContentSize(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [...?widget.children],
                        ),
                      )
                    else
                      ...?widget.children,
                  ],
                ),
              ),
            ),
          ),
        ),
        PositionedDirectional(
          start: 0,
          end: 0,
          top: 0,
          child: ValueListenableBuilder<double>(
            valueListenable: _collapse,
            builder: (context, collapse, _) => PageHeader(
              collapse: collapse,
              child: PageBar(
                title: widget.title,
                subtitle: widget.subtitle,
                onBack: widget.onBack,
                trailing: widget.trailing,
                maxWidth: widget.maxWidth,
                collapse: collapse,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _refreshable(BuildContext context, Widget list) {
    final onRefresh = widget.onRefresh;
    if (onRefresh == null) return list;
    return PullToRefresh(onRefresh: onRefresh, child: list);
  }
}

class GroupCard extends StatelessWidget {
  const GroupCard({
    super.key,
    required this.children,
    this.dividerInset = 60,
    this.header,
  });

  final List<Widget> children;

  /// Where a divider starts, so it lines up with the rows' titles.
  final double dividerInset;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(
          Padding(
            padding: EdgeInsets.only(left: dividerInset),
            child: Divider(height: 0.5, thickness: 0.5),
          ),
        );
      }
      rows.add(children[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: DefaultTextStyle.merge(
              style: AppTextStyle.footnote
                  .of(context)
                  .copyWith(color: context.colorScheme.onSurfaceVariant),
              child: header!,
            ),
          ),
        Card(
          radius: AppCorner.xl,
          padding: EdgeInsets.zero,
          child: ClipRSuperellipse(
            borderRadius: AppRadius.all(AppCorner.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            ),
          ),
        ),
      ],
    );
  }
}

/// A tinted strip for inline errors and notices.
class InlineNotice extends StatelessWidget {
  const InlineNotice({super.key, required this.text, this.tint});

  final String text;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final color = tint ?? context.colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: ShapeDecoration(
        color: color.withValues(alpha: 0.12),
        shape: AppShape.all(AppCorner.sm),
      ),
      child: Text(
        text,
        style: AppTextStyle.footnote.of(context).copyWith(color: color),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing, this.glyph});

  final String text;
  final Widget? trailing;

  /// A mark before the label, as FlClash's section headers carry.
  final Glyph? glyph;

  @override
  Widget build(BuildContext context) {
    final glyph = this.glyph;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
      child: Row(
        children: [
          if (glyph != null) ...[
            GlyphIcon(
              glyph,
              size: 16,
              color: context.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              text,
              style: AppTextStyle.subheadline
                  .of(context)
                  .copyWith(color: context.colorScheme.onSurfaceVariant),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// One screen-reader node for a pressable row: [label] replaces the texts
/// inside, so the row reads as a single item.
class IconBadge extends StatelessWidget {
  const IconBadge(this.glyph, {super.key, this.tint});

  final Glyph glyph;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final color = tint ?? scheme.primary;
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: color.withValues(alpha: 0.14),
        shape: AppShape.all(10),
      ),
      child: GlyphIcon(glyph, size: 18, color: color),
    );
  }
}

class RowSemantics extends StatelessWidget {
  const RowSemantics({
    super.key,
    required this.label,
    this.hint,
    this.onTap,
    this.onLongPress,
    required this.child,
  });

  final String label;
  final String? hint;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: onTap != null,
      label: label,
      hint: hint,
      onTap: onTap,
      onLongPress: onLongPress,
      excludeSemantics: true,
      child: child,
    );
  }
}

class NodeBadge extends StatelessWidget {
  const NodeBadge(this.node, {super.key, this.size = 40});

  final NodeItem node;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: node.tint.withValues(alpha: node.online ? 0.18 : 0.08),
        shape: AppShape.all(size * 0.32),
      ),
      child: GlyphIcon(
        switch (node.os) {
          'macOS' => Glyphs2.laptop,
          'Windows' => Glyphs2.monitor,
          'Android' || 'iOS' => Glyphs2.phone,
          _ => Glyphs2.nodes,
        },
        size: size * 0.52,
        color: node.online ? node.tint : node.tint.withValues(alpha: 0.45),
      ),
    );
  }
}

class PathBadge extends StatelessWidget {
  const PathBadge({super.key, required this.node, this.compact = false});

  final NodeItem node;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final direct = node.direct;
    final tint = direct ? scheme.primary : scheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlyphIcon(direct ? Glyphs2.bolt : Glyphs2.relay, size: 13, color: tint),
        const SizedBox(width: 4),
        Text(
          direct
              ? AppLocalizations.of(context).direct
              : AppLocalizations.of(context).relay(node.relay),
          style: AppTextStyle.caption1.of(context).copyWith(color: tint),
        ),
      ],
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.tint,
    this.dot = false,
    this.pulse = false,
  });

  final String label;
  final Color tint;

  /// Draws the status dot the Kotlin app's chip carries.
  final bool dot;

  /// Fades the dot in and out while the subject is working or blocked.
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dot ? 7 : 8, vertical: 3),
      decoration: ShapeDecoration(
        color: tint.withValues(alpha: 0.16),
        shape: AppShape.full,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            PulsingDot(color: tint, size: 6, pulse: pulse),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: AppTextStyle.caption2
                .of(context, emphasized: true)
                .copyWith(color: tint),
          ),
        ],
      ),
    );
  }
}

class TrafficLabel extends StatelessWidget {
  const TrafficLabel({super.key, required this.node});

  final NodeItem node;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final style = AppTextStyle.caption1
        .of(context)
        .copyWith(color: scheme.onSurfaceVariant);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlyphIcon(Glyphs2.arrowDown, size: 11, color: scheme.onSurfaceVariant),
        const SizedBox(width: 2),
        Text(node.rx, style: style),
        const SizedBox(width: 8),
        GlyphIcon(Glyphs2.arrowUp, size: 11, color: scheme.onSurfaceVariant),
        const SizedBox(width: 2),
        Text(node.tx, style: style),
      ],
    );
  }
}

/// The elbow that ties a peer row to the self card, iOS-style.
class Connector extends StatelessWidget {
  const Connector({super.key, this.isFirst = false});

  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(22, 38),
      painter: _ConnectorPainter(
        color: Divider.colorOf(context),
        isFirst: isFirst,
      ),
    );
  }
}

class _ConnectorPainter extends CustomPainter {
  const _ConnectorPainter({required this.color, required this.isFirst});

  final Color color;
  final bool isFirst;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final midY = size.height / 2;
    final x = size.width - 8;
    canvas.drawLine(
      Offset(x, isFirst ? midY : 0),
      Offset(x, size.height),
      paint,
    );
    canvas.drawLine(Offset(x, midY), Offset(size.width - 2, midY), paint);
    canvas.drawCircle(
      Offset(size.width - 1.5, midY),
      2.2,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_ConnectorPainter old) =>
      old.color != color || old.isFirst != isFirst;
}

class ServiceTile extends StatelessWidget {
  const ServiceTile(
    this.service, {
    super.key,
    this.onPressed,
    this.trailing,
    this.muted = false,
  });

  final Service service;
  final VoidCallback? onPressed;
  final Widget? trailing;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final name = service.name.isEmpty ? service.address : service.name;
    return TapFeedback(
      onTap: onPressed ?? () {},
      child: ListRow(
        leading: ServiceAvatar(service, muted: muted),
        title: Semantics(
          label: AppLocalizations.of(context)
              .serviceSemantics(name, service.node, service.port),
          excludeSemantics: true,
          child: Text(name, style: context.listTitleStyle),
        ),
        subtitle: ExcludeSemantics(
          child: Text(service.address, style: context.listCaptionStyle),
        ),
        trailing:
            trailing ??
            GlyphIcon(
              Glyphs.more,
              size: 18,
              color: scheme.onSurfaceVariant.opacity50,
            ),
      ),
    );
  }
}

class ActionPill extends StatelessWidget {
  const ActionPill({
    super.key,
    required this.label,
    required this.glyph,
    this.selected = false,
    this.onPressed,
    this.loading = false,
  });

  final String label;
  final Glyph glyph;
  final bool selected;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final fg = selected ? scheme.onPrimary : scheme.onSurface;
    return TapFeedback(
      onTap: loading ? null : onPressed,
      squish: true,
      shape: AppShape.full,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: ShapeDecoration(
          color: selected ? scheme.primary : scheme.surfaceContainerHigh,
          shape: AppShape.full,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 15,
              child: loading
                  ? LoadingIndicator(size: 15, color: fg)
                  : GlyphIcon(glyph, size: 15, color: fg),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTextStyle.footnote
                  .of(context, emphasized: selected)
                  .copyWith(color: fg),
            ),
          ],
        ),
      ),
    );
  }
}
