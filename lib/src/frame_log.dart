import 'dart:async';
import 'dart:ui' show FrameTiming;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Logs the cold start's own frame cost so an on-device gate can tell a slow
/// app from a stalled compositor: build is the UI isolate's work, raster also
/// waits on the surface.
void logStartupFrames(
  Stopwatch sinceMain, {
  Duration window = const Duration(seconds: 8),
}) {
  final binding = WidgetsBinding.instance;
  FrameTiming? first;
  var count = 0;
  var build = Duration.zero;
  var raster = Duration.zero;
  void onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      first ??= t;
      count++;
      if (t.buildDuration > build) build = t.buildDuration;
      if (t.rasterDuration > raster) raster = t.rasterDuration;
    }
  }

  binding.addTimingsCallback(onTimings);
  Timer(window - sinceMain.elapsed, () {
    binding.removeTimingsCallback(onTimings);
    final t = first;
    debugPrint(
      'taildeck frames: $count in ${window.inSeconds} s, '
      '${t == null ? '' : 'first build ${t.buildDuration.inMilliseconds} ms '
                'raster ${t.rasterDuration.inMilliseconds} ms, '}'
      'worst build ${build.inMilliseconds} ms, '
      'worst raster ${raster.inMilliseconds} ms',
    );
  });
  binding.waitUntilFirstFrameRasterized.then((_) {
    debugPrint(
      'taildeck first frame: ${sinceMain.elapsedMilliseconds} ms after main',
    );
  });
}
