import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../moviepilot/progress/request_notification.dart';

/// Shows 求片 events as system notifications.
///
/// An interface, not a class the controller talks to: the app wiring decides
/// which sink exists on a platform, and tests pass a no-op. Implementations are
/// expected to swallow nothing — failures are logged by the caller — but must
/// never throw into a poll round.
abstract interface class RequestNotificationSink {
  /// Shows [event] as a system notification.
  Future<void> show(RequestNotification event);

  /// Releases plugin resources.
  Future<void> dispose();
}

/// A sink that does nothing, for tests and for platforms where the plugin is
/// not wired.
class NoopRequestNotificationSink implements RequestNotificationSink {
  const NoopRequestNotificationSink();

  @override
  Future<void> show(RequestNotification event) async {}

  @override
  Future<void> dispose() async {}
}

/// Android / macOS / Windows system notifications via
/// `flutter_local_notifications`.
///
/// The plugin is initialised lazily on the first event, not at startup: an app
/// that never creates a 求片 must not show a notification permission prompt, and
/// a plugin failure must not block `main`.
class LocalRequestNotificationSink implements RequestNotificationSink {
  LocalRequestNotificationSink({
    FlutterLocalNotificationsPlugin? plugin,
    this.onTap,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// Called with the request id when the user taps a notification. The app
  /// turns that into "open 我的求片".
  final void Function(String requestId)? onTap;

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  /// Linux and web are out of scope for this app (contract target: Android,
  /// Windows, macOS); anything else gets the in-app banner only.
  static bool get isSupportedPlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows;
  }

  static const String _channelId = 'request_progress';
  static const String _channelName = '求片进度';
  static const String _channelDescription = '求片入库或需要注意时的提醒';

  @override
  Future<void> show(RequestNotification event) async {
    if (!isSupportedPlatform) return;
    await _ensureInitialized();
    await _plugin.show(
      id: event.dedupeKey.hashCode & 0x7fffffff,
      title: event.title,
      body: event.body,
      notificationDetails: _details,
      payload: event.requestId,
    );
  }

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
    ),
    macOS: DarwinNotificationDetails(),
    windows: WindowsNotificationDetails(),
  );

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    final InitializationSettings settings = switch (defaultTargetPlatform) {
      TargetPlatform.android => const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      TargetPlatform.macOS => const InitializationSettings(
        macOS: DarwinInitializationSettings(
          // Asked for on the first notification instead, see [requestPermission].
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      TargetPlatform.windows => const InitializationSettings(
        windows: WindowsInitializationSettings(
          appName: 'Media Player',
          appUserModelId: 'cn.sakuralovesmile.mediaplayer',
          guid: 'b0f4d8bb-0f0b-4f2c-9a2f-6a1c0f3f4d61',
        ),
      ),
      _ => const InitializationSettings(),
    };
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final requestId = response.payload;
        if (requestId != null && requestId.isNotEmpty) onTap?.call(requestId);
      },
    );
    _initialized = true;
  }

  /// Asks the OS for notification permission. Called from the settings toggle,
  /// i.e. only in response to a deliberate user action.
  Future<bool> requestPermission() async {
    if (!isSupportedPlatform) return false;
    await _ensureInitialized();
    return switch (defaultTargetPlatform) {
      TargetPlatform.android =>
        await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.requestNotificationsPermission() ??
            false,
      TargetPlatform.macOS =>
        await _plugin
                .resolvePlatformSpecificImplementation<
                  MacOSFlutterLocalNotificationsPlugin
                >()
                ?.requestPermissions(alert: true, badge: true, sound: true) ??
            false,
      // Windows has no permission prompt: toast notifications need no consent.
      _ => true,
    };
  }

  @override
  Future<void> dispose() async {}
}
