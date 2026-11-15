import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taildeck_ui/src/backend.dart';
import 'package:taildeck_ui/src/native/bridge.dart';
import 'package:taildeck_ui/src/native/storage.dart';
import 'package:taildeck_ui/src/splash.dart';

String _state(Map<String, String> values) => jsonEncode({
  for (final entry in values.entries)
    entry.key: base64Encode(utf8.encode(entry.value)),
});

class _FakeBridge implements NativeBridge {
  final _events = StreamController<BridgeEvent>.broadcast();
  int starts = 0;
  String reply = 'Starting';

  @override
  Stream<BridgeEvent> get events => _events.stream;

  @override
  Future<Map<String, dynamic>> start({
    required String dir,
    String hostname = 'taildeck',
    String controlURL = '',
    String authKey = '',
    int gatewayPort = 0,
    String platform = 'go',
  }) async {
    starts++;
    return {'gatewayPort': 19000};
  }

  @override
  Future<Map<String, dynamic>> status() async => {'state': reply};

  @override
  Future<void> stop() async {}

  @override
  Future<void> logout() async {}

  @override
  Future<void> herdrClose() async {}

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Storage implements BackendStorage {
  _Storage(this.config, {this.savedLogin = false});

  StoredConfig config;
  bool savedLogin;

  @override
  Future<bool> hasSavedLogin() async => savedLogin;

  @override
  Future<StoredConfig> readConfig() async => config;

  @override
  Future<void> writeConfig(StoredConfig value) async => config = value;

  @override
  Future<String> stateDir() async => '/tmp/taildeck-test';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('savedLoginInState', () {
    test('the current profile with a node id is a login record', () {
      expect(
        savedLoginInState(
          _state({
            '_current-profile': 'profile-abc',
            '_profiles':
                '{"abc":{"ID":"abc","Key":"profile-abc","NodeID":"n123"}}',
          }),
        ),
        isTrue,
      );
      expect(
        savedLoginInState(
          _state({
            '_current-profile': 'profile-abc',
            '_profiles': '{"abc":{"Key":"profile-abc","NodeID":""}}',
          }),
        ),
        isFalse,
      );
    });

    test('an accepted node key is a login record', () {
      expect(
        savedLoginInState(
          _state({
            '_current-profile': 'profile-abc',
            'profile-abc': '{"Persist":{"NodeID":"n123"}}',
          }),
        ),
        isTrue,
      );
    });

    test('a key without a node id is not signed in', () {
      expect(
        savedLoginInState(
          _state({
            '_current-profile': 'profile-abc',
            'profile-abc': '{"Persist":{"NodeID":""}}',
          }),
        ),
        isFalse,
      );
      expect(savedLoginInState(_state({'_current-profile': 'profile-abc'})), isFalse);
      expect(savedLoginInState('{}'), isFalse);
      expect(savedLoginInState('not json'), isFalse);
    });

    test('a plain JSON value is read too', () {
      expect(
        savedLoginInState(
          jsonEncode({
            'profile-abc': jsonEncode({
              'Persist': {'NodeID': 'n1'},
            }),
          }),
        ),
        isTrue,
      );
    });
  });

  group('launch route', () {
    TaildeckBackend backend(_Storage storage, _FakeBridge bridge) =>
        TaildeckBackend(bridge: bridge, storage: storage);

    test('a saved login opens the shell while the node starts', () async {
      final bridge = _FakeBridge();
      final subject = backend(_Storage(const StoredConfig(signedIn: true)), bridge);
      expect(subject.sessionKnown, isFalse);

      await subject.init();
      expect(subject.sessionKnown, isTrue);
      expect(subject.state, BackendState.starting);
      expect(subject.hasPersistedLogin, isTrue);
      expect(subject.showShell, isTrue);
      await subject.sessionReady;
      subject.dispose();
    });

    test('a tsnet profile alone is a saved login', () async {
      final bridge = _FakeBridge();
      final subject = backend(_Storage(const StoredConfig(), savedLogin: true), bridge);

      await subject.init();
      expect(subject.showShell, isTrue);
      expect(bridge.starts, 1);
      subject.dispose();
    });

    test('no record means the login page and no node start', () async {
      final bridge = _FakeBridge();
      final subject = backend(_Storage(const StoredConfig()), bridge);

      await subject.init();
      expect(subject.sessionKnown, isTrue);
      expect(subject.showShell, isFalse);
      expect(bridge.starts, 0);
      subject.dispose();
    });

    test('NeedsLogin returns a saved login to the login page', () async {
      final bridge = _FakeBridge();
      final subject = backend(_Storage(const StoredConfig(signedIn: true)), bridge);
      await subject.init();
      bridge.reply = 'NeedsLogin';

      bridge._events.add(
        const BridgeEvent(BridgeEventKind.state, {'state': 'NeedsLogin'}),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(subject.needsLogin, isTrue);
      expect(subject.showShell, isFalse);
      subject.dispose();
    });

    test('signing out drops the route to the login page', () async {
      final bridge = _FakeBridge();
      final subject = backend(_Storage(const StoredConfig(signedIn: true)), bridge);
      await subject.init();

      await subject.signOut();
      expect(subject.showShell, isFalse);
      subject.dispose();
    });
  });

  group('SplashGate', () {
    Widget app(Future<void>? until) => Directionality(
      textDirection: TextDirection.ltr,
      child: SplashGate(until: until, child: const Text('home')),
    );

    testWidgets('stays while the route is unknown, then hands over', (
      tester,
    ) async {
      final ready = Completer<void>();
      await tester.pumpWidget(app(ready.future));
      await tester.pump();
      expect(find.byType(SplashMark), findsOneWidget);
      expect(find.text('home'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.byType(SplashMark), findsOneWidget);

      ready.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(SplashMark), findsNothing);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('gives up after 1.5 s and reveals the app', (tester) async {
      await tester.pumpWidget(app(Completer<void>().future));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1400));
      expect(find.byType(SplashMark), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(SplashMark), findsNothing);
      expect(find.text('home'), findsOneWidget);
    });
  });
}
