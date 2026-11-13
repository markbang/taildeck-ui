import 'dart:async';

import 'package:flutter/widgets.dart';

/// A live region for status a sighted user sees change: the last message is
/// kept as the label, a burst of changes collapses into the settled one, and
/// repeats stay quiet for [gap] so a poll cannot flood a screen reader.
class LiveRegion extends StatefulWidget {
  const LiveRegion({
    super.key,
    required this.message,
    this.settle = const Duration(milliseconds: 400),
    this.gap = const Duration(seconds: 2),
  });

  final String message;
  final Duration settle;
  final Duration gap;

  @override
  State<LiveRegion> createState() => _LiveRegionState();
}

class _LiveRegionState extends State<LiveRegion> {
  String _announced = '';
  String _pending = '';
  DateTime? _last;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _announced = _pending = widget.message;
  }

  @override
  void didUpdateWidget(covariant LiveRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.message == oldWidget.message) return;
    _pending = widget.message;
    _timer?.cancel();
    _timer = Timer(widget.settle, _publish);
  }

  void _publish() {
    if (_pending.isEmpty || _pending == _announced) return;
    final now = DateTime.now();
    final last = _last;
    if (last != null && now.difference(last) < widget.gap) {
      _timer = Timer(widget.gap - now.difference(last), _publish);
      return;
    }
    _last = now;
    setState(() => _announced = _pending);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: _announced,
      child: const SizedBox.shrink(),
    );
  }
}
