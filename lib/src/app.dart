import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import 'backend.dart';
import 'l10n.dart';
import 'services.dart';
import 'shell.dart';
import 'theme.dart';

class TaildeckApp extends StatefulWidget {
  const TaildeckApp({super.key});

  @override
  State<TaildeckApp> createState() => _TaildeckAppState();
}

class _TaildeckAppState extends State<TaildeckApp> {
  final theme = TaildeckTheme();
  final backend = TaildeckBackend();
  final services = ServiceStore.open();

  @override
  void initState() {
    super.initState();
    unawaited(backend.init());
    unawaited(services.load());
  }

  @override
  void dispose() {
    backend.dispose();
    services.dispose();
    theme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: theme,
      builder: (context, _) => PrismApp(
        title: 'Taildeck',
        theme: theme.light,
        darkTheme: theme.dark,
        themeMode: theme.mode,
        liquidGlass: LiquidGlassQuality.ultra,
        locale: theme.locale,
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: const [Locale('en'), Locale('zh')],
        builder: (context, child) {
          final size = MediaQuery.sizeOf(context);
          return ViewScope(
            size: size,
            isMobile: size.width < 720,
            child: child!,
          );
        },
        home: BackendScope(
          backend: backend,
          child: ServicesScope(
            store: services,
            child: TaildeckShell(theme: theme),
          ),
        ),
      ),
    );
  }
}
