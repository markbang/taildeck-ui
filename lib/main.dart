import 'package:flutter/widgets.dart';

import 'src/app.dart';
import 'src/app_info.dart';
import 'src/diagnostics.dart';
import 'src/preview_env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installErrorHandlers();
  await readLaunchQuery();
  await AppInfo.load();
  runApp(const TaildeckApp());
}
