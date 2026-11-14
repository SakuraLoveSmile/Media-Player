import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:feedback_widget/feedback_widget.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/config/app_config.dart';
import '../core/router/app_routes.dart';
import '../data/moviepilot/progress/request_notification.dart';
import '../data/notifications/local_notification_sink.dart';
import '../ui/theme/app_theme.dart';
import '../features/request/request_controller.dart';
import '../features/settings/update_dialog.dart';
import 'accent_settings.dart';
import 'feedback_config.dart';
import 'feedback_layer.dart';
import 'feedback_orb_settings.dart';
import 'moviepilot_providers.dart';
import 'request_notification_banner.dart';
import 'request_notification_settings.dart';
import 'router.dart';
import 'theme_mode_settings.dart';
import 'update_providers.dart';

class MediaPlayerApp extends ConsumerStatefulWidget {
  const MediaPlayerApp({super.key});

  @override
  ConsumerState<MediaPlayerApp> createState() => _MediaPlayerAppState();
}

class _MediaPlayerAppState extends ConsumerState<MediaPlayerApp>
    with WidgetsBindingObserver {
  // Root-owned feedback wiring: the controller and outer navigator key are
  // created once so the feedback session (draft + login token) survives
  // navigation.
  final GlobalKey<NavigatorState> _feedbackNavigatorKey =
      GlobalKey<NavigatorState>();
  final ValueNotifier<String> _feedbackPageLabel = ValueNotifier<String>(
    'startup',
  );
  late final FeedbackController _feedbackController;
  GoRouter? _router;
  bool _updateDialogOpen = false;

  /// Only the silent startup check may auto-open the update dialog. Manual
  /// checks from the settings page open it themselves, so a shared trigger
  /// would stack two dialogs.
  bool _autoPromptUpdates = false;

  /// 求片 notifications. The controller is the app-wide one (both 求片 pages
  /// share it), so subscribing here is what makes a request finishing on an
  /// unrelated page still reach the user.
  RequestController? _requestController;
  void Function()? _unsubscribeRequest;
  LocalRequestNotificationSink? _systemNotifications;
  final ValueNotifier<RequestNotification?> _banner =
      ValueNotifier<RequestNotification?>(null);
  Timer? _bannerTimer;

  /// How long the in-app banner stays up before dismissing itself.
  static const Duration _bannerDuration = Duration(seconds: 6);

  @override
  void initState() {
    super.initState();
    // Registered before the router exists so this observer is consulted first:
    // Android back must close the feedback panel before GoRouter pops a route.
    WidgetsBinding.instance.addObserver(this);
    _feedbackController = ref.read(feedbackControllerProvider);
    _router = ref.read(appRouterProvider);
    _router!.routerDelegate.addListener(_onRouteChanged);
    _syncFeedbackPageLabel();
    _attachRequestNotifications();

    // Silent startup check; failures are invisible and never block the app.
    // Skipped in debug/tests so local runs and widget tests stay deterministic.
    if (!kDebugMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _autoPromptUpdates = true;
        ref.read(updateControllerProvider.notifier).check(silent: true);
      });
    }
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_onRouteChanged);
    WidgetsBinding.instance.removeObserver(this);
    _unsubscribeRequest?.call();
    _bannerTimer?.cancel();
    _banner.dispose();
    unawaited(_systemNotifications?.dispose());
    _feedbackPageLabel.dispose();
    super.dispose();
  }

  /// Subscribes to the app-wide 求片 controller.
  ///
  /// The controller provider resolves asynchronously (it reads storage first),
  /// so this listens rather than reads; a failed resolution (no storage, no
  /// MoviePilot configuration) simply leaves notifications off.
  void _attachRequestNotifications() {
    ref.listenManual<AsyncValue<RequestController?>>(
      requestControllerProvider,
      (_, AsyncValue<RequestController?> next) =>
          _bindRequestController(next.value),
      fireImmediately: true,
    );
  }

  void _bindRequestController(RequestController? controller) {
    if (identical(controller, _requestController)) return;
    _unsubscribeRequest?.call();
    _unsubscribeRequest = null;
    _requestController = controller;
    if (controller == null) return;

    final sink = LocalRequestNotificationSink(
      onTap: (String requestId) => _openMyRequests(),
    );
    _systemNotifications = sink;
    _unsubscribeRequest = controller.addNotificationListener((event) {
      unawaited(_deliver(event, sink));
    });
    // Ask for a round now: the controller may have restored a list whose
    // requests finished while the app was closed.
    unawaited(controller.startWatching());
  }

  /// Hands one event to the channels the user left enabled.
  Future<void> _deliver(
    RequestNotification event,
    LocalRequestNotificationSink sink,
  ) async {
    final RequestNotificationSettings settings =
        ref.read(requestNotificationSettingsProvider).value ??
        RequestNotificationSettings.defaults;
    if (settings.system) {
      try {
        await sink.show(event);
      } catch (error) {
        // A denied permission or a missing platform hook must never break the
        // poll; the in-app banner below is the fallback.
        debugPrint('[request] 系统通知失败：$error');
      }
    }
    if (!settings.inApp || !mounted) return;
    _bannerTimer?.cancel();
    _banner.value = event;
    _bannerTimer = Timer(_bannerDuration, _dismissBanner);
  }

  void _dismissBanner() {
    _bannerTimer?.cancel();
    _bannerTimer = null;
    _banner.value = null;
  }

  void _openMyRequests() {
    _dismissBanner();
    final router = _router;
    if (router == null) return;
    router.push(AppRoutes.myRequests);
  }

  /// Android back / system pop: close the feedback panel before normal
  /// navigation handles the event.
  @override
  Future<bool> didPopRoute() async => handleFeedbackBackPop(
    navigatorKey: _feedbackNavigatorKey,
    controller: _feedbackController,
  );

  void _onRouteChanged() {
    // The delegate notifies during the router's notify phase; defer the
    // ValueNotifier write so it never triggers a rebuild during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncFeedbackPageLabel();
    });
  }

  void _syncFeedbackPageLabel() {
    final router = _router;
    if (router == null) return;
    _feedbackPageLabel.value = feedbackPageLabelFromUri(
      router.routerDelegate.currentConfiguration.uri,
    );
  }

  @override
  Widget build(BuildContext context) {
    // A release newer than this build opens the update dialog once. The
    // settings page uses the same controller for manual checks.
    ref.listen<UpdateState>(updateControllerProvider, (_, next) {
      if (!_autoPromptUpdates) return;
      // Keep waiting while the startup check is still running; any terminal
      // state consumes the one-shot auto-prompt.
      if (next.status == UpdateStatus.checking) return;
      _autoPromptUpdates = false;
      if (next.status != UpdateStatus.available ||
          next.release == null ||
          _updateDialogOpen) {
        return;
      }
      final navigatorContext = appRootNavigatorKey.currentContext;
      if (navigatorContext == null) return;
      _updateDialogOpen = true;
      showUpdateDialog(navigatorContext).whenComplete(() {
        _updateDialogOpen = false;
      });
    });

    final FeedbackServiceConfig? feedbackService = ref.watch(
      feedbackServiceConfigProvider,
    );
    // Persisted appearance choice (设置 → 外观). While the store is still
    // resolving the app follows the system, which is also the default.
    final ThemeMode themeMode =
        ref.watch(themeModeControllerProvider).value ?? ThemeMode.system;
    // Persisted accent choice (设置 → 外观 → 主题色). Monet is opt-in; while the
    // store is still resolving the brand default applies.
    final AccentPreference accentPreference =
        ref.watch(accentControllerProvider).value ?? AccentPreference.defaults;
    // Host-managed orb preferences: watched only when the layer is mounted so
    // debug builds and tests never touch the bootstrap/store providers.
    final FeedbackOrbSettings orbSettings = feedbackService == null
        ? FeedbackOrbSettings.defaults
        : ref.watch(feedbackOrbSettingsProvider).value ??
              FeedbackOrbSettings.defaults;
    // Only resolve the package version when the feedback layer actually needs
    // it; tests in debug mode keep the provider untouched.
    final String? feedbackAppVersion = feedbackService == null
        ? null
        : _formatVersion(ref.watch(appVersionProvider).value);

    // Builds the root MaterialApp with the resolved per-brightness accents.
    // Kept as a closure so the Monet and non-Monet paths share one definition.
    Widget buildMaterialApp(Color? lightAccent, Color? darkAccent) {
      return MaterialApp.router(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        // Material 3 appearance in both light and dark mode. Which one is used
        // app-wide follows the persisted 主题模式 preference; the player page
        // still forces its own dark theme for the video overlays. The seed
        // follows the persisted 主题色 preference (preset or Monet).
        theme: buildAppTheme(Brightness.light, accent: lightAccent),
        darkTheme: buildAppTheme(Brightness.dark, accent: darkAccent),
        themeMode: themeMode,
        routerConfig: ref.watch(appRouterProvider),
        // Mount the long-lived feedback layer above the router subtree so the orb
        // is present on every page and the draft survives navigation. The orb is
        // hidden on the player page, where it would cover video controls.
        builder: (BuildContext context, Widget? child) {
          Widget routerChild = child ?? const SizedBox.shrink();
          // The 求片 banner sits above every page (including the player) but
          // below the feedback layer, so the orb's capture boundary stays intact.
          routerChild = _withRequestBanner(routerChild);
          if (feedbackService == null) return routerChild;
          return ValueListenableBuilder<String>(
            valueListenable: _feedbackPageLabel,
            builder: (BuildContext context, String pageLabel, Widget? _) {
              return FeedbackOverlay(
                controller: _feedbackController,
                navigatorKey: _feedbackNavigatorKey,
                config: buildFeedbackConfig(
                  service: feedbackService,
                  pageLabel: pageLabel,
                  appVersion: feedbackAppVersion,
                  showLauncher: pageLabel != 'player',
                ),
                orbIdleStyle: orbSettings.idleStyle,
                onOrbIdleStyleChanged: (FeedbackOrbIdleStyle style) {
                  unawaited(
                    _persistOrbSettings(
                      ref
                          .read(feedbackOrbSettingsProvider.notifier)
                          .setIdleStyle(style),
                    ),
                  );
                },
                wakeGestures: orbSettings.wakeGestures,
                onWakeGesturesChanged: (Set<FeedbackWakeGesture> gestures) {
                  unawaited(
                    _persistOrbSettings(
                      ref
                          .read(feedbackOrbSettingsProvider.notifier)
                          .setWakeGestures(gestures),
                    ),
                  );
                },
                child: routerChild,
              );
            },
          );
        },
      );
    }

    // Monet is opt-in. Only touch the dynamic_color platform channel when the
    // user actually enabled 跟随系统, so the default path stays plugin-free (and
    // widget tests that never enable Monet never mount the channel builder).
    if (accentPreference.mode != AccentMode.monet) {
      return buildMaterialApp(
        resolveAccentColor(accentPreference, null),
        resolveAccentColor(accentPreference, null),
      );
    }

    // Monet (跟随系统) reads the Android 12+ system palette here; the builder
    // re-runs when the OS accent changes. On other platforms the schemes stay
    // null and the chosen preset/default keeps tinting the app.
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        // dynamic_color also reports desktop accent colours; Monet is an
        // Android-only option, so ignore them everywhere else.
        final bool monetSupported =
            defaultTargetPlatform == TargetPlatform.android;
        return buildMaterialApp(
          resolveAccentColor(
            accentPreference,
            monetSupported ? lightDynamic : null,
          ),
          resolveAccentColor(
            accentPreference,
            monetSupported ? darkDynamic : null,
          ),
        );
      },
    );
  }

  /// Overlays the 求片 banner on [child].
  ///
  /// Kept out of the router so it survives navigation: the user is usually
  /// watching something when a request finishes, and a banner inside the
  /// library route would never appear while the player is on top.
  Widget _withRequestBanner(Widget child) {
    return Stack(
      children: <Widget>[
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ValueListenableBuilder<RequestNotification?>(
            valueListenable: _banner,
            builder: (BuildContext context, RequestNotification? event, _) {
              if (event == null) return const SizedBox.shrink();
              return RequestNotificationBanner(
                event: event,
                onTap: _openMyRequests,
                onDismiss: _dismissBanner,
              );
            },
          ),
        ),
      ],
    );
  }

  /// Persists a change coming from the in-panel feedback settings. The panel
  /// has no error surface, so a failure is only logged; the settings page
  /// performs the same writes with visible error feedback.
  Future<void> _persistOrbSettings(Future<void> save) async {
    try {
      await save;
    } catch (error) {
      debugPrint('[feedback] 保存灵感球设置失败：$error');
    }
  }

  static String? _formatVersion(PackageInfo? info) =>
      info == null ? null : '${info.version}+${info.buildNumber}';
}
