/// One libghostty-vt emulator plus the change notifications its painter wants.
///
/// The SSH store owns it, not the page: switching between sessions or leaving
/// the terminal keeps the grid, its scrollback and a program on the alternate
/// screen (vim, htop) exactly as the remote left it.
library;

import 'package:flutter/foundation.dart';

import 'native/term.dart';

class TerminalSession extends ChangeNotifier {
  TerminalSession(this.term) : _snapshot = term.snapshot();

  final NativeTerm term;
  TermSnapshot _snapshot;
  TermSnapshot get snapshot => _snapshot;

  /// Called after the emulator grid changed, so an SSH session can follow.
  void Function(int cols, int rows)? onResize;

  /// Feeds remote output; returns the bytes the remote should get back.
  Uint8List? feed(Uint8List bytes) {
    final reply = term.write(bytes);
    _refresh();
    return reply;
  }

  void scroll(int delta) {
    term.scroll(delta);
    _refresh();
  }

  void resize(int cols, int rows, int cellWidth, int cellHeight) {
    if (cols == term.cols && rows == term.rows) return;
    term.resize(cols, rows, cellWidth, cellHeight);
    onResize?.call(cols, rows);
    _refresh();
  }

  String? get title => term.title();

  /// Re-reads the grid, e.g. after the selection changed.
  void refresh() => _refresh();

  void _refresh() {
    _snapshot = term.snapshot();
    notifyListeners();
  }

  @override
  void dispose() {
    term.dispose();
    super.dispose();
  }
}
