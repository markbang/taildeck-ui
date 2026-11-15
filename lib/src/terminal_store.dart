import 'dart:async';

import 'package:flutter/foundation.dart';

import 'data.dart';
import 'native/bridge.dart';
import 'native/ssh.dart';
import 'native/term.dart';
import 'ssh_identities.dart';
import 'term_session.dart';
import 'terminal_appearance.dart';

/// What dialing a session again needs, kept in memory only: a reconnect after
/// a drop never asks for the password twice, and nothing is written to disk.
@immutable
class SshCredentials {
  const SshCredentials({
    required this.user,
    required this.port,
    this.password = '',
    this.identityId = builtinKeyId,
  });

  final String user;
  final int port;
  final String password;
  final String identityId;
}

/// One SSH session that outlives the terminal page.
///
/// It owns the emulator too, so switching to another session, leaving the
/// page or opening vim keeps the grid exactly as the remote left it; the
/// scrollback is the emulator's own cap rather than a byte buffer.
class SshTerminal extends ChangeNotifier {
  SshTerminal({
    required this.node,
    required this.credentials,
    required this.session,
    TerminalPalette palette = defaultTerminalPalette,
  }) : view = _openView(palette) {
    session?.output.listen(_onFrame);
    final remote = session;
    view?.onResize = (cols, rows) => remote?.resize(cols, rows);
  }

  final NodeItem node;
  final SshCredentials credentials;

  /// Null on the preview/mock path, where there is no remote shell to keep.
  final SshSession? session;

  /// The libghostty-vt emulator; null on Web or without the shared library.
  final TerminalSession? view;

  final _live = StreamController<SshOutput>.broadcast();
  bool _closed = false;
  bool _received = false;
  bool _disposed = false;
  String closeReason = '';

  static TerminalSession? _openView(TerminalPalette palette) {
    final term = createNativeTerm(
      cols: 80,
      rows: 24,
      scrollback: 5000,
      fg: palette.foregroundArgb,
      bg: palette.backgroundArgb,
      cursor: palette.cursorArgb,
    );
    return term == null ? null : TerminalSession(term);
  }

  String get user => credentials.user;
  int get port => credentials.port;

  bool get live => session != null;
  bool get closed => _closed;

  /// Any output arrived, so the page can tell connecting from connected.
  bool get received => _received;

  /// One target, one entry: what the tab strip and reconnect compare.
  String get id => node.name;

  /// Frames from now on; the grid is already up to date either way.
  Stream<SshOutput> get frames => _live.stream;

  void resize(int cols, int rows) => session?.resize(cols, rows);

  void write(Uint8List data) => session?.write(data);

  void _onFrame(SshOutput frame) {
    if (frame.closed) {
      _closed = true;
      closeReason = frame.reason;
      notifyListeners();
    } else {
      final bytes = frame.bytes;
      if (bytes != null && bytes.isNotEmpty) {
        _received = true;
        // Feed the grid even with no page attached: this is what lets a
        // session keep its vim screen and scrollback between visits.
        final reply = view?.feed(bytes);
        if (reply != null && reply.isNotEmpty) session?.write(reply);
      }
    }
    if (!_live.isClosed) _live.add(frame);
  }

  /// Ends the remote shell for good; only an explicit disconnect calls this.
  void close() {
    if (_closed) return;
    _closed = true;
    session?.close();
    view?.dispose();
    if (!_live.isClosed) _live.close();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    close();
    _live.close();
    super.dispose();
  }
}

/// The app's live SSH sessions, one per node, kept across terminal page closes.
class TerminalStore extends ChangeNotifier {
  final _sessions = <String, SshTerminal>{};

  Iterable<SshTerminal> get all => _sessions.values;

  bool get isEmpty => _sessions.isEmpty;

  SshTerminal? forNode(String name) => _sessions[name];

  /// Starts a session for [node] (or the mock one when [session] is null) and
  /// ends any earlier one on that node.
  SshTerminal open({
    required NodeItem node,
    required SshCredentials credentials,
    SshSession? session,
    TerminalPalette palette = defaultTerminalPalette,
  }) {
    final previous = _sessions.remove(node.name);
    if (previous != null) {
      previous.removeListener(notifyListeners);
      previous.dispose();
    }
    final terminal = SshTerminal(
      node: node,
      credentials: credentials,
      session: session,
      palette: palette,
    )..addListener(notifyListeners);
    _sessions[node.name] = terminal;
    notifyListeners();
    return terminal;
  }

  /// Ends the session and forgets it, so the node shows no resume row.
  void disconnect(SshTerminal terminal) {
    final known = _sessions[terminal.node.name];
    if (known == terminal) _sessions.remove(terminal.node.name);
    terminal
      ..removeListener(notifyListeners)
      ..dispose();
    notifyListeners();
  }

  /// Ends every session, for sign-out or when the user turns background
  /// keep-alive off and the app goes away.
  void closeAll() {
    if (_sessions.isEmpty) return;
    final sessions = _sessions.values.toList();
    _sessions.clear();
    for (final terminal in sessions) {
      terminal
        ..removeListener(notifyListeners)
        ..dispose();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    for (final terminal in _sessions.values.toList()) {
      terminal
        ..removeListener(notifyListeners)
        ..dispose();
    }
    _sessions.clear();
    super.dispose();
  }
}
