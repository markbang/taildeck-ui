import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../data.dart';
import '../l10n.dart';
import '../glyphs.dart';
import '../services.dart';

class PageBody extends StatelessWidget {
  const PageBody({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.leading,
    this.children,
    this.maxWidth = 720,
    this.padding,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? leading;
  final List<Widget>? children;
  final double maxWidth;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: ListView(
          padding: padding ??
              EdgeInsets.fromLTRB(
                20,
                context.contentTopPadding,
                20,
                40 + context.bottomInset,
              ),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 4)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.largeTitle.of(context, emphasized: true),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle!,
                            style: AppTextStyle.subheadline
                                .of(context)
                                .copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 16),
            ...?children,
          ],
        ),
      ),
    );
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows,
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
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: AppTextStyle.subheadline
                  .of(context)
                  .copyWith(color: context.colorScheme.onSurfaceVariant),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
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
        color: node.online
            ? node.tint
            : node.tint.withValues(alpha: 0.45),
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
  const StatusPill({super.key, required this.label, required this.tint});

  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: ShapeDecoration(
        color: tint.withValues(alpha: 0.16),
        shape: AppShape.full,
      ),
      child: Text(
        label,
        style: AppTextStyle.caption2
            .of(context, emphasized: true)
            .copyWith(color: tint),
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
      painter: _ConnectorPainter(color: Divider.colorOf(context), isFirst: isFirst),
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
    canvas.drawLine(Offset(x, isFirst ? midY : 0), Offset(x, size.height), paint);
    canvas.drawLine(Offset(x, midY), Offset(size.width - 2, midY), paint);
    canvas.drawCircle(Offset(size.width - 1.5, midY), 2.2, Paint()..color = color);
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
    return PressRegion(
      onTap: onPressed ?? () {},
      child: ListRow(
        leading: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: service.tint.withValues(alpha: muted ? 0.08 : 0.16),
            shape: AppShape.all(10),
          ),
          child: Text(
            name.characters.first.toUpperCase(),
            style: AppTextStyle.headline
                .of(context, emphasized: true)
                .copyWith(color: service.tint),
          ),
        ),
        title: Text(name, style: context.listTitleStyle),
        subtitle: Text(service.address, style: context.listCaptionStyle),
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
  });

  final String label;
  final Glyph glyph;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final fg = selected ? scheme.onPrimary : scheme.onSurface;
    return PressRegion(
      onTap: onPressed,
      shape: AppShape.full,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: ShapeDecoration(
          color: selected ? scheme.primary : scheme.surfaceContainerHigh,
          shape: AppShape.full,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlyphIcon(glyph, size: 15, color: fg),
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
