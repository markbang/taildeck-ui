import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import '../motion.dart';
import '../widgets/controls.dart';

/// A tool's output, laid out as Kotlin's `CommandOutput`: six lines until it
/// is tapped, then all of it, unwrapped and scrolling sideways inside its box.
///
/// The text is a plain [Text] under a [SelectionArea]: a [SelectableText] is
/// a text field, which needs a bounded width and asserts (grey ErrorWidget in
/// release) inside a horizontal scroll view.
class CommandOutput extends StatefulWidget {
  const CommandOutput({super.key, required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<CommandOutput> createState() => _CommandOutputState();
}

class _CommandOutputState extends State<CommandOutput> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final lines = widget.text.split('\n');
    final collapsed = lines.length > 6;
    final shown = _open || !collapsed
        ? widget.text
        : '${lines.take(6).join('\n')}\n…';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: AnimatedContentSize(
        // The tap sits inside the selection area so it wins a plain tap; a
        // long press still starts a selection, as Kotlin's SelectionContainer
        // inside a clickable Surface does.
        child: SelectionArea(
          child: TapFeedback(
            onTap: collapsed ? () => setState(() => _open = !_open) : null,
            shape: AppShape.all(AppCorner.sm),
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: scheme.surfaceContainer,
                shape: AppShape.all(AppCorner.sm),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(10),
                child: Text(shown, softWrap: false, style: widget.style),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
