import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:prism_ui/prism_ui.dart';

import '../backend.dart';
import '../favicons.dart';
import '../services.dart';

/// The rounded square in front of a service row: the name's initial while the
/// icon loads, then the icon itself. A failed fetch keeps the initial, so the
/// row never changes shape or flashes.
class ServiceAvatar extends StatefulWidget {
  const ServiceAvatar(
    this.service, {
    super.key,
    this.muted = false,
    this.size = 38,
  });

  final Service service;
  final bool muted;
  final double size;

  @override
  State<ServiceAvatar> createState() => _ServiceAvatarState();
}

class _ServiceAvatarState extends State<ServiceAvatar> {
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;
    // Icons are opt-out: with the toggle off nothing is fetched or read.
    if (!BackendScope.of(context).serviceIcons) return;
    _requested = true;
    FaviconsScope.of(context).ensure(widget.service);
  }

  @override
  Widget build(BuildContext context) {
    final entry = FaviconsScope.of(context).entryFor(widget.service);
    final image = entry.image;
    final factor = widget.size / 38;
    final placeholder = _initial(context, factor);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedSwitcher(
          duration: context.motionDuration(const Duration(milliseconds: 180)),
          child: image == null
              ? placeholder
              : KeyedSubtree(
                  key: ValueKey('${image.url}-${image.bytes.length}'),
                  child: _FaviconImage(
                    image: image,
                    size: widget.size,
                    padding: 4 * factor,
                    fallback: placeholder,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _initial(BuildContext context, double factor) {
    final service = widget.service;
    final name = service.name.isEmpty ? service.address : service.name;
    return Container(
      key: const ValueKey('placeholder'),
      width: widget.size,
      height: widget.size,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: service.tint.withValues(alpha: widget.muted ? 0.08 : 0.16),
        shape: AppShape.all(10 * factor),
      ),
      child: Text(
        name.characters.first.toUpperCase(),
        style: AppTextStyle.headline
            .of(context, emphasized: true)
            .copyWith(color: service.tint, fontSize: 15 * factor),
      ),
    );
  }
}

class _FaviconImage extends StatelessWidget {
  const _FaviconImage({
    required this.image,
    required this.size,
    required this.padding,
    required this.fallback,
  });

  final FaviconImage image;
  final double size;
  final double padding;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final inner = size - padding * 2;
    // Transparent favicons (and padded ones) read best on a plain surface.
    final background = Container(
      decoration: ShapeDecoration(
        color: context.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.32,
        ),
        shape: AppShape.all(size * 0.26),
      ),
    );
    if (image.vector) {
      return Stack(
        fit: StackFit.expand,
        children: [
          background,
          Padding(
            padding: EdgeInsets.all(padding),
            child: SvgPicture.memory(
              image.bytes,
              width: inner,
              height: inner,
              fit: BoxFit.contain,
            ),
          ),
        ],
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        background,
        Padding(
          padding: EdgeInsets.all(padding),
          child: Image.memory(
            image.bytes,
            width: inner,
            height: inner,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => fallback,
          ),
        ),
      ],
    );
  }
}
