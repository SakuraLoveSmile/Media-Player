import 'dart:async';

import 'package:feedback_widget/feedback_widget.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/config/app_config.dart';
import '../features/settings/update_dialog.dart';
import 'feedback_config.dart';
import 'feedback_layer.dart';
import 'feedback_orb_settings.dart';
import 'router.dart';
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
  final ValueNotifier<String> _feedbackPageLabel =
      ValueNotifier<String>('startup');
  late final FeedbackController _feedbackController;
  GoRouter? _router;
  bool _updateDialogOpen = false;

  /// Only the silent startup check may auto-open the update dialog. Manual
  /// checks from the settings page open it themselves, so a shared trigger
  /// would stack two dialogs.
  bool _autoPromptUpdates = false;

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
    _feedbackPageLabel.dispose();
    super.dispose();
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
    _feedbackPageLabel.value =
        feedbackPageLabelFromUri(router.routerDelegate.currentConfiguration.uri);
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

    final FeedbackServiceConfig? feedbackService =
        ref.watch(feedbackServiceConfigProvider);
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

    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF3F51B5),
      ),
      routerConfig: ref.watch(appRouterProvider),
      // Mount the long-lived feedback layer above the router subtree so the orb
      // is present on every page and the draft survives navigation. The orb is
      // hidden on the player page, where it would cover video controls.
      builder: (BuildContext context, Widget? child) {
        final Widget routerChild = child ?? const SizedBox.shrink();
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
