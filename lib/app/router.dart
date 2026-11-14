import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/router/app_page.dart';
import '../core/router/app_routes.dart';
import '../features/admin/admin_page.dart';
import '../features/browse/browse_pages.dart';
import '../features/detail/detail_page.dart';
import '../features/favorites/favorites_page.dart';
import '../features/home/home_page.dart';
import '../features/library/library_page.dart';
import '../features/livetv/live_tv_page.dart';
import '../features/login/login_page.dart';
import '../features/player/player_page.dart';
import '../features/request/my_requests_page.dart';
import '../features/request/request_page.dart';
import '../features/search/search_page.dart';
import '../features/series/season_page.dart';
import '../features/series/series_page.dart';
import '../features/servers/servers_page.dart';
import '../features/settings/cache_settings_page.dart';
import '../features/settings/danmaku_settings_page.dart';
import '../features/settings/library_visibility_page.dart';
import '../features/settings/mpv_settings_page.dart';
import '../features/settings/appearance_page.dart';
import '../features/settings/player_settings_page.dart';
import '../features/settings/screenshot_settings_page.dart';
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
///
/// Every route declares its page through [appPage]: go_router's own default
/// would be a `NoTransitionPage` here (see that helper), which turns
/// navigation into a hard cut and skips the app-wide cross-fade (S79).
final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    navigatorKey: appRootNavigatorKey,
    initialLocation: AppRoutes.startup,
    routes: [
      GoRoute(
        path: AppRoutes.startup,
        pageBuilder: (context, state) => appPage(state, const StartupPage()),
      ),
      GoRoute(
        path: AppRoutes.login,
        pageBuilder: (context, state) => appPage(
          state,
          LoginPage(
            // Key by target so switching to a different server (or 添加) builds
            // a fresh form instead of reusing the previous login state.
            key: ValueKey<String>('login:${state.uri.query}'),
            serverId: state.uri.queryParameters['server'],
            addMode: state.uri.queryParameters['add'] == '1',
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.home,
        pageBuilder: (context, state) => appPage(state, const HomePage()),
      ),
      GoRoute(
        path: AppRoutes.library,
        pageBuilder: (context, state) => appPage(
          state,
          LibraryPage(
            initialViewId: state.uri.queryParameters['view'],
            initialGenre: state.uri.queryParameters['genre'],
            initialStudioId: state.uri.queryParameters['studio'],
            initialStudioName: state.uri.queryParameters['studioName'],
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.search,
        pageBuilder: (context, state) => appPage(state, const SearchPage()),
      ),
      GoRoute(
        path: AppRoutes.favorites,
        pageBuilder: (context, state) => appPage(state, const FavoritesPage()),
      ),
      GoRoute(
        path: AppRoutes.liveTv,
        pageBuilder: (context, state) => appPage(state, const LiveTvPage()),
      ),
      GoRoute(
        path: '${AppRoutes.person}/:personId',
        pageBuilder: (context, state) => appPage(
          state,
          PersonPage(
            personId: state.pathParameters['personId'] ?? '',
            name: state.uri.queryParameters['name'],
          ),
        ),
      ),
      GoRoute(
        path: '${AppRoutes.collection}/:collectionId',
        pageBuilder: (context, state) => appPage(
          state,
          CollectionPage(
            collectionId: state.pathParameters['collectionId'] ?? '',
            name: state.uri.queryParameters['name'],
          ),
        ),
      ),
      GoRoute(
        path: '${AppRoutes.series}/:seriesId',
        pageBuilder: (context, state) => appPage(
          state,
          SeriesPage(seriesId: state.pathParameters['seriesId'] ?? ''),
        ),
      ),
      GoRoute(
        path: '${AppRoutes.season}/:seasonId',
        pageBuilder: (context, state) => appPage(
          state,
          SeasonPage(
            seasonId: state.pathParameters['seasonId'] ?? '',
            seriesId: state.uri.queryParameters['series'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '${AppRoutes.detail}/:itemId',
        pageBuilder: (context, state) => appPage(
          state,
          DetailPage(itemId: state.pathParameters['itemId'] ?? ''),
        ),
      ),
      GoRoute(
        path: '${AppRoutes.player}/:itemId',
        pageBuilder: (context, state) => appPage(
          state,
          PlayerPage(
            itemId: state.pathParameters['itemId'] ?? '',
            preferredSourceId: state.uri.queryParameters['source'],
            // S78: continuous play forwards the current playback mode, so a new
            // episode route opens in the same orientation instead of landscape.
            initialPortrait: state.uri.queryParameters['portrait'] == '1',
            initialAudioIndex: int.tryParse(
              state.uri.queryParameters['audio'] ?? '',
            ),
            initialSubtitleIndex: int.tryParse(
              state.uri.queryParameters['subtitle'] ?? '',
            ),
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.request,
        pageBuilder: (context, state) => appPage(state, const RequestPage()),
        routes: <RouteBase>[
          GoRoute(
            path: 'mine',
            pageBuilder: (context, state) =>
                appPage(state, const MyRequestsPage()),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.settings,
        pageBuilder: (context, state) => appPage(state, const SettingsPage()),
      ),
      GoRoute(
        path: AppRoutes.settingsCache,
        pageBuilder: (context, state) =>
            appPage(state, const CacheSettingsPage()),
      ),
      GoRoute(
        path: AppRoutes.settingsPlayer,
        pageBuilder: (context, state) =>
            appPage(state, const PlayerSettingsPage()),
      ),
      GoRoute(
        path: AppRoutes.settingsAppearance,
        pageBuilder: (context, state) => appPage(state, const AppearancePage()),
      ),
      GoRoute(
        path: AppRoutes.settingsScreenshot,
        pageBuilder: (context, state) =>
            appPage(state, const ScreenshotSettingsPage()),
      ),
      GoRoute(
        path: AppRoutes.settingsDanmaku,
        pageBuilder: (context, state) =>
            appPage(state, const DanmakuSettingsPage()),
      ),
      GoRoute(
        path: AppRoutes.settingsMpv,
        pageBuilder: (context, state) => appPage(state, const MpvSettingsPage()),
      ),
      GoRoute(
        path: AppRoutes.settingsLibraries,
        pageBuilder: (context, state) =>
            appPage(state, const LibraryVisibilityPage()),
      ),
      GoRoute(
        path: AppRoutes.servers,
        pageBuilder: (context, state) => appPage(state, const ServersPage()),
      ),
      GoRoute(
        path: AppRoutes.admin,
        pageBuilder: (context, state) => appPage(state, const AdminPage()),
      ),
    ],
  );

  ref.onDispose(router.dispose);
  return router;
});
