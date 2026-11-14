import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../a11y.dart';
import '../data.dart';
import '../l10n.dart';
import '../native/bridge.dart';
import '../native/keys.dart';
import '../native/ssh.dart';
import '../native/term.dart';
import '../native/term_demo.dart';
import '../widgets/controls.dart';
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
    this.user = 'root',
    this.port = 22,
    this.ssh,
    this.demo = false,
  });

  final NodeItem node;
  final VoidCallback onClose;
  final String user;
  final int port;

  /// Live session from the Go node; null on the mock/web path.
  final SshSession? ssh;

  /// `?ssh=demo`: feed a canned ANSI session through the emulator.
  final bool demo;

  bool get live => ssh != null;

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

  @override
  void initState() {
    super.initState();
    final ssh = widget.ssh;
    final term = createNativeTerm(cols: 80, rows: 24, scrollback: 5000);
    if (term != null) {
      _session = TerminalSession(term)
        ..addListener(_onSessionChanged)
        ..onResize = (cols, rows) => ssh?.resize(cols, rows);
      if (widget.demo) _session!.feed(demoSessionBytes());
    }
    if (ssh != null) {
      _focus.onKeyEvent = _onKey;
      _output = ssh.output.listen(_onOutput);
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
    if (reply != null && reply.isNotEmpty) widget.ssh?.write(reply);
    if (!frame.notice && !_connected) setState(() => _connected = true);
  }

  static Uint8List _ansi(String text) => Uint8List.fromList(utf8.encode(text));

  /// Hardware keys reach the emulator's encoder; printable characters come
  /// through the text field below and are encoded there.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final ssh = widget.ssh;
    final session = _session;
    if (ssh == null || session == null) return KeyEventResult.ignored;
    if (event is KeyUpEvent) return KeyEventResult.handled;
    final mods = ghosttyModsOf(HardwareKeyboard.instance);
    final text = event.character;
    // Plain printable keys go through the text field, which encodes them.
    if (text != null && text.isNotEmpty && mods & ~GhosttyMods.shift == 0) {
      return KeyEventResult.ignored;
    }
    final encoded = session.term.encodeKey(ghosttyKeyOf(event), mods);
    if (encoded != null) ssh.write(encoded);
    return KeyEventResult.handled;
  }

  void _onTextChanged(String value) {
    final ssh = widget.ssh;
    final session = _session;
    if (ssh == null || session == null) return;
    // An IME preedit is not committed text: wait for the commit.
    if (_input.value.composing.isValid) return;
    final added = _sent.isEmpty
        ? value
        : (value.startsWith(_sent) ? value.substring(_sent.length) : value);
    _sent = value;
    for (final rune in added.runes) {
      final text = String.fromCharCode(rune);
      final encoded = session.term.encodeKey(
        ghosttyKeyForText(text),
        0,
        text: text,
      );
      if (encoded != null) ssh.write(encoded);
    }
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
    final ssh = widget.ssh;
    final session = _session;
    if (ssh == null || session == null) return;
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      final encoded = session.term.encodeKey(
        ghosttyKeyForText(ch),
        0,
        text: ch,
      );
      if (encoded != null) ssh.write(encoded);
    }
    final enter = session.term.encodeKey(58, 0); // GHOSTTY_KEY_ENTER
    if (enter != null) ssh.write(enter);
  }

  /// Keeps the header's grid size in step with the emulator.
  void _onSessionChanged() => setState(() {});

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
    _output?.cancel();
    widget.ssh?.close();
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
        _Line('apps    docker-compose.yml    Makefile    README.md', _Kind.output),
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
        _Line('Try: ls · uname -a · tailscale · docker ps · whoami · pwd · uptime · clear', _Kind.muted),
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
        ? (grid == null ? 'libghostty-vt' : 'libghostty-vt · ${grid.cols}×${grid.rows}')
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
                  onChanged: widget.live ? _onTextChanged : null,
                  onSubmitted: (value) {
                    if (widget.live) {
                      if (value.isNotEmpty) _sendLine(value);
                      _input.clear();
                      return;
                    }
                    _run(value);
                    _input.clear();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

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
          TextSpan(text: ':~\$ ', style: mono.copyWith(color: const Color(0xFF5C6370))),
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
  });

  final NodeItem node;
  final VoidCallback onClose;
  final TextStyle mono;
  final String user;
  final String subtitle;
  final String status;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 8, 14, 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x14FFFFFF), width: 0.5)),
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
                  style: mono.copyWith(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: mono.copyWith(fontSize: 11, color: const Color(0xFF7C838D)),
                ),
              ],
            ),
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

class _QuickBar extends StatelessWidget {
  const _QuickBar({required this.onRun});

  final ValueChanged<String> onRun;

  static const _commands = ['ls', 'uname -a', 'tailscale', 'docker ps', 'clear'];

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
