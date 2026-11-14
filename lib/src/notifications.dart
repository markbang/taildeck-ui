import 'dart:async';

import 'package:flutter/foundation.dart';

import 'herdr.dart';
import 'notifications_platform.dart';
import 'preview_env.dart';

/// Local alerts for agents that need attention; the notification carries the
/// pane id so a tap can open that agent's chat.
class AgentNotifications extends ChangeNotifier {
  AgentNotifications([NotificationPlatform? platform])
    : _platform = platform ?? openNotificationPlatform();

  static const channelId = 'agents';

  final NotificationPlatform _platform;

  /// `?notify=1` on the preview build: the toggle is shown on, since the
  /// plugin is not linked on that host.
  final bool _preview = previewParam('notify') == '1';
  bool _enabled = false;
  bool _denied = false;
  bool _failed = false;
  bool _zh = false;
  String? _pending;

  /// False on web and on a host whose plugin is not linked.
  bool get supported => _preview || (_platform.supported && !_failed);
  bool get enabled => _enabled;

  /// The last permission request was refused; the settings page says why.
  bool get denied => _denied;

  Future<void> init() async {
    if (_preview) {
      _enabled = true;
      return;
    }
    if (!supported) return;
    try {
      await _platform.init(_tap);
      _pending ??= await _platform.launchPane();
    } on Object catch (error) {
      _failed = true;
      debugPrint('taildeck: notifications unavailable: $error');
    }
  }

  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (value) _denied = false;
    notifyListeners();
    if (!value) unawaited(_platform.cancelAll());
  }

  Future<bool> requestPermission() async {
    if (!supported) return false;
    bool granted;
    try {
      granted = await _platform.requestPermission();
    } on Object catch (error) {
      debugPrint('taildeck: notification permission failed: $error');
      granted = false;
    }
    _denied = !granted;
    notifyListeners();
    return granted;
  }

  /// The language the notification text is written in.
  void setLanguage(String code) => _zh = code == 'zh';

  /// A pane a tapped notification asked for; the shell clears this.
  String? takePendingPane() {
    final pane = _pending;
    _pending = null;
    return pane;
  }

  /// Posts one alert per pane; a later state replaces the earlier alert.
  Future<void> show(HerdrAgent agent, {required bool needsInput}) async {
    if (!supported || !_enabled) return;
    final project = agent.workspace.isEmpty ? 'herdr' : agent.workspace;
    final status = needsInput
        ? (_zh ? '需要你处理' : 'Needs you')
        : (_zh ? '已完成' : 'Finished');
    final body = [
      status,
      if (agent.kind.isNotEmpty) agent.kind,
      if (agent.title.isNotEmpty) agent.title,
    ].join(' · ');
    try {
      await _platform.show(
        id: agent.paneId.hashCode & 0x7fffffff,
        title: '${agent.label} · $project',
        body: body,
        channelId: channelId,
        channelName: _zh ? '代理通知' : 'Agent notifications',
        channelDescription: _zh
            ? '代理需要你或完成任务时提醒'
            : 'Alerts when an agent needs you or finishes',
        pane: agent.paneId,
      );
    } on Object catch (error) {
      debugPrint('taildeck: notification failed: $error');
    }
  }

  void _tap(String pane) {
    _pending = pane;
    notifyListeners();
  }
}
