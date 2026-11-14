import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../a11y.dart';
import '../backend.dart';
import '../glyphs.dart';
import '../data.dart';
import '../l10n.dart';
import '../motion.dart';
import '../native/bridge.dart';
import '../native/keys.dart';
import '../native/term.dart';
import '../native/term_demo.dart';
import '../terminal_keys.dart';
import '../terminal_store.dart';
import '../widgets/controls.dart';
import 'term_key_bar.dart';
import 'term_view.dart';

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

class _TerminalPageState extends State<TerminalPage> {
  static const _bgTop = Color(0xFF090A0C);
  static const _bgBottom = Color(0xFF101319);
  static const _fg = Color(0xFFE7E9ED);
  static const _dim = Color(0xFF7C838D);
  static const _green = Color(0xFF57D7A0);
  static const _red = Color(0xFFFF7B72);

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

  /// The libghostty-vt emulator; null on Web or when the library is missing.
  TerminalSession? _session;
  final _focus = FocusNode(debugLabel: 'terminal');
  StreamSubscription<SshOutput>? _output;
  String? _closedReason;
  bool _connected = false;
  bool _bannerFed = false;
  String _sent = '';
  final _mods = TerminalMods();

  @override
  void initState() {
    super.initState();
    final terminal = widget.terminal;
    final term = createNativeTerm(cols: 80, rows: 24, scrollback: 5000);
    if (term != null) {
      _session = TerminalSession(term)
        ..addListener(_onSessionChanged)
        ..onResize = (cols, rows) => terminal.resize(cols, rows);
      if (widget.demo) {
        _session!.feed(demoSessionBytes());
      } else {
        // Output that arrived while no page was attached.
        final buffered = terminal.takeBuffered();
        if (buffered.isNotEmpty) {
          _session!.feed(buffered);
          _connected = terminal.live;
        }
      }
    }
    if (terminal.live) {
      _focus.onKeyEvent = _onKey;
      _output = terminal.frames.listen(_onOutput);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
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
    final bytes = frame.bytes;
    if (bytes == null) return;
    final reply = session?.feed(bytes);
    if (reply != null && reply.isNotEmpty) widget.terminal.write(reply);
    if (!frame.notice && !_connected) setState(() => _connected = true);
  }

  static Uint8List _ansi(String text) => Uint8List.fromList(utf8.encode(text));

  /// Hardware keys reach the emulator's encoder; printable characters come
  /// through the text field below and are encoded there.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final terminal = widget.terminal;
    if (!terminal.live || _session == null) return KeyEventResult.ignored;
    final session = _session!;
    if (event is KeyUpEvent) return KeyEventResult.handled;
    final mods = ghosttyModsOf(HardwareKeyboard.instance);
    final text = event.character;
    // Plain printable keys go through the text field, which encodes them.
    if (text != null && text.isNotEmpty && mods & ~GhosttyMods.shift == 0) {
      return KeyEventResult.ignored;
    }
    final encoded = session.term.encodeKey(ghosttyKeyOf(event), mods);
    if (encoded != null) terminal.write(encoded);
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
    // Detach only; the session stays up in the store and back reattaches.
    _output?.cancel();
    _focus.dispose();
    _session?.removeListener(_onSessionChanged);
    _session?.dispose();
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

  Color _colorOf(_Kind kind) => switch (kind) {
    _Kind.command => _fg,
    _Kind.output => const Color(0xFFC9CDD6),
    _Kind.muted => _dim,
    _Kind.error => _red,
    _Kind.ok => _green,
  };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 900;
    final keyboard = _keyboardInset(context);
    final l10n = AppLocalizations.of(context);
    final session = _session;
    final mono = TextStyle(
      fontFamily: 'DejaVuSansMono',
      fontFamilyFallback: const ['NotoSansCJK'],
      fontSize: wide ? 14.5 : 13.5,
      height: 1.6,
      color: _fg,
      decoration: TextDecoration.none,
    );
    final (status, statusColor) = widget.demo
        ? (l10n.demo, const Color(0xFFE3B341))
        : widget.live
        ? (_closedReason != null
              ? (l10n.disconnected, _red)
              : _connected
              ? (l10n.connected, _green)
              : (l10n.connecting, const Color(0xFFE3B341)))
        : session == null
        ? (l10n.connected, _green)
        : (l10n.notConnected, _dim);
    final grid = session?.snapshot;
    final subtitle = widget.demo
        ? (grid == null
              ? 'libghostty-vt'
              : 'libghostty-vt · ${grid.cols}×${grid.rows}')
        : widget.live
        ? '${widget.node.ip}:${widget.port} · ${widget.node.os}'
        : '${widget.node.os} · ${widget.node.ip} · 18 ms';
    return Surface(
      color: _bgTop,
      child: DefaultTextStyle(
        style: mono,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_bgTop, _bgBottom],
            ),
          ),
          child: SafeArea(
            bottom: keyboard == 0,
            child: Padding(
              padding: EdgeInsets.only(bottom: keyboard),
              child: Column(
                children: [
                  _Header(
                    node: widget.node,
                    onClose: widget.onClose,
                    mono: mono,
                    user: widget.user,
                    subtitle: subtitle,
                    status: status,
                    statusColor: statusColor,
                    reconnect: _closedReason != null
                        ? widget.onReconnect
                        : null,
                    agents: widget.onAgents,
                  ),
                  LiveRegion(message: status),
                  Expanded(
                    child: Semantics(
                      container: true,
                      readOnly: true,
                      label: l10n.terminalOutput,
                      hint: l10n.terminalReadOnly,
                      child: session == null
                          ? _simulated(wide, mono)
                          : _emulator(session, wide ? 14.0 : 13.0),
                    ),
                  ),
                  _QuickBar(onRun: _run),
                  _InputBar(
                    controller: _input,
                    mono: mono,
                    focusNode: _focus,
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
                  if (_showKeyRow(wide))
                    TerminalKeyBar(
                      pages: BackendScope.of(context).terminalKeyPages,
                      mods: _mods,
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

  /// A desktop window has a hardware keyboard, so the row would only take
  /// room; phones and tablets keep it.
  static bool _showKeyRow(bool wide) =>
      !wide ||
      switch (defaultTargetPlatform) {
        TargetPlatform.android || TargetPlatform.iOS => true,
        _ => false,
      };

  /// iOS and macOS report the keyboard as an inset; Android's adjustResize
  /// already shrank the view.
  static double _keyboardInset(BuildContext context) =>
      switch (defaultTargetPlatform) {
        TargetPlatform.iOS ||
        TargetPlatform.macOS => MediaQuery.viewInsetsOf(context).bottom,
        _ => 0,
      };

  Widget _emulator(TerminalSession session, double fontSize) {
    return Listener(
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent) return;
        final lines = (event.scrollDelta.dy / 20).round();
        if (lines != 0) session.scroll(lines);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.live ? _focus.requestFocus : null,
        child: TerminalCanvas(session: session, fontSize: fontSize),
      ),
    );
  }

  Widget _simulated(bool wide, TextStyle mono) {
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
              style: mono.copyWith(color: _green),
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
                  user: widget.user,
                  host: widget.node.name,
                )
              : Text(
                  line.text,
                  style: mono.copyWith(color: _colorOf(line.kind)),
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
    required this.user,
    required this.host,
  });

  final String command;
  final TextStyle mono;
  final String user;
  final String host;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$user@$host',
            style: mono.copyWith(color: const Color(0xFF57D7A0)),
          ),
          TextSpan(
            text: ':~\$ ',
            style: mono.copyWith(color: const Color(0xFF5C6370)),
          ),
          TextSpan(
            text: command,
            style: mono.copyWith(
              color: const Color(0xFFE7E9ED),
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
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0x14FFFFFF), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: const GlyphIcon(Glyphs.chevronBack, color: Color(0xFFE7E9ED)),
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
                  child: Text(
                    subtitle,
                    key: ValueKey(subtitle),
                    style: mono.copyWith(
                      fontSize: 11,
                      color: const Color(0xFF7C838D),
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
                        color: const Color(0xFFE7E9ED),
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
  });

  final String label;
  final VoidCallback onPressed;
  final TextStyle mono;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: ButtonStyle.from(
        foregroundColor: const Color(0xFF7FB4FF),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
        shape: const StadiumBorder(),
      ),
      child: Text(label, style: mono.copyWith(fontSize: 11.5)),
    );
  }
}

class _QuickBar extends StatelessWidget {
  const _QuickBar({required this.onRun});

  final ValueChanged<String> onRun;

  static const _commands = [
    'ls',
    'uname -a',
    'tailscale',
    'docker ps',
    'clear',
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: [
          for (final command in _commands)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TapFeedback(
                onTap: () => onRun(command),
                scale: true,
                shape: AppShape.full,
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: const ShapeDecoration(
                    color: Color(0xFF15181F),
                    shape: StadiumBorder(),
                  ),
                  child: Text(
                    command,
                    style: const TextStyle(
                      fontFamily: 'DejaVuSansMono',
                      fontSize: 11.5,
                      color: Color(0xFFAEB4BE),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.mono,
    required this.onSubmitted,
    this.focusNode,
    this.onChanged,
  });

  final TextEditingController controller;
  final TextStyle mono;
  final ValueChanged<String> onSubmitted;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: ShapeDecoration(
          color: const Color(0xFF15181F),
          shape: AppShape.all(12),
          shadows: const [],
        ),
        child: Row(
          children: [
            const GlyphIcon(
              Glyphs.chevronForward,
              size: 13,
              color: Color(0xFF7FB4FF),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: true,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                cursorColor: const Color(0xFF7FB4FF),
                cursorHeight: 15,
                style: mono.copyWith(fontSize: 13),
                decoration: InputDecoration.collapsed(
                  hintText: AppLocalizations.of(context).typeCommand,
                  hintStyle: const TextStyle(
                    fontFamily: 'DejaVuSansMono',
                    fontSize: 13,
                    color: Color(0xFF4A515B),
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
