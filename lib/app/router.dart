import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/router/app_routes.dart';
import '../features/library/library_page.dart';
import '../features/login/login_page.dart';
import '../features/player/player_page.dart';
import '../features/request/request_page.dart';
import '../features/series/series_page.dart';
import '../features/settings/settings_page.dart';
import '../features/startup/startup_page.dart';

/// Root navigator of the app (inside the feedback layer). Root-level dialogs
/// such as the update prompt use this context so they stay inside the capture
/// boundary and below the feedback panel.
final GlobalKey<NavigatorState> appRootNavigatorKey =
    GlobalKey<NavigatorState>();

/// Single place where features are wired into navigation.
///
/// Route paths live in `core/router/app_routes.dart` so that features can
/// reference them without importing the router (and creating a cycle).
final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    navigatorKey: appRootNavigatorKey,
    initialLocation: AppRoutes.startup,
    routes: [
      GoRoute(
        path: AppRoutes.startup,
        builder: (context, state) => const StartupPage(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: AppRoutes.library,
        builder: (context, state) => const LibraryPage(),
      ),
      GoRoute(
        path: '${AppRoutes.series}/:seriesId',
        builder: (context, state) =>
            SeriesPage(seriesId: state.pathParameters['seriesId'] ?? ''),
      ),
      GoRoute(
        path: '${AppRoutes.player}/:itemId',
        builder: (context, state) =>
            PlayerPage(itemId: state.pathParameters['itemId'] ?? ''),
      ),
      GoRoute(
        path: AppRoutes.request,
        builder: (context, state) => const RequestPage(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsPage(),
      ),
    ],
  );

  ref.onDispose(router.dispose);
  return router;
});
