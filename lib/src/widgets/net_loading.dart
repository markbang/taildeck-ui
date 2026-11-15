import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import '../a11y.dart';
import 'loading.dart';

/// The page is waiting on the tailnet node: the reason with an indicator,
/// then placeholder rows instead of an empty list or a premature error.
class NetLoading extends StatelessWidget {
  const NetLoading({
    super.key,
    required this.title,
    this.caption,
    this.rows = 3,
  });

  final String title;
  final String? caption;

  /// Placeholder rows under the card; 0 leaves the page to its own content.
  final int rows;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          radius: AppCorner.xl,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              LoadingIndicator(size: 22, semanticLabel: title),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyle.body.of(context, emphasized: true),
                    ),
                    if (caption case final caption?) ...[
                      const SizedBox(height: 3),
                      Text(
                        caption,
                        style: AppTextStyle.footnote
                            .of(context)
                            .copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (rows > 0) ...[
          const SizedBox(height: 18),
          Card(
            radius: AppCorner.xl,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              children: [
                for (var i = 0; i < rows; i++) ...[
                  if (i > 0) const SizedBox(height: 18),
                  Row(
                    children: [
                      const SkeletonPill(width: 34, height: 34),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonText(
                            width: 130 + i * 18,
                            style: AppTextStyle.body.of(context),
                          ),
                          const SizedBox(height: 6),
                          SkeletonText(
                            width: 180 + i * 12,
                            style: AppTextStyle.caption1.of(context),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
        LiveRegion(message: title),
      ],
    );
  }
}
