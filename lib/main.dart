import 'package:flutter/widgets.dart';

import 'src/app.dart';
import 'src/preview_env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await readLaunchQuery();
  runApp(const TaildeckApp());
}
