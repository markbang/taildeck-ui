import 'dart:async';

import 'package:flutter/foundation.dart';

import 'data.dart';
import 'native/bridge.dart';
import 'native/ssh.dart';

/// One SSH session that outlives the terminal page.
///
/// While no page is attached the frames keep arriving into a capped buffer, so
/// reopening the terminal replays the scrollback instead of dialing again.
class SshTerminal extends ChangeNotifier {
  SshTerminal({
    required this.node,
    required this.user,
    required this.port,
    required this.session,
  }) {
    session?.output.listen(_onFrame);
  }

  /// Older output is dropped from the front past this many bytes.
  static const bufferedLimit = 512 * 1024;

  final NodeItem node;
  final String user;
  final int port;

  /// Null on the preview/mock path, where there is no remote shell to keep.
  final SshSession? session;

  final StreamController<SshOutput> _live = StreamController.broadcast();
  final List<Uint8List> _chunks = [];
  int _buffered = 0;
  bool _closed = false;
  String closeReason = '';

  bool get live => session != null;
  bool get closed => _closed;

  /// Frames from now on; a page feeds [takeBuffered] first, then follows this.
  Stream<SshOutput> get frames => _live.stream;

  /// Output that arrived while no page was attached.
  Uint8List takeBuffered() {
    if (_chunks.isEmpty) return Uint8List(0);
    final all = Uint8List(_buffered);
    var offset = 0;
    for (final chunk in _chunks) {
      all.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    _chunks.clear();
    _buffered = 0;
    return all;
  }

  void write(Uint8List data) => session?.write(data);

  void resize(int cols, int rows) => session?.resize(cols, rows);

  void _onFrame(SshOutput frame) {
    final bytes = frame.bytes;
    if (!frame.notice && bytes != null) _buffer(bytes);
    if (frame.closed) {
      _closed = true;
      closeReason = frame.reason;
      notifyListeners();
    }
    if (!_live.isClosed) _live.add(frame);
  }

  void _buffer(Uint8List bytes) {
    if (bytes.isEmpty) return;
    _chunks.add(bytes);
    _buffered += bytes.length;
    while (_buffered > bufferedLimit && _chunks.length > 1) {
      _buffered -= _chunks.removeAt(0).length;
    }
  }

  /// Ends the remote shell for good; only an explicit disconnect calls this.
  void close() {
    if (_closed) return;
    _closed = true;
    session?.close();
    if (!_live.isClosed) _live.close();
  }

  @override
  void dispose() {
    close();
    _live.close();
    super.dispose();
  }
}

/// The app's live SSH sessions, one per node, kept across terminal page closes.
class TerminalStore extends ChangeNotifier {
  final _sessions = <String, SshTerminal>{};

  Iterable<SshTerminal> get all => _sessions.values;

  SshTerminal? forNode(String name) => _sessions[name];

  /// Starts a session for [node] (or the mock one when [session] is null) and
  /// ends any earlier one on that node.
  SshTerminal open({
    required NodeItem node,
    required String user,
    required int port,
    SshSession? session,
  }) {
    final previous = _sessions.remove(node.name);
    if (previous != null) {
      previous.removeListener(notifyListeners);
      previous.dispose();
    }
    final terminal = SshTerminal(
      node: node,
      user: user,
      port: port,
      session: session,
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
