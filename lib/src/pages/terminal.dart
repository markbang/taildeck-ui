import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../data.dart';

enum _Kind { command, output, muted, error, ok }

class _Line {
  const _Line(this.text, this.kind);

  final String text;
  final _Kind kind;
}

class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key, required this.node, required this.onClose});

  final NodeItem node;
  final VoidCallback onClose;

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
    _Line('Connected to ${widget.node.name} · Tailscale SSH · 18 ms', _Kind.ok),
    _Line('Linux devbox 6.8.0-45-generic #45-Ubuntu SMP PREEMPT_DYNAMIC x86_64', _Kind.output),
    _Line('Last login: Thu Nov 13 16:02:11 2026 from 100.101.4.2', _Kind.muted),
    const _Line('uptime', _Kind.command),
    const _Line('16:47:03 up 12 days, 4:21, 2 users, load average: 0.14, 0.09, 0.06', _Kind.output),
    const _Line('tailscale status', _Kind.command),
    const _Line('100.71.200.9   devbox     markbang@   linux    -', _Kind.output),
    const _Line('100.101.4.2    pixel-9    markbang@   android  offline', _Kind.output),
    const _Line('100.88.12.7    nas        markbang@   linux    -', _Kind.output),
    const _Line('docker ps', _Kind.command),
    const _Line('CONTAINER ID   IMAGE                  STATUS        NAMES', _Kind.output),
    const _Line('3f9c1a2b7d10   grafana:11.3.0         Up 12 days    grafana', _Kind.output),
    const _Line('8a71d0c4e512   codercom/code-server   Up 12 days    code', _Kind.output),
  ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _run(String raw) {
    final command = raw.trim();
    if (command.isEmpty) return;
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
        _Line('Linux devbox 6.8.0-45-generic #45-Ubuntu SMP PREEMPT_DYNAMIC x86_64 GNU/Linux', _Kind.output),
      ],
    'tailscale' => const [
        _Line('100.71.200.9   devbox     markbang@   linux    -', _Kind.output),
        _Line('100.101.4.2    pixel-9    markbang@   android  offline', _Kind.output),
        _Line('100.88.12.7    nas        markbang@   linux    -', _Kind.output),
      ],
    'docker' => const [
        _Line('CONTAINER ID   IMAGE                  STATUS        NAMES', _Kind.output),
        _Line('3f9c1a2b7d10   grafana:11.3.0         Up 12 days    grafana', _Kind.output),
        _Line('8a71d0c4e512   codercom/code-server   Up 12 days    code', _Kind.output),
      ],
    'whoami' => const [_Line('root', _Kind.output)],
    'pwd' => const [_Line('/root', _Kind.output)],
    'uptime' => const [
        _Line('16:47:12 up 12 days, 4:21, 2 users, load average: 0.12, 0.09, 0.06', _Kind.output),
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
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
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
    final mono = TextStyle(
      fontFamily: 'DejaVuSansMono',
      fontSize: wide ? 14.5 : 13.5,
      height: 1.6,
      color: _fg,
      decoration: TextDecoration.none,
    );
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
                _Header(node: widget.node, onClose: widget.onClose, mono: mono),
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: EdgeInsets.fromLTRB(wide ? 24 : 18, 14, wide ? 24 : 18, 10),
                    itemCount: _lines.length,
                    itemBuilder: (context, index) {
                      final line = _lines[index];
                      final isCommand = line.kind == _Kind.command;
                      final gap = isCommand && index > 0 ? 10.0 : 0.0;
                      return Padding(
                        padding: EdgeInsets.only(top: gap, bottom: 1),
                        child: isCommand
                            ? _PromptLine(command: line.text, mono: mono)
                            : Text(
                                line.text,
                                style: mono.copyWith(color: _colorOf(line.kind)),
                              ),
                      );
                    },
                  ),
                ),
                _QuickBar(onRun: _run),
                _InputBar(
                  controller: _input,
                  mono: mono,
                  onSubmitted: (value) {
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
}

class _PromptLine extends StatelessWidget {
  const _PromptLine({required this.command, required this.mono});

  final String command;
  final TextStyle mono;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: 'root@devbox',
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
  const _Header({required this.node, required this.onClose, required this.mono});

  final NodeItem node;
  final VoidCallback onClose;
  final TextStyle mono;

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
            tooltip: 'Close',
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'root@${node.name}',
                  style: mono.copyWith(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 1),
                Text(
                  '${node.os} · ${node.ip} · 18 ms',
                  style: mono.copyWith(fontSize: 11, color: const Color(0xFF7C838D)),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: const ShapeDecoration(
              color: Color(0x1F57D7A0),
              shape: StadiumBorder(),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFF57D7A0),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  'Connected',
                  style: mono.copyWith(fontSize: 10.5, color: const Color(0xFF57D7A0)),
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
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: [
          for (final command in _commands)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: PressRegion(
                onTap: () => onRun(command),
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
  });

  final TextEditingController controller;
  final TextStyle mono;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: ShapeDecoration(
          color: const Color(0xFF15181F),
          shape: AppShape.all(12),
          // A hairline keeps the field readable over the gradient.
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
                autofocus: true,
                onSubmitted: onSubmitted,
                cursorColor: const Color(0xFF7FB4FF),
                cursorHeight: 15,
                style: mono.copyWith(fontSize: 13),
                decoration: const InputDecoration.collapsed(
                  hintText: 'Type a command',
                  hintStyle: TextStyle(
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

