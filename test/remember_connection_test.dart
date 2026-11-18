import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:taildeck_ui/src/backend.dart';
import 'package:taildeck_ui/src/connection_memory.dart';
import 'package:taildeck_ui/src/data.dart';
import 'package:taildeck_ui/src/favicons.dart';
import 'package:taildeck_ui/src/l10n.dart';
import 'package:taildeck_ui/src/native/bridge.dart';
import 'package:taildeck_ui/src/native/storage.dart';
import 'package:taildeck_ui/src/services.dart';
import 'package:taildeck_ui/src/shell.dart';
import 'package:taildeck_ui/src/theme.dart';

import 'golden/fake_backend.dart';

class _Bridge extends FakeBridge {
  _Bridge() {
    statusReply = {
      ...FakeBridge.readyStatus,
      'peers': [
        for (final (id, name, ip) in [
          ('nBangwu', 'bangwu', '100.64.0.2'),
          ('nMotion', 'motionpeer', '100.64.0.3'),
        ])
          {
            'id': id,
            'name': name,
            'ips': [ip],
            'online': true,
            'os': 'linux',
            'user': 'bangwu@github',
          },
      ],
    };
  }

  final dials = <({String host, String user, int port, String password})>[];
  String dialError = '';

  @override
  Future<Map<String, dynamic>> sshDial({
    required String host,
    int port = 22,
    String user = 'root',
    String password = '',
    String keyPath = '',
    String passphrase = '',
    String certPath = '',
    int cols = 80,
    int rows = 24,
  }) async {
    dials.add((host: host, user: user, port: port, password: password));
    if (dialError.isNotEmpty) throw BridgeException(dialError);
    return {'id': dials.length};
  }
}

const _bangwu = NodeItem(
  name: 'bangwu',
  id: 'nBangwu',
  ip: '100.64.0.2',
  os: 'Linux',
  online: true,
);

const _tailscale = SavedConnection(
  user: 'bangwu',
  port: 22,
  auth: SshAuth.tailscale,
);

Future<TaildeckBackend> _backend(_Bridge bridge, MemoryStorage storage) async {
  final backend = TaildeckBackend(bridge: bridge, storage: storage);
  await backend.init();
  return backend;
}

Future<void> _pumpShell(WidgetTester tester, TaildeckBackend backend) async {
  tester.view.physicalSize = const Size(414, 896);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final theme = TaildeckTheme();
  final services = ServiceStore.open();
  final favicons = FaviconsController(fetch: (_) async => null);
  await tester.pumpWidget(
    PrismApp(
      theme: theme.light,
      darkTheme: theme.dark,
      themeMode: theme.mode,
      locale: const Locale('en'),
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: const [Locale('en'), Locale('zh')],
      builder: (context, child) => ViewScope(
        size: const Size(414, 896),
        isMobile: true,
        child: BackendScope(
          backend: backend,
          child: ServicesScope(
            store: services,
            child: FaviconsScope(controller: favicons, child: child!),
          ),
        ),
      ),
      home: TaildeckShell(theme: theme),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _row(String name) => find.text(name).last;

void main() {
  group('stored config', () {
    test('old sshUsers/sshPorts become prefill-only device entries', () {
      final config = StoredConfig.fromJson({
        'sshUsers': {'bangwu': 'mark', 'bangwu/svc': 'svc'},
        'sshPorts': {'bangwu': 2222},
      });
      final saved = config.connections['bangwu']!;
      expect(saved.user, 'mark');
      expect(saved.port, 2222);
      expect(saved.auth, isNull);
      expect(planTap(saved), TapPlan.menu);
      expect(config.connections.containsKey('bangwu/svc'), isFalse);
      expect(config.sshUsers['bangwu/svc'], 'svc');

      final again = StoredConfig.fromJson(config.toJson());
      expect(again.connections.keys, ['bangwu']);
    });

    test('a saved entry round-trips without a password', () {
      const saved = SavedConnection(
        user: 'root',
        port: 2200,
        auth: SshAuth.key,
        identityId: 'work',
      );
      final json = const StoredConfig(connections: {'n1': saved}).toJson();
      expect(json.toString(), isNot(contains('password')));
      final back = StoredConfig.fromJson(json).connections['n1']!;
      expect(
        (back.user, back.port, back.auth, back.dialIdentity),
        ('root', 2200, SshAuth.key, 'work'),
      );
    });

    test('a password login reopens the sheet, others dial', () {
      expect(planTap(null), TapPlan.menu);
      expect(planTap(_tailscale), TapPlan.dial);
      expect(
        planTap(const SavedConnection(user: 'a', auth: SshAuth.password)),
        TapPlan.sheet,
      );
      expect(
        planTap(const SavedConnection(action: ConnectionAction.ping)),
        TapPlan.ping,
      );
    });
  });

  group('backend memory', () {
    test('two devices keep their own, keyed by stable id', () async {
      final storage = MemoryStorage()
        ..config = StoredConfig.fromJson({
          'sshUsers': {'bangwu': 'old'},
          'sshPorts': {'bangwu': 2022},
        });
      final backend = await _backend(_Bridge(), storage);
      expect(backend.connectionFor(_bangwu)?.user, 'old');

      await backend.rememberConnection(_bangwu, _tailscale);
      const motion = NodeItem(
        name: 'motionpeer',
        id: 'nMotion',
        ip: '100.64.0.3',
        os: 'Linux',
        online: true,
      );
      await backend.rememberConnection(
        motion,
        const SavedConnection(user: 'root', port: 2200, auth: SshAuth.key),
      );

      expect(storage.config.connections.keys, ['nBangwu', 'nMotion']);
      final reread = await _backend(_Bridge(), storage);
      expect(reread.connectionFor(_bangwu)?.auth, SshAuth.tailscale);
      expect(reread.connectionFor(motion)?.port, 2200);

      final cleared = await _backend(_Bridge(), MemoryStorage());
      expect(planTap(cleared.connectionFor(_bangwu)), TapPlan.menu);
      backend.dispose();
      reread.dispose();
      cleared.dispose();
    });
  });

  group('tap flow', () {
    testWidgets('first connect saves, second tap dials without the sheet', (
      tester,
    ) async {
      final bridge = _Bridge();
      final storage = MemoryStorage()
        ..config = const StoredConfig(signedIn: true);
      final backend = await tester.runAsync(() => _backend(bridge, storage));
      await _pumpShell(tester, backend!);

      await tester.tap(_row('bangwu'));
      await tester.pumpAndSettle();
      expect(find.text('Scan common ports'), findsOneWidget);
      await tester.tap(find.text('SSH').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(bridge.dials, hasLength(1));
      expect(storage.config.connections['nBangwu']?.auth, SshAuth.tailscale);

      // A fresh launch on the same config: the tap goes straight in.
      final relaunched = await tester.runAsync(
        () => _backend(bridge, storage),
      );
      await tester.pumpWidget(const SizedBox());
      await _pumpShell(tester, relaunched!);
      expect(find.text('SSH · bangwu · Tailscale SSH'), findsOneWidget);
      await tester.tap(_row('bangwu'));
      await tester.pumpAndSettle();
      expect(bridge.dials, hasLength(2));
      expect(find.text('Connect'), findsNothing);
      backend.dispose();
      relaunched.dispose();
    });

    testWidgets('editing to key auth is used next time', (tester) async {
      final bridge = _Bridge();
      final storage = MemoryStorage()
        ..config = const StoredConfig(
          signedIn: true,
          connections: {'nBangwu': _tailscale},
        );
      final backend = await tester.runAsync(() => _backend(bridge, storage));
      await _pumpShell(tester, backend!);

      await tester.longPress(_row('bangwu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit connection'));
      await tester.pumpAndSettle();
      expect(find.text('Tailscale SSH'), findsOneWidget);
      await tester.tap(find.text('Tailscale SSH'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Key').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(storage.config.connections['nBangwu']?.auth, SshAuth.key);
      expect(bridge.dials, hasLength(1));

      final relaunched = await tester.runAsync(
        () => _backend(bridge, storage),
      );
      await tester.pumpWidget(const SizedBox());
      await _pumpShell(tester, relaunched!);
      expect(find.text('SSH · bangwu · Key'), findsOneWidget);
      await tester.tap(_row('bangwu'));
      await tester.pumpAndSettle();
      expect(bridge.dials, hasLength(2));
      expect(find.text('Connect'), findsNothing);
      backend.dispose();
      relaunched.dispose();
    });

    testWidgets('a failed saved connection opens the sheet with the reason', (
      tester,
    ) async {
      final bridge = _Bridge()
        ..dialError = 'ssh: unable to authenticate, attempted methods [none]';
      final storage = MemoryStorage()
        ..config = const StoredConfig(
          signedIn: true,
          connections: {
            'nBangwu': SavedConnection(
              user: 'deploy',
              port: 2200,
              auth: SshAuth.tailscale,
            ),
          },
        );
      final backend = await tester.runAsync(() => _backend(bridge, storage));
      await _pumpShell(tester, backend!);

      await tester.tap(_row('bangwu'));
      await tester.pumpAndSettle();
      expect(bridge.dials, hasLength(1));
      expect(find.text('Connect'), findsOneWidget);
      expect(
        find.text('The SSH login was refused; check the user, key or password.'),
        findsOneWidget,
      );
      expect(find.text('deploy'), findsWidgets);
      expect(find.text('2200'), findsOneWidget);
      expect(find.text('Tailscale SSH'), findsOneWidget);
      backend.dispose();
    });

    testWidgets('a saved password login opens the sheet on the password', (
      tester,
    ) async {
      final bridge = _Bridge();
      final storage = MemoryStorage()
        ..config = const StoredConfig(
          signedIn: true,
          connections: {
            'nBangwu': SavedConnection(user: 'mark', auth: SshAuth.password),
          },
        );
      final backend = await tester.runAsync(() => _backend(bridge, storage));
      await _pumpShell(tester, backend!);

      await tester.tap(_row('bangwu'));
      await tester.pumpAndSettle();
      expect(bridge.dials, isEmpty);
      final field = tester.widget<TextField>(find.byType(TextField).last);
      expect(field.obscureText, isTrue);
      expect(field.focusNode?.hasFocus ?? field.autofocus, isTrue);
      await tester.enterText(find.byType(TextField).last, 'secret');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(bridge.dials.single.password, 'secret');
      expect(storage.config.toJson().toString(), isNot(contains('secret')));
      backend.dispose();
    });
  });
}
