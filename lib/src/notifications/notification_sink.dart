import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Platform notifications for incoming messages; overridden in tests.
abstract class NotificationSink {
  Future<void> showMessage({
    required String chatRef,
    required String title,
    required String body,
  });
}

final notificationSinkProvider = Provider<NotificationSink>(
  (ref) => LocalNotificationSink(),
);

/// Mirrors Telegram's local message notifications: one channel, high
/// importance, the chat name as the title and the preview as the body.
class LocalNotificationSink implements NotificationSink {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _ready;

  Future<void> _initialize() {
    return _ready ??= () async {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        linux: LinuxInitializationSettings(defaultActionName: 'Open'),
      );
      await _plugin.initialize(settings: settings);
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }().catchError((Object error) {
      // CI and desktops without a notification daemon must not crash the app.
      if (kDebugMode) {
        debugPrint('[Tanglex] notification init failed: $error');
      }
    });
  }

  @override
  Future<void> showMessage({
    required String chatRef,
    required String title,
    required String body,
  }) async {
    await _initialize();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'messages',
        'Messages',
        channelDescription: 'New SimpleX messages',
        importance: Importance.high,
        priority: Priority.high,
      ),
      linux: LinuxNotificationDetails(),
    );
    await _plugin.show(
      id: chatRef.hashCode & 0x7fffffff,
      title: title,
      body: body,
      notificationDetails: details,
      payload: chatRef,
    );
  }
}
