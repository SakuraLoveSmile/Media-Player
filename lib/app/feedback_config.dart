import 'package:feedback_widget/feedback_widget.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Compile-time feedback wiring, injected with `--dart-define`.
///
/// * `FEEDBACK_ENABLED` — master gate. When it is unset the layer is enabled
///   for release/profile builds and disabled for debug builds and `flutter
///   test`, so day-to-day dev runs and the existing widget-test suite stay
///   unaffected unless feedback is explicitly requested.
/// * `FEEDBACK_API_BASE` — Feedback service base URL (defaults to production).
/// * `FEEDBACK_APP_ID` — the appId registered on the Feedback service for
///   Media Player.
/// * `FEEDBACK_APP_NAME` — display name reported with submissions. The service
///   only adopts it while no admin-set name exists for the appId
///   (Feedback >= 0.4.0; ignored by older servers).
///
/// Only these four values are read here. The client never touches AI/Kaneo
/// admin secrets: it knows the service base URL, the appId, and — after the
/// in-panel login — its own token (stored under a key derived from apiBase +
/// appId, fully isolated from the Emby credentials in `data/storage`).
class FeedbackBuildConfig {
  const FeedbackBuildConfig._();

  /// Production Feedback service address (punycode form of the IDN domain).
  static const String defaultApiBase = 'https://feedback.xn--fhqths51enha.cn';

  /// appId registered on the Feedback service for this app.
  static const String defaultAppId = 'dev.mediaplayer.media_player';

  /// Display name reported alongside submissions (matches the app title).
  static const String defaultAppName = 'Media Player';

  static const String _enabledRaw = String.fromEnvironment('FEEDBACK_ENABLED');
  static const String _apiBaseRaw = String.fromEnvironment('FEEDBACK_API_BASE');
  static const String _appIdRaw = String.fromEnvironment('FEEDBACK_APP_ID');
  static const String _appNameRaw = String.fromEnvironment('FEEDBACK_APP_NAME');

  /// Whether the feedback layer is mounted. Defaults to on for official builds.
  static bool get enabled => _enabledRaw.isEmpty
      ? !kDebugMode
      : (_enabledRaw == 'true' || _enabledRaw == '1');

  static String get apiBase =>
      _apiBaseRaw.isEmpty ? defaultApiBase : _apiBaseRaw;

  static String get appId => _appIdRaw.isEmpty ? defaultAppId : _appIdRaw;

  static String get appName =>
      _appNameRaw.isEmpty ? defaultAppName : _appNameRaw;
}

/// Runtime service identity handed to `FeedbackWidget`. `null` means the
/// feedback layer is off (do not mount it, do not show host entry points).
class FeedbackServiceConfig {
  const FeedbackServiceConfig({
    required this.apiBase,
    required this.appId,
    this.appName,
  });

  final String apiBase;
  final String appId;

  /// Optional display name reported with submissions (Feedback >= 0.4.0).
  final String? appName;
}

/// Resolves the service identity from the build config. Tests override this
/// provider to enable feedback against an isolated address, or to force it off.
final feedbackServiceConfigProvider = Provider<FeedbackServiceConfig?>((ref) {
  if (!FeedbackBuildConfig.enabled) return null;
  return FeedbackServiceConfig(
    apiBase: FeedbackBuildConfig.apiBase,
    appId: FeedbackBuildConfig.appId,
    appName: FeedbackBuildConfig.appName,
  );
});

/// The single, root-owned controller shared by the floating entry and any host
/// UI that opens the same capture flow. Disposed with the root
/// [ProviderContainer], never by a page.
final feedbackControllerProvider = Provider<FeedbackController>((ref) {
  final FeedbackController controller = FeedbackController();
  ref.onDispose(controller.dispose);
  return controller;
});

/// Page categories that may be reported as `pageLabel`. Anything outside this
/// allow-list collapses to `other`, so a route id, query parameter or server
/// address can never leak into the feedback metadata.
const Set<String> _pageCategories = <String>{
  'startup',
  'login',
  'library',
  'player',
  'series',
  'settings',
};

/// Reduces a router location to a coarse, non-sensitive page category.
///
/// Only the first non-empty path segment is considered, and it must be a known
/// category: ids (`/player/42`), sub-paths and query parameters
/// (`/player/42?server=...`) are all dropped. The root route is `startup`;
/// anything unknown becomes `other`.
String feedbackPageLabelFromUri(Uri uri) {
  for (final String segment in uri.pathSegments) {
    if (segment.isEmpty) continue;
    return _pageCategories.contains(segment) ? segment : 'other';
  }
  return 'startup';
}

/// Builds the immutable `FeedbackConfig` for the current runtime state.
///
/// Fixed choices: right-side floating orb, viewport capture on invoke, light
/// theme (the app is light-only), and an initial bottom offset that clears the
/// mobile bottom navigation. [showLauncher] is exposed so the host can hide the
/// built-in entry on the player page while keeping the panel reachable through
/// the shared controller.
FeedbackConfig buildFeedbackConfig({
  required FeedbackServiceConfig service,
  required String pageLabel,
  String? appVersion,
  bool showLauncher = true,
}) {
  return FeedbackConfig(
    service.apiBase,
    service.appId,
    appName: service.appName,
    appVersion: appVersion,
    pageLabel: pageLabel,
    side: FeedbackSide.right,
    theme: FeedbackThemeMode.light,
    // Explicit: orb launcher + capture the current viewport on invoke. The
    // package defaults are `tab` / `off`, so these must be stated.
    launcherMode: FeedbackLauncherMode.orb,
    captureMode: FeedbackCaptureMode.viewport,
    // 30% up the right edge keeps the orb clear of the bottom navigation bar;
    // it remains draggable to anywhere else.
    launcherBottom: '30%',
    showLauncher: showLauncher,
  );
}
