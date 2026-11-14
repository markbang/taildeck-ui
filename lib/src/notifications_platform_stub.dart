import 'notifications_platform.dart';

NotificationPlatform openNotificationPlatformImpl() =>
    const _NoNotificationPlatform();

class _NoNotificationPlatform implements NotificationPlatform {
  const _NoNotificationPlatform();

  @override
  bool get supported => false;

  @override
  Future<void> init(void Function(String pane) onPane) async {}

  @override
  Future<String?> launchPane() async => null;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String channelId,
    required String channelName,
    required String channelDescription,
    required String pane,
  }) async {}

  @override
  Future<void> cancelAll() async {}
}
