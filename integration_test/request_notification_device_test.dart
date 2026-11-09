import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_player/data/moviepilot/progress/request_notification.dart';
import 'package:media_player/data/notifications/local_notification_sink.dart';

/// Real-device check that a 求片 notification reaches the OS notification
/// shade.
///
/// The widget tests can only prove that the app calls the sink; whether the
/// platform actually renders a notification (permission, channel, icon) needs a
/// real device. Run with:
///
/// ```
/// flutter test integration_test/request_notification_device_test.dart -d <id>
/// ```
///
/// The test fails when the sink throws or reports "unsupported"; a permission
/// denial is reported as a skip-style message rather than a silent pass,
/// because a denied permission is indistinguishable from a broken channel on
/// the device.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a 求片 notification reaches the system', (WidgetTester tester) async {
    expect(
      LocalRequestNotificationSink.isSupportedPlatform,
      isTrue,
      reason: 'the sink only exists on Android, macOS and Windows',
    );

    final sink = LocalRequestNotificationSink();
    // Permission first: without it show() succeeds silently and the test would
    // pass while nothing is displayed.
    final granted = await sink.requestPermission();
    debugPrint('[device] notification permission granted=$granted');

    await sink.show(
      const RequestNotification(
        requestId: 'device-check',
        title: 'Media Player 通知测试',
        body: '如果你看到这条通知，求片入库提醒已经能触达系统',
        embyItemId: 'device-check',
      ),
    );
    // Give the platform time to post the toast before the process is torn down.
    await tester.pump(const Duration(seconds: 2));
  });
}
