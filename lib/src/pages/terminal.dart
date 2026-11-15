import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../a11y.dart';
import '../backend.dart';
import '../glyphs.dart';
import '../data.dart';
import '../l10n.dart';
import '../motion.dart';
import '../native/bridge.dart';
import '../native/hardware_keyboard.dart';
import '../native/keys.dart';
import '../native/term.dart';
import '../native/term_demo.dart';
import '../preview_env.dart';
import '../term_session.dart';
import '../terminal_appearance.dart';
import '../terminal_gestures.dart';
import '../terminal_keys.dart';
import '../terminal_snippets.dart';
import '../terminal_store.dart';
import '../widgets/controls.dart';
import 'term_key_bar.dart';
import 'terminal_sessions.dart';
import 'term_view.dart';
import 'terminal_snippets_sheet.dart';

enum _Kind { command, output, muted, error, ok }

class _Line {
  const _Line(this.text, this.kind);

  final String text;
  final _Kind kind;
}

class TerminalPage extends StatefulWidget {
  const TerminalPage({
    super.key,
    required this.node,
    required this.onClose,
    required this.terminal,
    this.user = 'root',
    this.port = 22,
    this.demo = false,
    this.onDisconnect,
    this.onReconnect,
    this.onAgents,
    this.sessions = const [],
    this.onSwitch,
  });

  final NodeItem node;

  /// Leaving the page; the session keeps running in [terminal].
  final VoidCallback onClose;

  /// Ending the remote shell for good.
  final VoidCallback? onDisconnect;

  /// Dialing the node again after the session dropped.
  final VoidCallback? onReconnect;

  /// Opening the herdr agents for this node, when the link is up.
  final VoidCallback? onAgents;

  /// Every session that is still open, for the strip under the header.
  final List<SshTerminal> sessions;

  /// Switching to another session without dialing again.
  final ValueChanged<SshTerminal>? onSwitch;

  final String user;
  final int port;

  /// Owns the SSH session and its output; live unless the mock path opened it
  /// without a session.
  final SshTerminal terminal;

  /// `?ssh=demo`: feed a canned ANSI session through the emulator.
  final bool demo;

  bool get live => terminal.live;

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage>
    with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final List<_Line> _lines = [
    _Line('Linux devbox 6.8.0-45-generic x86_64', _Kind.output),
    _Line('Last login: Thu Nov 13 16:02:11 from 100.101.4.2', _Kind.muted),
    const _Line('uptime', _Kind.command),
    const _Line('16:47 up 12 days, 2 users, load 0.14 0.09 0.06', _Kind.output),
    const _Line('tailscale status', _Kind.command),
    const _Line('devbox    100.71.200.9   online', _Kind.output),
    const _Line('pixel-9   100.101.4.2    offline', _Kind.output),
    const _Line('nas       100.88.12.7    online', _Kind.output),
    const _Line('docker ps', _Kind.command),
    const _Line('grafana:11.3.0        Up 12 days', _Kind.output),
    const _Line('code-server:latest    Up 12 days', _Kind.output),
  ];

  /// The libghostty-vt emulator; the store owns the live one, so switching
  /// sessions or leaving the page keeps its grid and scrollback.
  TerminalSession? _session;
  bool _ownsSession = false;
  final _focus = FocusNode(debugLabel: 'terminal');
  StreamSubscription<SshOutput>? _output;
  String? _closedReason;
  bool _connected = false;
  bool _bannerFed = false;
  int _demoRows = 0;
  String _sent = '';
  final _mods = TerminalMods();

  /// Pinch size while the finger is down; the backend value lands after the
  /// debounce, then this falls back to it.
  double? _pinchFont;
  Timer? _fontSave;

  /// Android's `Configuration.keyboard`; null when the platform cannot say.
  bool? _physicalKeyboard;

  @override
  void initState() {
    super.initState();
    final terminal = widget.terminal;
    final shared = terminal.view;
    if (widget.demo) {
      // The demo feeds its own emulator, whatever the store holds.
      final term = createNativeTerm(cols: 80, rows: 24, scrollback: 5000);
      if (term != null) {
        _ownsSession = true;
        _session = TerminalSession(term)..addListener(_onSessionChanged);
        _session!.onResize = (cols, rows) {
          if (rows == _demoRows) return;
          _demoRows = rows;
          _session?.feed(demoSessionBytes(rows: rows));
        };
        _session!.feed(demoSessionBytes());
      }
    } else if (shared != null) {
      _session = shared..addListener(_onSessionChanged);
      _connected = terminal.received;
      _closedReason = terminal.closed ? terminal.closeReason : null;
    }
    // Hardware keys go through the emulator's encoder in the demo too, so a
    // keyboard can be tried without a tailnet.
    if (_session != null) _focus.onKeyEvent = _onKey;
    if (terminal.live) _output = terminal.frames.listen(_onOutput);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_readKeyboard());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A keyboard can be plugged in while the app is in the background.
    if (state == AppLifecycleState.resumed) unawaited(_readKeyboard());
  }

  @override
  void didChangeMetrics() {
    // ...or while the terminal is on screen.
    unawaited(_readKeyboard());
  }

  Future<void> _readKeyboard() async {
    final attached = await physicalKeyboardAttached();
    if (!mounted || attached == null || attached == _physicalKeyboard) return;
    setState(() => _physicalKeyboard = attached);
  }

  void _onOutput(SshOutput frame) {
    if (!mounted) return;
    final session = _session;
    if (frame.closed) {
      final l10n = AppLocalizations.of(context);
      final line = frame.reason.isEmpty
          ? l10n.disconnected
          : l10n.disconnectedReason(frame.reason);
      setState(() => _closedReason = frame.reason);
      session?.feed(_ansi('\r\n\x1b[31m$line\x1b[0m\r\n'));
      return;
    }
    // The store already fed the grid (it owns the emulator), so the page only
    // tracks status here; feeding again would double every byte.
    if (frame.bytes == null) return;
    if (!frame.notice && !_connected) setState(() => _connected = true);
  }

  static Uint8List _ansi(String text) => Uint8List.fromList(utf8.encode(text));

  /// Hardware keys reach the emulator's encoder; printable characters come
  /// through the text field below and are encoded there.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final session = _session;
    if (session == null) return KeyEventResult.ignored;
    if (event is KeyUpEvent) return KeyEventResult.handled;
    final mods = ghosttyModsOf(HardwareKeyboard.instance);
    final text = event.character;
    // Printable keys go through the text field, which encodes them. Esc, Tab
    // and Backspace also carry a control character, so they must not: their
    // shortcuts would pop the page or edit the keystroke buffer.
    final printable =
        text != null && text.isNotEmpty && text.codeUnitAt(0) >= 0x20;
    if (printable && mods & ~GhosttyMods.shift == 0) {
      return KeyEventResult.ignored;
    }
    final encoded = session.term.encodeKey(ghosttyKeyOf(event), mods);
    if (encoded != null) _deliver(encoded);
    return KeyEventResult.handled;
  }

  void _onTextChanged(String value) {
    final session = _session;
    if (session == null) return;
    // An IME preedit is not committed text: wait for the commit.
    if (_input.value.composing.isValid) return;
    final added = _sent.isEmpty
        ? value
        : (value.startsWith(_sent) ? value.substring(_sent.length) : value);
    _sent = value;
    final armed = _mods.mask;
    for (final (index, rune) in added.runes.indexed) {
      final text = String.fromCharCode(rune);
      // A sticky modifier applies to the next key only.
      final encoded = session.term.encodeKey(
        ghosttyKeyForText(text),
        index == 0 ? armed : 0,
        text: text,
      );
      if (encoded != null) _deliver(encoded);
    }
    if (armed != 0 && added.isNotEmpty && _mods.consume()) setState(() {});
    if (value.isEmpty) return;
    // The line is a keystroke buffer, not an input box: clear it once the
    // frames are out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _input.clear();
      _sent = '';
    });
  }

  void _sendLine(String text) {
    final terminal = widget.terminal;
    if (!terminal.live || _session == null) return;
    final session = _session!;
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      final encoded = session.term.encodeKey(
        ghosttyKeyForText(ch),
        0,
        text: ch,
      );
      if (encoded != null) terminal.write(encoded);
    }
    final enter = session.term.encodeKey(GhosttyKeys.enter, 0);
    if (enter != null) terminal.write(enter);
  }

  void _tapKey(TerminalKey key) {
    final mod = key.modifier;
    if (mod != null) {
      setState(() => _mods.tap(mod));
      _haptic();
      return;
    }
    final session = _session;
    final bytes = session == null
        ? null
        : encodeTerminalKey(session.term, key, _mods.mask);
    _deliver(bytes);
    if (_mods.consume()) setState(() {});
    _haptic();
    _focus.requestFocus();
  }

  /// An arrow from a swipe carries the sticky modifiers like a row key.
  void _onArrow(TerminalArrow arrow) {
    _sendKey(switch (arrow) {
      TerminalArrow.up => GhosttyKeys.arrowUp,
      TerminalArrow.down => GhosttyKeys.arrowDown,
      TerminalArrow.left => GhosttyKeys.arrowLeft,
      TerminalArrow.right => GhosttyKeys.arrowRight,
    });
  }

  void _sendKey(int code) {
    final session = _session;
    if (session == null) return;
    _deliver(session.term.encodeKey(code, _mods.mask));
    if (_mods.consume()) setState(() {});
    _haptic();
  }

  /// Pastes through the emulator's encoder, so a program that asked for
  /// bracketed paste gets its markers.
  Future<void> _paste() async {
    final session = _session;
    if (session == null) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    _deliver(session.term.encodePaste(Uint8List.fromList(utf8.encode(text))));
    _haptic();
  }

  /// A snippet is typed input: the payload goes out as bytes, Return
  /// included when the snippet asks for it.
  void _sendSnippet(TerminalSnippet snippet) {
    _haptic();
    if (!widget.live) {
      final session = _session;
      if (session == null) return;
      session.feed(Uint8List.fromList(utf8.encode(snippet.payload)));
      return;
    }
    widget.terminal.write(Uint8List.fromList(utf8.encode(snippet.payload)));
  }

  Future<void> _openSnippets() async {
    final backend = BackendScope.of(context);
    await showTerminalSnippetsSheet(
      context,
      backend: backend,
      onSend: _sendSnippet,
    );
  }

  /// Pinch zoom: the grid follows the finger, the config follows the release.
  void _zoomTo(double size) {
    final backend = BackendScope.of(context);
    final next = clampTerminalFont(size);
    if (next == (_pinchFont ?? backend.terminalFontSize)) return;
    setState(() => _pinchFont = next);
    _fontSave?.cancel();
    _fontSave = Timer(const Duration(milliseconds: 400), () {
      unawaited(backend.setTerminalFontSize(next));
      if (mounted) setState(() => _pinchFont = null);
    });
  }

  Future<bool> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// A tap on the grid or the input line brings the soft keyboard back, even
  /// when the field never lost focus.
  void _focusTerminal() {
    _focus.requestFocus();
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.show'));
  }

  void _haptic() {
    if (!BackendScope.of(context).terminalKeyHaptics) return;
    HapticFeedback.lightImpact();
  }

  /// Bytes go to the remote; the demo has none, so its emulator shows what a
  /// remote would have echoed back.
  void _deliver(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return;
    if (widget.live) {
      widget.terminal.write(bytes);
      return;
    }
    _session?.feed(_demoEcho(bytes));
  }

  static Uint8List _demoEcho(Uint8List bytes) {
    final text = StringBuffer();
    for (final byte in bytes) {
      if (byte == 0x7f) {
        text.write('^?');
      } else if (byte < 0x20) {
        text.write('^${String.fromCharCode(byte + 0x40)}');
      } else {
        text.write(String.fromCharCode(byte));
      }
    }
    return Uint8List.fromList(utf8.encode(text.toString()));
  }

  /// Keeps the header's grid size in step with the emulator.
  void _onSessionChanged() {
    // A bell in the session rings once: the native side clears the bit when
    // the snapshot is read.
    if (_session?.snapshot.meta[TermMeta.effects] case final effects?
        when effects & 1 != 0) {
      unawaited(HapticFeedback.selectionClick());
    }
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bannerFed || widget.demo || widget.live) return;
    _bannerFed = true;
    final session = _session;
    if (session == null) return;
    final text = AppLocalizations.of(context).sshPending;
    session.feed(Uint8List.fromList(utf8.encode('\x1b[2m$text\x1b[0m\r\n')));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fontSave?.cancel();
    // Detach only; the session stays up in the store and back reattaches.
    _output?.cancel();
    _focus.dispose();
    _session?.removeListener(_onSessionChanged);
    if (_ownsSession) _session?.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _run(String raw) {
    final command = raw.trim();
    if (command.isEmpty) return;
    if (widget.live) {
      _sendLine(command);
      return;
    }
    final session = _session;
    if (session != null) {
      // Demo echoes locally; there is no remote behind it.
      if (widget.demo) {
        session.feed(Uint8List.fromList(utf8.encode('$command\r\n')));
      }
      return;
    }
    if (command == 'clear') {
      setState(_lines.clear);
      return;
    }
    setState(() {
      _lines.add(_Line(command, _Kind.command));
      _lines.addAll(_outputFor(command));
    });
    _toBottom();
  }

  List<_Line> _outputFor(String command) => switch (command.split(' ').first) {
    'ls' => const [
      _Line(
        'apps    docker-compose.yml    Makefile    README.md',
        _Kind.output,
      ),
      _Line('bin     grafana.ini         node_modules  scripts', _Kind.output),
    ],
    'uname' => const [
      _Line('Linux devbox 6.8.0-45-generic x86_64', _Kind.output),
    ],
    'tailscale' => const [
      _Line('devbox    100.71.200.9   online', _Kind.output),
      _Line('pixel-9   100.101.4.2    offline', _Kind.output),
      _Line('nas       100.88.12.7    online', _Kind.output),
    ],
    'docker' => const [
      _Line('grafana:11.3.0        Up 12 days', _Kind.output),
      _Line('code-server:latest    Up 12 days', _Kind.output),
    ],
    'whoami' => const [_Line('root', _Kind.output)],
    'pwd' => const [_Line('/root', _Kind.output)],
    'uptime' => const [
      _Line('16:47 up 12 days, 2 users, load 0.12 0.09 0.06', _Kind.output),
    ],
    'help' => const [
      _Line(
        'Try: ls · uname -a · tailscale · docker ps · whoami · pwd · uptime · clear',
        _Kind.muted,
      ),
    ],
    _ => [
      _Line('bash: $command: command not found', _Kind.error),
      const _Line('Type help for the demo commands.', _Kind.muted),
    ],
  };

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final bottom = _scroll.position.maxScrollExtent;
      if (context.disableAnimations) {
        _scroll.jumpTo(bottom);
        return;
      }
      _scroll.animateTo(
        bottom,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Color _colorOf(TerminalPalette palette, _Kind kind) => switch (kind) {
    _Kind.command => palette.foreground,
    _Kind.output => palette.foreground.withValues(alpha: 0.86),
    _Kind.muted => palette.dim,
    _Kind.error => palette.error,
    _Kind.ok => palette.success,
  };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 900;
    final keyboard = _keyboardInset(context);
    final l10n = AppLocalizations.of(context);
    final backend = BackendScope.of(context);
    final palette = terminalPaletteOf(
      backend.terminalTheme,
      Theme.of(context).brightness,
    );
    final family = terminalFontFamily(backend.terminalFont);
    final session = _session;
    final mono = TextStyle(
      fontFamily: family,
      fontFamilyFallback: terminalFontFallback,
      fontSize: wide ? 14.5 : 13.5,
      height: 1.6,
      color: palette.foreground,
      decoration: TextDecoration.none,
    );
    final closed = _closedReason != null || widget.terminal.closed;
    final (status, statusColor) = widget.demo
        ? (l10n.demo, palette.warning)
        : widget.live
        ? (closed
              ? (l10n.disconnected, palette.error)
              : _connected
              ? (l10n.connected, palette.success)
              : (l10n.connecting, palette.warning))
        : session == null
        ? (l10n.connected, palette.success)
        : (l10n.notConnected, palette.dim);
    final fontSize = _pinchFont ?? backend.terminalFontSize;
    // Landscape on a phone is short: the quick commands would cost half the
    // rows the grid needs.
    final compact = MediaQuery.sizeOf(context).height < 420;
    final grid = session?.snapshot;
    final subtitle = widget.demo
        ? (grid == null
              ? 'libghostty-vt'
              : 'libghostty-vt · ${grid.cols}×${grid.rows}')
        : widget.live
        ? '${widget.node.ip}:${widget.port} · ${widget.node.os}'
        : '${widget.node.os} · ${widget.node.ip} · 18 ms';
    final keyRow = _showKeyRow(context);
    // The chrome under the grid owns the gesture bar (or the notch) below it,
    // so the row's surface reaches the screen edge instead of stopping short.
    final bottomInset = keyboard > 0 ? 0.0 : MediaQuery.viewPaddingOf(context).bottom;
    return Surface(
      color: palette.background,
      child: DefaultTextStyle(
        style: mono,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [palette.background, palette.backgroundAlt],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.only(bottom: keyboard),
              child: Column(
                children: [
                  _Header(
                    node: widget.node,
                    onClose: widget.onClose,
                    mono: mono,
                    palette: palette,
                    user: widget.user,
                    subtitle: subtitle,
                    status: status,
                    statusColor: statusColor,
                    reconnect: closed ? widget.onReconnect : null,
                    agents: widget.onAgents,
                  ),
                  if (widget.sessions.length > 1)
                    TerminalSessionStrip(
                      sessions: widget.sessions,
                      current: widget.terminal,
                      palette: palette,
                      onSwitch: widget.onSwitch,
                    ),
                  LiveRegion(message: status),
                  Expanded(
                    child: Semantics(
                      container: true,
                      readOnly: true,
                      label: l10n.terminalOutput,
                      hint: l10n.terminalReadOnly,
                      child: session == null
                          ? _simulated(wide, mono, palette)
                          : _emulator(
                              session,
                              fontSize,
                              backend.terminalSwipeArrows,
                              palette,
                              family,
                            ),
                    ),
                  ),
                  if (!compact)
                    _QuickBar(
                      palette: palette,
                      snippets: backend.terminalSnippets,
                      onRun: _run,
                      onSnippet: _sendSnippet,
                      onManage: () => unawaited(_openSnippets()),
                    ),
                  _InputBar(
                    controller: _input,
                    mono: mono,
                    palette: palette,
                    focusNode: _focus,
                    bottomInset: keyRow ? 0 : bottomInset,
                    onPaste: session == null ? null : _paste,
                    onTap: _focusTerminal,
                    onChanged: _session == null ? null : _onTextChanged,
                    onSubmitted: (value) {
                      if (widget.live) {
                        if (value.isNotEmpty) _sendLine(value);
                        _input.clear();
                        return;
                      }
                      if (widget.demo) {
                        // Typed characters were already echoed as they arrived.
                        _session?.feed(Uint8List.fromList(utf8.encode('\r\n')));
                        _input.clear();
                        return;
                      }
                      _run(value);
                      _input.clear();
                    },
                  ),
                  if (keyRow)
                    TerminalKeyBar(
                      pages: backend.terminalKeyPages,
                      mods: _mods,
                      palette: palette,
                      bottomInset: bottomInset,
                      onKey: _tapKey,
                      onModifier: (mod) {
                        setState(() => _mods.tap(mod));
                        _haptic();
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// A desktop window always has a hardware keyboard, so the row would only
  /// take room. On a phone it hides while a physical keyboard is attached,
  /// unless Settings keeps it or the soft keyboard is up.
  bool _showKeyRow(BuildContext context) {
    if (BackendScope.of(context).terminalKeyRowWithKeyboard) return true;
    // `?keys=1` keeps the row on a preview build that reports a keyboard.
    if (previewParam('keys') == '1') return true;
    final mobile = switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
    if (!mobile) return false;
    if ((_physicalKeyboard ?? false) &&
        MediaQuery.viewInsetsOf(context).bottom == 0) {
      return false;
    }
    return true;
  }

  /// The keyboard reaches the page as a view inset on every platform: nothing
  /// above the terminal builds a Scaffold that would resize for it.
  static double _keyboardInset(BuildContext context) =>
      MediaQuery.viewInsetsOf(context).bottom;

  Widget _emulator(
    TerminalSession session,
    double fontSize,
    bool swipeArrows,
    TerminalPalette palette,
    String family,
  ) {
    final backend = BackendScope.of(context);
    return Listener(
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent) return;
        final lines = (event.scrollDelta.dy / 20).round();
        if (lines != 0) session.scroll(lines);
      },
      child: TerminalCanvas(
        session: session,
        fontSize: fontSize,
        fontFamily: family,
        fontFallback: terminalFontFallback,
        palette: palette,
        cursor: backend.terminalCursor,
        cursorBlink: backend.terminalCursorBlink,
        swipeArrows: swipeArrows,
        onArrow: _onArrow,
        onFontSize: _zoomTo,
        onFocus: _focusTerminal,
        onOpenUrl: _openUrl,
        onPaste: _paste,
      ),
    );
  }

  Widget _simulated(bool wide, TextStyle mono, TerminalPalette palette) {
    // The demo node is not an SSH session, so it never claims to be connected.
    final banner = !widget.demo;
    return ListView.builder(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(wide ? 24 : 18, 14, wide ? 24 : 18, 10),
      itemCount: _lines.length + (banner ? 1 : 0),
      itemBuilder: (context, index) {
        if (banner && index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              AppLocalizations.of(context).connectedTo(widget.node.name),
              style: mono.copyWith(color: palette.success),
            ),
          );
        }
        final line = _lines[index - (banner ? 1 : 0)];
        final isCommand = line.kind == _Kind.command;
        final gap = isCommand ? 10.0 : 0.0;
        return Padding(
          padding: EdgeInsets.only(top: gap, bottom: 1),
          child: isCommand
              ? _PromptLine(
                  command: line.text,
                  mono: mono,
                  palette: palette,
                  user: widget.user,
                  host: widget.node.name,
                )
              : Text(
                  line.text,
                  style: mono.copyWith(color: _colorOf(palette, line.kind)),
                ),
        );
      },
    );
  }
}

class _PromptLine extends StatelessWidget {
  const _PromptLine({
    required this.command,
    required this.mono,
    required this.palette,
    required this.user,
    required this.host,
  });

  final String command;
  final TextStyle mono;
  final TerminalPalette palette;
  final String user;
  final String host;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$user@$host',
            style: mono.copyWith(color: palette.success),
          ),
          TextSpan(
            text: ':~\$ ',
            style: mono.copyWith(color: palette.dim),
          ),
          TextSpan(
            text: command,
            style: mono.copyWith(
              color: palette.foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.node,
    required this.onClose,
    required this.mono,
    required this.palette,
    required this.user,
    required this.subtitle,
    required this.status,
    required this.statusColor,
    this.reconnect,
    this.agents,
  });

  final NodeItem node;
  final VoidCallback onClose;
  final TextStyle mono;
  final TerminalPalette palette;
  final String user;
  final String subtitle;
  final String status;
  final Color statusColor;
  final VoidCallback? reconnect;
  final VoidCallback? agents;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 8, 14, 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: palette.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: GlyphIcon(Glyphs.chevronBack, color: palette.foreground),
            tooltip: AppLocalizations.of(context).close,
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$user@${node.name}',
                  style: mono.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 1),
                FadeThrough(
                  child: Semantics(
                    container: true,
                    label: subtitle,
                    excludeSemantics: true,
                    child: Text(
                      subtitle,
                      key: ValueKey(subtitle),
                      style: mono.copyWith(fontSize: 11, color: palette.dim),
                    ),
                  ),
                ),
              ],
            ),
          ),
          MotionVisibility(
            visible: reconnect != null,
            scaleFrom: 0.8,
            child: _HeaderTextButton(
              label: AppLocalizations.of(context).reconnect,
              onPressed: reconnect ?? () {},
              mono: mono,
              color: palette.accent,
            ),
          ),
          if (agents != null)
            Builder(
              builder: (context) {
                final herdr = BackendScope.of(context).herdr;
                if (herdr == null) return const SizedBox.shrink();
                return ListenableBuilder(
                  listenable: herdr,
                  builder: (context, _) => MotionVisibility(
                    visible: herdr.ready && herdr.node == node.name,
                    scaleFrom: 0.6,
                    child: IconButton(
                      onPressed: agents,
                      icon: GlyphIcon(
                        Glyphs2.agents,
                        size: 18,
                        color: palette.foreground,
                      ),
                      tooltip: AppLocalizations.of(context).agentsTitle,
                    ),
                  ),
                );
              },
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: ShapeDecoration(
              color: statusColor.withValues(alpha: 0.12),
              shape: const StadiumBorder(),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  status,
                  style: mono.copyWith(fontSize: 10.5, color: statusColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderTextButton extends StatelessWidget {
  const _HeaderTextButton({
    required this.label,
    required this.onPressed,
    required this.mono,
    required this.color,
  });

  final String label;
  final VoidCallback onPressed;
  final TextStyle mono;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: ButtonStyle.from(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
        shape: const StadiumBorder(),
      ),
      child: Text(label, style: mono.copyWith(fontSize: 11.5)),
    );
  }
}

/// The snippets button comes first, then the saved commands, or the built-in
/// ones while the drawer is empty.
class _QuickBar extends StatelessWidget {
  const _QuickBar({
    required this.palette,
    required this.snippets,
    required this.onRun,
    required this.onSnippet,
    required this.onManage,
  });

  final TerminalPalette palette;
  final List<TerminalSnippet> snippets;
  final ValueChanged<String> onRun;
  final ValueChanged<TerminalSnippet> onSnippet;
  final VoidCallback onManage;

  static const _commands = [
    'ls',
    'uname -a',
    'tailscale',
    'docker ps',
    'clear',
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: [
          _QuickChip(
            label: l10n.terminalSnippets,
            palette: palette,
            glyph: Glyphs2.bolt,
            onTap: onManage,
          ),
          for (final snippet in snippets)
            _QuickChip(
              label: snippet.label,
              palette: palette,
              tooltip: snippet.command,
              onTap: () => onSnippet(snippet),
            ),
          if (snippets.isEmpty)
            for (final command in _commands)
              _QuickChip(
                label: command,
                palette: palette,
                onTap: () => onRun(command),
              ),
        ],
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({
    required this.label,
    required this.palette,
    required this.onTap,
    this.tooltip,
    this.glyph,
  });

  final String label;
  final TerminalPalette palette;
  final VoidCallback onTap;
  final String? tooltip;
  final Glyph? glyph;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: tooltip ?? '',
        child: Semantics(
          button: true,
          label: tooltip == null ? label : '$label: $tooltip',
          excludeSemantics: true,
          onTap: onTap,
          child: TapFeedback(
            onTap: onTap,
            excludeFromSemantics: true,
            squish: true,
            shape: AppShape.full,
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: ShapeDecoration(
                color: palette.surface,
                shape: const StadiumBorder(),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (glyph case final glyph?) ...[
                    GlyphIcon(glyph, size: 13, color: palette.dim),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: terminalFontFamily(TerminalFontId.dejavu),
                      fontSize: 11.5,
                      color: palette.foreground.withValues(alpha: 0.9),
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.mono,
    required this.palette,
    required this.onSubmitted,
    this.focusNode,
    this.bottomInset = 0,
    this.onChanged,
    this.onPaste,
    this.onTap,
  });

  final TextEditingController controller;
  final TextStyle mono;
  final TerminalPalette palette;
  final ValueChanged<String> onSubmitted;
  final FocusNode? focusNode;

  /// Gesture bar or cutout below the input line, when no key row follows it.
  final double bottomInset;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onPaste;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 2, 12, 12 + bottomInset),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: ShapeDecoration(
          color: palette.surface,
          shape: AppShape.all(12),
          shadows: const [],
        ),
        child: Row(
          children: [
            GlyphIcon(Glyphs.chevronForward, size: 13, color: palette.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                textField: true,
                label: AppLocalizations.of(context).terminalInput,
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: true,
                  onTap: onTap,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  cursorColor: palette.accent,
                  cursorHeight: 15,
                  style: mono.copyWith(fontSize: 13),
                  decoration: InputDecoration.collapsed(
                    hintText: AppLocalizations.of(context).typeCommand,
                    hintStyle: TextStyle(
                      fontFamily: terminalFontFamily(TerminalFontId.dejavu),
                      fontSize: 13,
                      color: palette.dim.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ),
            ),
            if (onPaste != null)
              Semantics(
                button: true,
                label: AppLocalizations.of(context).terminalPasteButton,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onPaste,
                  child: SizedBox(
                    width: 34,
                    height: 34,
                    child: Center(
                      child: GlyphIcon(Glyphs.paste, size: 16, color: palette.dim),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
