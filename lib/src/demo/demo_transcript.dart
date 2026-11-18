import 'dart:convert';

import 'demo.dart';

/// `?chat=w1:p1&herdr=demo&transcript=demo`: the demo herdr answers with a
/// Claude session whose reply exercises the Markdown renderer. Its shape is
/// what `native/bridge/transcript.go` returns.
String? demoTranscript(String? which) {
  if (!demoData || which != 'demo') return null;
  return jsonEncode({
    'model': 'claude-opus-4-1',
    'context': {'used': 48210, 'window': 200000},
    'messages': _messages,
  });
}

const demoAgentReply = '''
## Why the cold-start dial fails

The dial runs **before** the tailnet has a netmap, so `devbox` does not resolve yet. Two places decide this:

1. [`agents_phase.dart`](lib/src/agents_phase.dart) starts the dial on *Running*.
2. [`herdr.go`](/home/bang/src/taildeck-ui/native/bridge/herdr.go) gives up after one `4 s` attempt.

> The fix is to wait for the first netmap, not to retry.

```go
func (h *Herdr) dial(ctx context.Context) error {
	// Wait for the peer table before resolving.
	if err := h.node.WaitNetmap(ctx); err != nil {
		return fmt.Errorf("tailnet not ready: %w", err)
	}
	return h.connect(ctx, "devbox", 22)
}
```

| Step | Before | After |
|:--|:-:|--:|
| tailnet `Running` | dial | wait |
| first netmap | – | dial |
| failure | auto retry | **Retry** button |
| cold start (median) | 4.1 s | 1.3 s |

- [x] read the dial path
- [x] reproduce on a cold start
- [ ] ship the change

Dashboard: http://devbox.tail4a2c.ts.net:3000/d/herdr · docs: [MagicDNS](https://tailscale.com/kb/1081/magicdns) · a long one: https://github.com/markbang/taildeck-ui/blob/main/native/bridge/transcript_resolution_for_claude_sessions.go#L120-L188

Log file: `/home/bang/.local/state/herdr/sessions/default/panes/w3-p4/claude-2026-11-18T09-14-03.jsonl`

<b>raw html stays text</b> and [this link](javascript:alert(1)) does nothing.
''';

const _messages = [
  {'role': 'user', 'text': 'Why does the herdr dial fail on a cold start?'},
  {
    'role': 'thinking',
    'text':
        'Look at where the agents page starts the dial, then at the Go side.',
  },
  {
    'role': 'tool',
    'kind': 'shell',
    'name': 'Bash',
    'summary': 'rg -n "dial" lib/src native/bridge',
    'output': 'lib/src/agents_phase.dart:41: dial()\nnative/bridge/herdr.go:56: func ConnectHerdr',
  },
  {
    'role': 'tool',
    'kind': 'read',
    'name': 'Read',
    'summary': 'lib/src/agents_phase.dart',
  },
  {
    'role': 'tool',
    'kind': 'read',
    'name': 'Read',
    'summary': 'native/bridge/herdr.go',
  },
  {
    'role': 'tool',
    'kind': 'shell',
    'name': 'Bash',
    'summary': 'go test ./native/bridge -run Dial',
    'output': 'ok  \ttaildeck/native/bridge\t0.412s',
  },
  {'role': 'assistant', 'text': demoAgentReply},
  {'role': 'user', 'text': 'Ship it and run the tests.'},
  {
    'role': 'tool',
    'kind': 'edit',
    'name': 'Edit',
    'summary': 'native/bridge/herdr.go',
  },
  {
    'role': 'tool',
    'kind': 'shell',
    'name': 'Bash',
    'summary': 'go test ./native/bridge/...',
    'output': 'ok  \ttaildeck/native/bridge\t1.204s',
  },
  {
    'role': 'tool',
    'kind': 'shell',
    'name': 'Bash',
    'summary': 'flutter test',
    'output': '00:21 +118: All tests passed!',
  },
  {
    'role': 'assistant',
    'text':
        'Done. `go test` and `flutter test` pass (**118** tests). '
        'The change is in [herdr.go](native/bridge/herdr.go).',
  },
];
