import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notifications_platform.dart';

NotificationPlatform openNotificationPlatformImpl() =>
    _LocalNotificationPlatform();

/// Android and iOS; every other desktop target stays quiet.
class _LocalNotificationPlatform implements NotificationPlatform {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  bool get _mobile => Platform.isAndroid || Platform.isIOS;

  @override
  bool get supported => _mobile;

  @override
  Future<void> init(void Function(String pane) onPane) async {
    if (!_mobile) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_taildeck'),
        // Permission is requested when the toggle is turned on, not at launch.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final pane = response.payload;
        if (pane != null && pane.isNotEmpty) onPane(pane);
      },
    );
    _initialized = true;
  }

  @override
  Future<String?> launchPane() async {
    if (!_mobile || !_initialized) return null;
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;
    final pane = details.notificationResponse?.payload;
    return pane == null || pane.isEmpty ? null : pane;
  }

  @override
  Future<bool> requestPermission() async {
    if (!_mobile || !_initialized) return false;
    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    return await ios?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ??
        false;
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String channelId,
    required String channelName,
    required String channelDescription,
    required String pane,
  }) async {
    if (!_mobile || !_initialized) return;
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.message,
            icon: 'ic_stat_taildeck',
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: false,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: pane,
      );
    } on PlatformException catch (error) {
      debugPrint('taildeck: notification failed: ${error.message}');
    }
  }

  @override
  Future<void> cancelAll() async {
    if (!_mobile || !_initialized) return;
    await _plugin.cancelAll();
  }
}
