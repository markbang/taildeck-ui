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
import '../native/bridge.dart';
import '../native/keys.dart';
import '../native/term.dart';
import '../demo/demo.dart';
import '../demo/demo_term.dart';
import '../preview_env.dart';
import '../term_session.dart';
import '../terminal_appearance.dart';
import '../terminal_gestures.dart';
import '../terminal_keys.dart';
import '../terminal_send.dart';
import '../terminal_snippets.dart';
import '../terminal_store.dart';
import '../widgets/snackbar.dart';
import 'term_toolbar.dart';
import 'terminal_compose_sheet.dart';
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
    with TickerProviderStateMixin {
  /// The hidden IME target: the soft keyboard types into this field, the
  /// handler sends each committed character, and the field is emptied again,
  /// so no input line is ever shown.
  final _ime = TextEditingController();
  final _imeFocus = FocusNode(debugLabel: 'terminal-ime');
  final _keyFocus = FocusNode(debugLabel: 'terminal-keys');
  final _scroll = ScrollController();

  /// The keyboard's inset, animated as one tween per change so the grid
  /// shrinks smoothly instead of jumping a frame.
  late final AnimationController _inset = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  Animation<double>? _insetTween;
  double _insetValue = 0;
  double _insetTarget = 0;
  bool _imeClearing = false;

  /// What the IME's field held at the last commit. The field keeps it, so a
  /// backspace reaches the remote as a KeyCode.DEL rather than only editing
  /// an invisible buffer; keeping the two in step is what makes that work.
  String _imeSnap = '';
  bool _arrowsOpen = false;

  /// The demo session's transcript; a release build starts empty and only
  /// ever shows what a real remote wrote.
  late final List<_Line> _lines = !demoData
      ? []
      : [
          _Line('Linux devbox 6.8.0-45-generic x86_64', _Kind.output),
          _Line(
            'Last login: Thu Nov 13 16:02:11 from 100.101.4.2',
            _Kind.muted,
          ),
          const _Line('uptime', _Kind.command),
          const _Line(
            '16:47 up 12 days, 2 users, load 0.14 0.09 0.06',
            _Kind.output,
          ),
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
  StreamSubscription<SshOutput>? _output;
  String? _closedReason;
  bool _connected = false;
  bool _bannerFed = false;
  int _demoRows = 0;
  final _mods = TerminalMods();

  /// One Send at a time, so the lines of a paste reach the remote in order.
  Future<void> _sending = Future<void>.value();

  /// Pinch size while the finger is down; the backend value lands after the
  /// debounce, then this falls back to it.
  double? _pinchFont;
  Timer? _fontSave;

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
    if (terminal.live) _output = terminal.frames.listen(_onOutput);
    _ime.addListener(_onImeChanged);
    _inset.addListener(_onInsetTick);
  }

  void _onInsetTick() {
    final tween = _insetTween;
    if (!mounted || tween == null) return;
    setState(() => _insetValue = tween.value);
  }

  /// A new keyboard inset, approached from the current value: a mid-animation
  /// change retargets instead of restarting from zero.
  void _aimInset(double target) {
    if (target == _insetTarget) return;
    _insetTarget = target;
    final begin = _insetValue;
    _inset.stop();
    if (context.disableAnimations || (begin - target).abs() < 0.5) {
      _insetValue = target;
      return;
    }
    _insetTween = Tween<double>(
      begin: begin,
      end: target,
    ).animate(CurvedAnimation(parent: _inset, curve: Curves.easeOutCubic));
    _inset
      ..reset()
      ..forward().whenComplete(() {
        if (mounted) setState(() => _insetValue = target);
      });
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

  /// Hardware keys go straight through the emulator's encoder. While the IME
  /// target holds focus, a printable key or Enter belongs to that field, whose
  /// change handler sends the committed text; everything else (Esc, Tab,
  /// arrows, Ctrl combinations, Backspace) is a terminal key here.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final session = _session;
    if (session == null) return KeyEventResult.ignored;
    if (event is KeyUpEvent) return KeyEventResult.handled;
    final typing = _imeFocus.hasFocus;
    final mods = ghosttyModsOf(HardwareKeyboard.instance);
    final text = event.character;
    final printable =
        text != null && text.isNotEmpty && text.codeUnitAt(0) >= 0x20;
    if (printable && mods & ~GhosttyMods.shift == 0) {
      if (typing) return KeyEventResult.ignored;
      final encoded = session.term.encodeKey(
        ghosttyKeyForText(text),
        0,
        text: text,
      );
      if (encoded != null) _deliver(encoded);
      return KeyEventResult.handled;
    }
    final key = ghosttyKeyOf(event);
    if (key == GhosttyKeys.enter && mods == 0) {
      if (typing) return KeyEventResult.ignored;
      final encoded = session.term.encodeKey(GhosttyKeys.enter, 0);
      if (encoded != null) _deliver(encoded);
      return KeyEventResult.handled;
    }
    final encoded = session.term.encodeKey(key, mods);
    if (encoded != null) _deliver(encoded);
    return KeyEventResult.handled;
  }

  /// The IME's committed text, compared with the last commit: appended
  /// characters are key presses (the armed Ctrl/Alt rides on the first one)
  /// and removed ones are Backspace presses. The field keeps the buffer and
  /// is only cleared when the keyboard closes, so Gboard's own backspace
  /// turns into a real deletion on the remote. A composition in progress is
  /// left to the IME until it commits.
  void _onImeChanged() {
    if (_imeClearing) return;
    final value = _ime.value;
    if (value.composing.isValid) return;
    final text = value.text;
    if (text == _imeSnap) return;
    final session = _session;
    if (session == null) {
      _imeSnap = text;
      return;
    }
    var common = 0;
    while (common < text.length &&
        common < _imeSnap.length &&
        text.codeUnitAt(common) == _imeSnap.codeUnitAt(common)) {
      common++;
    }
    final removed = _imeSnap.length - common;
    for (var i = 0; i < removed; i++) {
      final encoded = session.term.encodeKey(GhosttyKeys.backspace, 0);
      if (encoded != null) _deliver(encoded);
    }
    final added = text.substring(common);
    var mods = _mods.mask;
    var consumed = false;
    for (final rune in added.runes) {
      if (rune == 0x0a || rune == 0x0d) {
        final encoded = session.term.encodeKey(GhosttyKeys.enter, 0);
        if (encoded != null) _deliver(encoded);
        continue;
      }
      final ch = String.fromCharCode(rune);
      final encoded = session.term.encodeKey(
        ghosttyKeyForText(ch),
        mods,
        text: ch,
      );
      if (encoded != null) _deliver(encoded);
      if (mods != 0) {
        mods = 0;
        consumed = true;
      }
    }
    _imeSnap = text;
    if (consumed && _mods.consume()) setState(() {});
    // The caret stays at the end; the field is invisible, so any other
    // selection would only make a later diff ambiguous.
    if (value.selection.isValid && value.selection.end != text.length) {
      _imeClearing = true;
      _ime.selection = TextSelection.collapsed(offset: text.length);
      _imeClearing = false;
    }
  }

  void _clearIme() {
    _imeClearing = true;
    _ime.clear();
    _imeSnap = '';
    _imeClearing = false;
  }

  /// The toolbar's keyboard button: the only way in, apart from system back
  /// which Android keeps for closing it.
  void _toggleKeyboard() {
    _haptic();
    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      _hideKeyboard();
      return;
    }
    _showKeyboard();
  }

  /// Opens the IME on the hidden field. A field that kept focus does not ask
  /// Android for the IME again after the back key closed it, so focus is taken
  /// anew: one frame unfocused, then focused.
  void _showKeyboard() {
    if (_imeFocus.hasFocus) {
      _imeFocus.unfocus();
      _keyFocus.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _imeFocus.requestFocus();
        unawaited(
          SystemChannels.textInput.invokeMethod<void>('TextInput.show'),
        );
      });
      return;
    }
    _imeFocus.requestFocus();
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.show'));
  }

  void _hideKeyboard() {
    _imeFocus.unfocus();
    _keyFocus.requestFocus();
    _clearIme();
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
  }

  Future<void> _compose() async {
    _hideKeyboard();
    final backend = BackendScope.of(context);
    // `?compose=...` pre-fills the sheet on a preview build, so a recording
    // can show a CJK command without a Chinese IME installed.
    final initial = kReleaseMode ? '' : (previewParam('compose') ?? '');
    final text = await showTerminalComposeSheet(
      context,
      backend: backend,
      initialText: initial,
    );
    if (!mounted || text == null) return;
    await _send(text);
  }

  /// How long each line of a paste waits for the one before it.
  static const _linePace = Duration(milliseconds: 20);

  /// One Send, one chunk per line, written in order.
  ///
  /// The line breaks an Enter adds come from [terminalSendChunks], so a
  /// multi-line paste runs each line instead of landing in one command.
  Future<void> _send(String text, {bool? enter}) {
    final pressesEnter = enter ?? BackendScope.of(context).terminalSendEnter;
    final chunks = terminalSendChunks(
      text,
      pressesEnter ? TerminalSendMode.enter : TerminalSendMode.insert,
    );
    if (chunks.isEmpty) return Future<void>.value();
    if (!widget.live && !widget.demo) {
      // The mock has no remote shell: there is nowhere to write.
      return Future<void>.value();
    }
    _haptic();
    return _sending = _sending.then((_) async {
      for (final (index, chunk) in chunks.indexed) {
        if (!mounted) return;
        _writeChunk(chunk);
        if (index + 1 < chunks.length) {
          await Future<void>.delayed(_linePace);
        }
      }
    });
  }

  /// A line through the emulator's encoder: its characters, then the Enter
  /// that the trailing CR stands for.
  void _writeChunk(String chunk) {
    final session = _session;
    if (session == null) return;
    final enter = chunk.endsWith('\r');
    final body = enter ? chunk.substring(0, chunk.length - 1) : chunk;
    for (final rune in body.runes) {
      if (rune == 0x0a) {
        // Insert-only keeps the text's own line breaks.
        _deliver(session.term.encodeKey(GhosttyKeys.enter, 0));
        continue;
      }
      final ch = String.fromCharCode(rune);
      _deliver(session.term.encodeKey(ghosttyKeyForText(ch), 0, text: ch));
    }
    if (!enter) return;
    _deliver(session.term.encodeKey(GhosttyKeys.enter, 0));
    // The demo has no shell to echo the line break.
    if (widget.demo) _session?.feed(_ansi('\r\n'));
  }

  /// The long-press on Send and the row's Ins key: keep the text, skip Enter.
  void _toggleSendEnter() {
    final backend = BackendScope.of(context);
    final enter = !backend.terminalSendEnter;
    final l10n = AppLocalizations.of(context);
    unawaited(backend.setTerminalSendEnter(enter));
    _haptic();
    setState(() {});
    showMotionSnack(
      context,
      enter ? l10n.terminalSendEnterOn : l10n.terminalSendInsertOnly,
    );
  }

  void _tapKey(TerminalKey key) {
    if (key.toggle) {
      _toggleSendEnter();
      return;
    }
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
  }

  void _consumeMods() {
    if (_mods.consume()) setState(() {});
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
    _hideKeyboard();
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
    if (demoData) _session?.feed(_demoEcho(bytes));
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
    // MediaQuery changes bring a new keyboard inset; the page follows it with
    // one tween, and the grid holds its rows until it settles.
    _aimInset(MediaQuery.viewInsetsOf(context).bottom);
    if (_bannerFed || widget.demo || widget.live) return;
    _bannerFed = true;
    final session = _session;
    if (session == null) return;
    final text = AppLocalizations.of(context).sshPending;
    session.feed(Uint8List.fromList(utf8.encode('\x1b[2m$text\x1b[0m\r\n')));
  }

  @override
  void dispose() {
    _fontSave?.cancel();
    // Detach only; the session stays up in the store and back reattaches.
    _output?.cancel();
    _ime.removeListener(_onImeChanged);
    _inset.dispose();
    _imeFocus.dispose();
    _keyFocus.dispose();
    _session?.removeListener(_onSessionChanged);
    if (_ownsSession) _session?.dispose();
    _ime.dispose();
    _scroll.dispose();
    super.dispose();
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
      height: 1.5,
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
    final keyboardVisible = _keyboardInset(context) > 0;
    // The toolbar owns the gesture bar or cutout below it; the keyboard owns
    // the space while it is up.
    final bottomInset = keyboardVisible
        ? 0.0
        : MediaQuery.viewPaddingOf(context).bottom;
    final showToolbar = _showToolbar(context);
    final toolbarSpace = showToolbar ? 62 + bottomInset : 0.0;
    final title = '${widget.user}: ${widget.node.name}';
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
            child: Focus(
              focusNode: _keyFocus,
              autofocus: true,
              onKeyEvent: _onKey,
              child: Padding(
                padding: EdgeInsets.only(bottom: _insetValue),
                child: Column(
                  children: [
                    _Grabber(palette: palette),
                    _TitleBar(
                      title: title,
                      palette: palette,
                      mono: mono,
                      status: status,
                      statusColor: statusColor,
                      onClose: widget.onClose,
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
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Padding(
                              padding: EdgeInsets.only(bottom: toolbarSpace),
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
                                        palette,
                                        family,
                                      ),
                              ),
                            ),
                          ),
                          if (showToolbar)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: TerminalToolbar(
                                palette: palette,
                                mods: _mods,
                                pages: backend.terminalKeyPages,
                                expanded: _arrowsOpen,
                                keyboardVisible: keyboardVisible,
                                bottomInset: bottomInset,
                                onToggleExpanded: () {
                                  _haptic();
                                  setState(() => _arrowsOpen = !_arrowsOpen);
                                },
                                onKey: _tapKey,
                                onModifier: (mod) {
                                  setState(() => _mods.tap(mod));
                                  _haptic();
                                },
                                onSnippets: () => unawaited(_openSnippets()),
                                onPaste: () => unawaited(_paste()),
                                onCompose: () => unawaited(_compose()),
                                onKeyboard: _toggleKeyboard,
                              ),
                            ),
                          // The IME target: 1x1, invisible and untouchable, so
                          // the keyboard types into the shell without an input
                          // line, and a tap on the grid never reaches it.
                          Positioned(
                            left: 0,
                            top: 0,
                            width: 1,
                            height: 1,
                            child: IgnorePointer(
                              child: ExcludeSemantics(
                                child: Opacity(
                                  opacity: 0,
                                  child: TextField(
                                    controller: _ime,
                                    focusNode: _imeFocus,
                                    keyboardType: TextInputType.multiline,
                                    textInputAction: TextInputAction.newline,
                                    maxLines: null,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    enableInteractiveSelection: false,
                                    showCursor: false,
                                    style: mono.copyWith(
                                      color: const Color(0x00000000),
                                    ),
                                    decoration: const InputDecoration.collapsed(
                                      hintText: null,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// On a phone the toolbar is always there: it is the only way to open the
  /// keyboard, so hiding it while Android reports a physical keyboard (the
  /// emulator does) would leave no way in. A desktop window has a hardware
  /// keyboard, so it hides unless Settings or `?keys=1` asks for it.
  bool _showToolbar(BuildContext context) {
    if (BackendScope.of(context).terminalKeyRowWithKeyboard) return true;
    if (previewParam('keys') == '1') return true;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
  }

  /// The keyboard reaches the page as a view inset on every platform: nothing
  /// above the terminal builds a Scaffold that would resize for it.
  static double _keyboardInset(BuildContext context) =>
      MediaQuery.viewInsetsOf(context).bottom;

  Widget _emulator(
    TerminalSession session,
    double fontSize,
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
        liveResize: !_inset.isAnimating,
        onFontSize: _zoomTo,
        onBytes: _deliver,
        onMouseSent: _consumeMods,
        mouseMods: _mods.mask,
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

/// The sheet's grabber: a short pill at the top edge, the affordance that
/// says this page came up as a sheet.
class _Grabber extends StatelessWidget {
  const _Grabber({required this.palette});

  final TerminalPalette palette;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        height: 16,
        child: Center(
          child: Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: palette.foreground.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}

/// The narrow title bar: close dot and app mark, the session title, and a
/// small SSH badge that doubles as Reconnect once the session dropped.
class _TitleBar extends StatelessWidget {
  const _TitleBar({
    required this.title,
    required this.palette,
    required this.mono,
    required this.status,
    required this.statusColor,
    required this.onClose,
    this.reconnect,
    this.agents,
  });

  final String title;
  final TerminalPalette palette;
  final TextStyle mono;
  final String status;
  final Color statusColor;
  final VoidCallback onClose;
  final VoidCallback? reconnect;
  final VoidCallback? agents;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: SizedBox(
        height: 42,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
          child: Row(
            children: [
              Semantics(
                button: true,
                label: l10n.close,
                onTap: onClose,
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClose,
                  child: SizedBox(
                    height: 40,
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: palette.error,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Container(
                          width: 24,
                          height: 24,
                          decoration: ShapeDecoration(
                            color: palette.surface,
                            shape: AppShape.all(7).copyWith(
                              side: BorderSide(
                                color: palette.border,
                                width: 0.5,
                              ),
                            ),
                          ),
                          child: Center(
                            child: _AppMark(palette: palette, size: 14),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: mono.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: palette.foreground,
                  ),
                ),
              ),
              if (agents != null)
                Builder(
                  builder: (context) {
                    final herdr = BackendScope.of(context).herdr;
                    if (herdr == null) return const SizedBox.shrink();
                    return ListenableBuilder(
                      listenable: herdr,
                      builder: (context, _) => SizedBox(
                        width: herdr.ready ? 34 : 0,
                        child: herdr.ready
                            ? Semantics(
                                button: true,
                                label: l10n.agentsTitle,
                                onTap: agents,
                                excludeSemantics: true,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: agents,
                                  child: SizedBox(
                                    width: 34,
                                    height: 40,
                                    child: Center(
                                      child: GlyphIcon(
                                        Glyphs2.agents,
                                        size: 17,
                                        color: palette.foreground,
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    );
                  },
                ),
              if (reconnect != null)
                _ReconnectButton(
                  label: l10n.reconnect,
                  color: palette.accent,
                  mono: mono,
                  onTap: reconnect!,
                ),
              const SizedBox(width: 4),
              _SshBadge(
                status: status,
                color: statusColor,
                palette: palette,
                mono: mono,
                onTap: reconnect,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The launcher icon's 3x3 node grid, one node lit: the app mark, drawn small
/// enough for the title bar.
class _AppMark extends StatelessWidget {
  const _AppMark({required this.palette, required this.size});

  final TerminalPalette palette;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dot = size / 6;
    return SizedBox(
      width: size,
      height: size,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var row = 0; row < 3; row++)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var column = 0; column < 3; column++)
                  Container(
                    width: dot,
                    height: dot,
                    decoration: BoxDecoration(
                      color: row == 1 && column == 1
                          ? palette.accent
                          : palette.foreground.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// A dropped session's only extra control, kept to a word so the title bar
/// stays narrow; the badge next to it carries the state.
class _ReconnectButton extends StatelessWidget {
  const _ReconnectButton({
    required this.label,
    required this.color,
    required this.mono,
    required this.onTap,
  });

  final String label;
  final Color color;
  final TextStyle mono;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 40,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            label,
            style: mono.copyWith(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

/// A small SSH badge with the session's state dot; with a dropped session a
/// tap dials again instead of showing a Reconnect button in the header.
class _SshBadge extends StatelessWidget {
  const _SshBadge({
    required this.status,
    required this.color,
    required this.palette,
    required this.mono,
    this.onTap,
  });

  final String status;
  final Color color;
  final TerminalPalette palette;
  final TextStyle mono;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: onTap != null,
      label: 'SSH, $status',
      hint: onTap == null ? null : l10n.reconnect,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: ShapeDecoration(
            color: color.withValues(alpha: 0.12),
            shape: StadiumBorder(
              side: BorderSide(
                color: color.withValues(alpha: 0.28),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Text(
                'SSH',
                style: mono.copyWith(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
