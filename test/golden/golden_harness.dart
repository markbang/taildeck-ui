import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:taildeck_ui/src/l10n.dart';
import 'package:taildeck_ui/src/theme.dart';

/// The reference phone the emulator and the goldens both draw: 414 x 896.
const phoneSize = Size(414, 896);

const statusBar = 47.0;
const gestureBar = 34.0;

/// Real text metrics, so a golden changes only when the UI does.
Future<void> loadGoldenFonts() async {
  Future<void> load(String family, List<String> assets) async {
    final loader = FontLoader(family);
    for (final asset in assets) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }

  await load('Roboto', const [
    'assets/fonts/Roboto-Regular.ttf',
    'assets/fonts/Roboto-Medium.ttf',
    'assets/fonts/Roboto-Bold.ttf',
  ]);
  await load('NotoSansCJK', const ['assets/fonts/NotoSansCJK-subset.otf']);
  await load('DejaVuSansMono', const [
    'assets/fonts/DejaVuSansMono.ttf',
    'assets/fonts/DejaVuSansMono-Bold.ttf',
  ]);
}

/// Goldens compare at the pixel level, ignoring a one-step antialias wobble
/// (max channel delta 2) that the same frame can draw differently run to run.
void useGoldenComparator() {
  final base = goldenFileComparator;
  if (base is LocalFileComparator) {
    goldenFileComparator = TolerantComparator(
      base.basedir.resolve('golden.dart'),
    );
  }
}

class TolerantComparator extends LocalFileComparator {
  TolerantComparator(super.testFile);

  static const _maxDelta = 2;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final master = await getGoldenBytes(golden);
    final (width, height, test) = await _rgba(imageBytes);
    final (masterWidth, masterHeight, expected) = await _rgba(
      Uint8List.fromList(master),
    );
    if (width != masterWidth || height != masterHeight) {
      return super.compare(imageBytes, golden);
    }
    for (var i = 0; i < test.length; i += 4) {
      for (var channel = 0; channel < 4; channel++) {
        if ((test[i + channel] - expected[i + channel]).abs() > _maxDelta) {
          return super.compare(imageBytes, golden);
        }
      }
    }
    return true;
  }

  Future<(int, int, Uint8List)> _rgba(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    final width = frame.image.width;
    final height = frame.image.height;
    frame.image.dispose();
    codec.dispose();
    return (width, height, data!.buffer.asUint8List());
  }
}

/// A phone view at 1x with the status bar and gesture area the emulator has.
void usePhone(WidgetTester tester, {Size size = phoneSize}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(
    top: statusBar,
    bottom: gestureBar,
  );
  addTearDown(tester.view.reset);
}

/// The app's own theme, language and fonts. Glass stays off: its shader needs
/// a GPU the test host has not, and the goldens judge layout and motion.
Widget goldenApp({required Widget home}) {
  final theme = TaildeckTheme();
  return PrismApp(
    title: 'Taildeck',
    theme: theme.light,
    darkTheme: theme.dark,
    themeMode: ThemeMode.dark,
    locale: const Locale('en'),
    localizationsDelegates: const [AppLocalizations.delegate],
    supportedLocales: const [Locale('en'), Locale('zh')],
    debugShowCheckedModeBanner: false,
    home: home,
  );
}

/// Pump [duration] frame by frame, as a 60 Hz phone would draw it.
Future<void> pumpFrames(
  WidgetTester tester,
  Duration duration, {
  Duration step = const Duration(milliseconds: 16),
}) async {
  var left = duration;
  while (left > Duration.zero) {
    final next = left < step ? left : step;
    await tester.pump(next);
    left -= next;
  }
}
