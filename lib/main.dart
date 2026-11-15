import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'src/app.dart';
import 'src/app_info.dart';
import 'src/diagnostics.dart';
import 'src/preview_env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installErrorHandlers();
  await readLaunchQuery();
  // `?slow=6` stretches every animation, so a recording can see each frame of
  // a transition; debug and profile builds only.
  final slow = double.tryParse(previewParam('slow') ?? '');
  if (!kReleaseMode && slow != null && slow > 0) timeDilation = slow;
  await AppInfo.load();
  runApp(const TaildeckApp());
}
