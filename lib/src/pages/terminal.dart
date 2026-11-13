import 'package:flutter/widgets.dart';
import 'package:prism_ui/icons/icons.dart';
import 'package:prism_ui/prism_ui.dart';

import '../data.dart';

enum _Kind { input, output, muted, error, ok }

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
  static const _bg = Color(0xFF0B0C0E);
  static const _fg = Color(0xFFE6E8EC);
  static const _dim = Color(0xFF8C929C);
  static const _green = Color(0xFF57D7A0);
  static const _red = Color(0xFFFF7B72);
  static const _blue = Color(0xFF7FB4FF);

  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final List<_Line> _lines = [
    _Line('Connected to ${widget.node.name} · Tailscale SSH', _Kind.ok),
    _Line('Linux devbox 6.8.0-45-generic #45-Ubuntu SMP x86_64', _Kind.output),
    _Line('Last login: Thu Nov 13 16:02:11 2026 from 100.101.4.2', _Kind.muted),
    _Line(r'root@devbox:~$ uptime', _Kind.input),
    _Line(' 16:47:03 up 12 days,  4:21,  2 users,  load average: 0.14, 0.09, 0.06', _Kind.output),
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
      _lines.add(_Line('root@devbox:~\$ $command', _Kind.input));
      for (final line in _outputFor(command)) {
        _lines.add(line);
      }
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
        _Line('100.71.200.9   devbox     markbang@   linux   -', _Kind.output),
        _Line('100.101.4.2    pixel-9    markbang@   android offline', _Kind.output),
        _Line('100.88.12.7    nas        markbang@   linux   -', _Kind.output),
      ],
    'docker' => const [
        _Line('CONTAINER ID   IMAGE             STATUS         NAMES', _Kind.output),
        _Line('3f9c1a2b7d10   grafana:11.3.0    Up 12 days     grafana', _Kind.output),
        _Line('8a71d0c4e512   codercom/code-server   Up 12 days  code', _Kind.output),
      ],
    'whoami' => const [_Line('root', _Kind.output)],
    'pwd' => const [_Line('/root', _Kind.output)],
    'help' => const [
        _Line('Demo terminal. Try: ls, uname -a, tailscale, uptime, docker ps, whoami, pwd, clear', _Kind.muted),
      ],
    'uptime' => const [
        _Line(' 16:47:12 up 12 days,  4:21,  2 users,  load average: 0.12, 0.09, 0.06', _Kind.output),
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
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  Color _colorOf(_Kind kind) => switch (kind) {
    _Kind.input => _blue,
    _Kind.output => _fg,
    _Kind.muted => _dim,
    _Kind.error => _red,
    _Kind.ok => _green,
  };

  @override
  Widget build(BuildContext context) {
    final mono = TextStyle(
      fontFamily: 'DejaVuSansMono',
      fontSize: 13,
      height: 1.55,
      color: _fg,
      decoration: TextDecoration.none,
    );
    return Surface(
      color: _bg,
      child: DefaultTextStyle(
        style: mono,
        child: SafeArea(
        child: Column(
          children: [
            _Header(node: widget.node, onClose: widget.onClose, mono: mono),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                itemCount: _lines.length,
                itemBuilder: (context, index) {
                  final line = _lines[index];
                  final isInput = line.kind == _Kind.input;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          if (isInput)
                            const TextSpan(
                              text: '',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          TextSpan(text: line.text),
                        ],
                      ),
                      style: mono.copyWith(color: _colorOf(line.kind)),
                    ),
                  );
                },
              ),
            ),
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
      padding: const EdgeInsets.fromLTRB(6, 6, 12, 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: const Color(0xFF1E2126), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onClose,
            icon: const GlyphIcon(Glyphs.chevronBack, color: Color(0xFFE6E8EC)),
            tooltip: 'Close',
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Text(
              'root@${node.name}',
              style: mono.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: const ShapeDecoration(
              color: Color(0x1F57D7A0),
              shape: StadiumBorder(),
            ),
            child: const Text(
              'Connected',
              style: TextStyle(
                fontFamily: 'DejaVuSansMono',
                fontSize: 11,
                color: Color(0xFF57D7A0),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF1E2126), width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('root@devbox:~\$ ', style: mono.copyWith(color: const Color(0xFF7FB4FF))),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              onSubmitted: onSubmitted,
              cursorColor: const Color(0xFF7FB4FF),
              style: mono,
              decoration: const InputDecoration.collapsed(
                hintText: 'help',
                hintStyle: TextStyle(
                  fontFamily: 'DejaVuSansMono',
                  fontSize: 13,
                  color: Color(0xFF3A3F47),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
