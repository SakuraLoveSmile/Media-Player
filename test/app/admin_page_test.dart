import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:media_player/app/admin_providers.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/emby_exception.dart';
import 'package:media_player/core/router/app_routes.dart';
import 'package:media_player/data/models/admin_info.dart';
import 'package:media_player/features/admin/admin_page.dart';

import '../support/fake_admin_service.dart';

ThemeData _appTheme() =>
    ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF3F51B5));

void main() {
  late FakeAdminService service;

  setUp(() {
    service = FakeAdminService(
      systemInfo: const AdminSystemInfo(
        serverName: 'NAS',
        version: '4.9.0.50',
        operatingSystem: 'Linux',
        hasPendingRestart: true,
      ),
      userList: <AdminUser>[
        AdminUser(
          id: 'u-1',
          name: 'alice',
          isAdministrator: true,
          lastLoginDate: DateTime.utc(2026, 11, 20, 8, 30),
        ),
        const AdminUser(id: 'u-2', name: 'bob'),
      ],
      sessionList: <AdminSessionInfo>[
        const AdminSessionInfo(
          userName: 'alice',
          client: 'Yamby',
          deviceName: 'Pixel 9',
          nowPlayingName: 'Dune',
          positionTicks: 600000000,
        ),
        const AdminSessionInfo(
          userName: 'bob',
          client: 'Emby Web',
          deviceName: 'Chrome',
        ),
      ],
    );
  });

  /// Pumps the real route, so direct navigation by any session is exercised.
  /// The admin page is pushed on top of '/' exactly like the settings entry
  /// does, so 返回 has somewhere to pop to.
  Future<void> pumpAdmin(WidgetTester tester) async {
    // Three sections plus rows need more than the default 600pt window.
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final GoRouter router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: AppRoutes.admin,
          builder: (context, state) => const AdminPage(),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [adminServiceProvider.overrideWith((ref) async => service)],
        child: MaterialApp.router(theme: _appTheme(), routerConfig: router),
      ),
    );
    router.push(AppRoutes.admin);
    await tester.pumpAndSettle();
  }

  testWidgets('an admin sees the server info, users and sessions sections', (
    tester,
  ) async {
    await pumpAdmin(tester);

    expect(find.text('服务器管理'), findsOneWidget);
    expect(find.text('服务器信息'), findsOneWidget);
    expect(find.text('NAS'), findsOneWidget);
    expect(find.text('4.9.0.50'), findsOneWidget);
    expect(find.text('Linux'), findsOneWidget);
    expect(find.text('服务器有等待重启的更新'), findsOneWidget);

    expect(find.text('用户'), findsOneWidget);
    expect(find.text('alice'), findsWidgets);
    expect(find.text('bob'), findsWidgets);
    // Only alice carries the admin badge; bob never logged in.
    expect(find.text('管理员'), findsOneWidget);
    expect(find.textContaining('上次登录：'), findsOneWidget);
    expect(find.text('从未登录'), findsOneWidget);

    expect(find.text('活跃会话'), findsOneWidget);
  });

  testWidgets('sessions render the device and the now-playing position', (
    tester,
  ) async {
    await pumpAdmin(tester);

    expect(find.text('Yamby · Pixel 9'), findsOneWidget);
    // 600000000 ticks = 60 seconds.
    expect(find.text('正在播放：Dune · 01:00'), findsOneWidget);
    expect(find.text('Emby Web · Chrome'), findsOneWidget);
    expect(find.text('空闲'), findsOneWidget);
  });

  testWidgets('a non-admin reaching the route directly sees 无权限', (
    tester,
  ) async {
    service.admin = false;
    await pumpAdmin(tester);

    expect(find.byKey(const Key('admin-forbidden')), findsOneWidget);
    expect(find.text('无权限'), findsOneWidget);
    expect(find.text('仅管理员可以访问服务器管理'), findsOneWidget);
    expect(find.text('服务器信息'), findsNothing);
    expect(find.text('用户'), findsNothing);
    expect(find.text('活跃会话'), findsNothing);
    // The gate must stop before any admin data is requested.
    expect(service.systemInfoCalls, 0);
    expect(service.usersCalls, 0);
    expect(service.sessionsCalls, 0);
  });

  testWidgets('a load failure shows the error and retry recovers', (
    tester,
  ) async {
    service.failure = EmbyException(AppErrorCode.networkUnreachable);
    await pumpAdmin(tester);

    expect(find.byKey(const Key('admin-error')), findsOneWidget);
    expect(find.text('无法连接服务器，请检查网络'), findsOneWidget);

    service.failure = null;
    await tester.tap(find.byKey(const Key('admin-retry')));
    await tester.pumpAndSettle();

    expect(find.text('服务器信息'), findsOneWidget);
    expect(find.text('NAS'), findsOneWidget);
  });

  testWidgets('the refresh action reloads the snapshot', (tester) async {
    await pumpAdmin(tester);
    expect(service.isAdminCalls, 1);

    await tester.tap(find.byKey(const Key('admin-refresh')));
    await tester.pumpAndSettle();

    expect(service.isAdminCalls, 2);
    expect(service.systemInfoCalls, 2);
  });

  testWidgets('back pops to the previous route', (tester) async {
    await pumpAdmin(tester);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();

    expect(find.text('home'), findsOneWidget);
    expect(find.text('服务器管理'), findsNothing);
  });
}
