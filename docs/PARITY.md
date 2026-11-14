[English](PARITY.md) · [中文](PARITY.zh-CN.md)

# Parity with the Kotlin app

How much of [markbang/taildeck](https://github.com/markbang/taildeck) (Kotlin + Compose, `0d90f24`) the Flutter
client covers. The native boundary is described in [ARCHITECTURE.md](ARCHITECTURE.md); this page is only about
features.

| Status | Meaning |
|---|---|
| **Done** | Implemented and exercised here (UI screenshots, FFI smoke test, or a CI run). |
| **Unverified** | Implemented, but never exercised end to end on this machine. |
| **Partial** | Works, with a named gap. |
| **Not yet** | Missing. |

The build machine has no Tailscale control-plane access and no auth key, so anything that needs a live tailnet is
**Unverified**: real login, peer lists, SSH, herdr and port scans. The Web preview at
https://markbang.github.io/taildeck-ui/ runs on mock data; no row below counts the preview as verification.

## Features

| Feature | Kotlin app | Flutter client | Status | Why |
|---|---|---|---|---|
| tsnet node | In-app node via SagerNet `tsnet`, no VPN slot | Same Go engine as a c-shared library over `dart:ffi` (`native/bridge`), Android and Linux | Unverified | Start/stop/status/logs work in the FFI smoke test; no control plane was reachable, so a real node never came up |
| Login | Browser sign-in, auth key, Headscale control server | Same flows, with a waiting state and an optional control-server field | Unverified | The browser URL and waiting state are implemented; approval could not be completed without a control server |
| Node state, peers, ping | Online, OS, addresses, tags, routes, direct/relay, latency | `td_status` / `td_ping`; last-seen and key-expiry dates localized | Unverified | Rendered from fixtures and screenshots; live peers and ping untested |
| Node list and detail | Grouped list, detail with actions | Self card, per-OS badges, path badge, SSH/Web/Ping actions, details card | Done | UI complete and screenshotted; live values depend on the unverified node |
| SSH sessions | Tailscale SSH, password, built-in key, imported keys, OpenSSH certificates | `td_ssh_dial` + PTY, Tailscale SSH / password / key auth; leaving the terminal keeps the shell, the node resumes or disconnects it | Unverified | Session plumbing and key mapping landed (M2b); no reachable host to dial. The keep-alive buffer is covered by a local test with a fake session |
| SSH auth modes | Includes OpenSSH certificates | Tailscale SSH, password, built-in ed25519 key and imported PEM keys with an optional passphrase | Partial | The ABI carries `certPath`, but the sheet has no certificate picker |
| SSH identities | Built-in key, import, delete | Built-in `id_ed25519` plus imported PEM keys, passphrase stored with metadata, delete | Done | Key creation and import paths tested locally; dialing with them is part of the unverified SSH row |
| SSH login | Editable username, kept with the saved profile | Same, validated, prefilled from the last login for that node/service, then the node's Tailscale user, then `root` | Done | Written to `config.json`; the Linux build read it back after a restart |
| Host-key trust | TOFU, forget trusted hosts | Same, `td_forget_host_keys` | Unverified | No host was ever trusted here |
| Services | Add, edit, delete, grouped by node | `services.json`, add/edit/delete with node, scheme, port, path | Done | Screenshotted; persisted through the native storage layer |
| Port scan | 32 common ports through the node | `td_probe`, same port list | Unverified | Wired to the node; the Web preview says it needs a native build |
| Open a service | In-app WebView or default browser via the gateway | Follows Settings: in-app WebView on Android/iOS, default browser elsewhere, both through `127.0.0.1:18680` | Unverified | The shared `gatewayUrl` and routing are wired and the fallback is screenshotted; the gateway was never exercised |
| 18680 gateway | Loopback forward proxy, per-service origins | Same Go gateway from `bridge/` | Unverified | Reused unchanged, but needs a running node to test |
| In-app WebView | Proxy-override WebView, tailnet hosts through the gateway | `webview_flutter` loading the gateway URL, with back/reload, progress and retry | Partial | Android and iOS only; desktop and web keep the system browser and say so inline. Never run on a device; downloads, file pickers and HTTP auth are not wired |
| Agents list | herdr panes by workspace, states, errors | Real `agent.list` over SSH, workspace sections, state pills, connection card | Partial | Implemented and error states verified; live panes untested |
| Agent chat | Transcript, prompt, restart, model switch, more history | Transcript or screen text, prompt, restart, `/model` and effort picker, paging | Partial | Same gap: no live herdr; see the rows below for what is missing |
| Notifications | Allow / deny / reply from a notification | `flutter_local_notifications` alert when a pane turns `blocked` or `done` while the app is away; tap opens that pane's chat; zh/en toggle in Settings | Partial | Tap-to-open only, no Allow / Deny / Reply actions yet. Built for Android and iOS; delivery and permission prompts are unverified without a device |
| Prompt queues | Queue prompts while an agent works | Holds prompts locally, sends one per settle, cancel or send now | Partial | Queued while the agent works and released on `done`/`idle`; no live herdr to watch it change the agent's turn |
| Subagent transcripts | Open a subagent's call transcript | `td_herdr_subagent` reads the pane session's subagent file, with type, description and finished state | Partial | Claude only and error states only; no live subagent ran |
| Images | Show transcript images and files the agent names | `td_herdr_image` for `img:` refs, thumbnails in the transcript, full-screen zoom view, upload of a picked file via `td_herdr_upload` | Partial | Rendering and the full-screen view are implemented; the composer has no attach button yet, and node paths (not `img:` refs) stay as placeholders |
| Slash commands | Completion for `/` commands | Built-in list per harness plus `/` commands and skills read from the node, ↑↓/Esc, inserts the chosen command | Partial | Popup verified against the built-in list; node commands untested without a node |
| Settings and logs | Tailnet, device, services, SSH keys, logs | Tailnet/device info, service open mode, navigation, tab motion, language, logs page | Done | Screenshotted (M3b, a11y pass) |
| Sign out | Stop and log out the node | `td_logout` with a confirmation | Unverified | Needs a signed-in node |
| Android foreground service | Keeps the node alive when backgrounded | `dataSync` service with a low-importance notification, started when the node reaches `Running` and stopped on stop/sign-out | Unverified | In the merged manifest and the debug APK; no device to confirm the process survives being backgrounded |
| Android network hooks | ConnectivityManager-backed interfaces and DNS | `PlatformBridge.kt` + JNI (`platform_jni.c`), `"platform": "host"` | Done | Landed in #16; builds in CI, not yet run on a device |
| Android system back | Compose back stack; back on the node list leaves the app | One policy in `lib/src/back.dart`: sheets, dialogs and menus pop, then the tab's page, then the first tab, then a second press to leave | Done | `tool/back_android.sh` in `android-smoke` sends real back keys on an emulator and checks each step, the process and the resumed activity |
| Accessibility | Compose semantics | Screen-reader labels, Esc dismissal, reduce motion, text scale clamped to 0.9–1.3 | Done | Landed in #15; screenshots for reduce motion and scale |
| Linux desktop | — | Bundle with both native libraries, run on Xvfb in CI | Done | Added beyond the Kotlin app |
| Windows / macOS | — | Unsigned packages built on a tag or manual run, native DLL/dylib wired | Unverified | Never launched |
| iOS | — | `c-archive` links into the Runner | Unverified | Unsigned package builds; the Runner target force-loads both archives and references `td_start` / `td_term_create`, so a missing archive fails the link. The next macOS CI build has to prove the symbols in the binary |

## Not parity, on purpose

- **Web** is a preview and debug target only; it has no native backend and stays on fixtures.
- **Desktop and iOS** go beyond the Kotlin app, which is Android-only. Their build settings live in
  `.github/workflows/platform-release.yml`.
