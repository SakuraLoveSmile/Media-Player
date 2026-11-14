import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/request_notification_banner.dart';
import 'package:media_player/data/moviepilot/progress/request_notification.dart';
import 'package:media_player/ui/theme/app_theme.dart';

const RequestNotification _event = RequestNotification(
  requestId: 'req-1',
  title: '沙丘 2',
  body: '第 2 季 已入库，可以播放',
  embyItemId: 'emby-7',
  isSeries: true,
);

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: buildAppTheme(Brightness.light),
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('renders the title and the body copy', (tester) async {
    await tester.pumpWidget(
      _wrap(
        RequestNotificationBanner(
          event: _event,
          onTap: () {},
          onDismiss: () {},
        ),
      ),
    );

    expect(find.text('沙丘 2'), findsOneWidget);
    expect(find.text('第 2 季 已入库，可以播放'), findsOneWidget);
  });

  testWidgets('the open action and the dismiss action both fire', (
    tester,
  ) async {
    var opened = 0;
    var dismissed = 0;
    await tester.pumpWidget(
      _wrap(
        RequestNotificationBanner(
          event: _event,
          onTap: () => opened++,
          onDismiss: () => dismissed++,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('request-banner-open')));
    await tester.tap(find.byKey(const Key('request-banner-dismiss')));

    expect(opened, 1);
    expect(dismissed, 1);
  });

  testWidgets('a long title is truncated instead of overflowing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _wrap(
        RequestNotificationBanner(
          event: const RequestNotification(
            requestId: 'req-1',
            title: '一个非常非常长的电影标题用来检查布局不会溢出屏幕边界',
            body: '已入库，可以播放',
          ),
          onTap: () {},
          onDismiss: () {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('request-banner-title')), findsOneWidget);
  });
}
