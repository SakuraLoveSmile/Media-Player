import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/router/app_routes.dart';
import '../features/library/library_page.dart';
import '../features/login/login_page.dart';
import '../features/player/player_page.dart';
import '../features/startup/startup_page.dart';

/// Single place where features are wired into navigation.
///
/// Route paths live in `core/router/app_routes.dart` so that features can
/// reference them without importing the router (and creating a cycle).
final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
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
        path: '${AppRoutes.player}/:itemId',
        builder: (context, state) =>
            PlayerPage(itemId: state.pathParameters['itemId'] ?? ''),
      ),
    ],
  );

  ref.onDispose(router.dispose);
  return router;
});
