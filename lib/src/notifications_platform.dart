import 'notifications_platform_stub.dart'
    if (dart.library.io) 'notifications_platform_io.dart';

/// What a local-notification backend has to provide; the stub is used on web.
abstract class NotificationPlatform {
  bool get supported;

  /// Initialises the plugin and routes taps to [onPane].
  Future<void> init(void Function(String pane) onPane);

  /// The pane a notification launched the app with, when it did.
  Future<String?> launchPane();

  Future<bool> requestPermission();

  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String channelId,
    required String channelName,
    required String channelDescription,
    required String pane,
  });

  Future<void> cancelAll();
}

NotificationPlatform openNotificationPlatform() =>
    openNotificationPlatformImpl();
