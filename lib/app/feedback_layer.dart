import 'package:feedback_widget/feedback_widget.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';

/// Long-lived feedback layer, mounted in `MaterialApp.router`'s `builder` above
/// the router subtree (see the feedback_widget integration guide §3.5).
///
/// Structure:
/// ```
/// _FeedbackScope            (InheritedWidget: latest config + router child)
///   └── Navigator           (outer host navigator, zero-transition, once)
///         └── FeedbackWidget(orb + panel + capture scope)
///               └── RepaintBoundary -> the router subtree
/// ```
///
/// The outer [Navigator] supplies the Navigator/Overlay ancestors the panel
/// needs (TextField selection handles and the screenshot-preview dialog) while
/// sitting ABOVE the app's own Navigator, so route push/pop never rebuilds the
/// widget and the draft + login token survive navigation. Because that route is
/// created once and its content is cached, [_FeedbackScope] feeds the latest
/// config/child into the route body through an inherited dependency instead of
/// recreating the route.
class FeedbackOverlay extends StatelessWidget {
  const FeedbackOverlay({
    super.key,
    required this.controller,
    required this.navigatorKey,
    required this.config,
    required this.child,
    this.launcherStyle,
    this.onLauncherStyleChanged,
    this.wakeVisual,
    this.onWakeVisualChanged,
    this.orbEntrance,
    this.onOrbEntranceChanged,
    this.orbIdleStyle,
    this.onOrbIdleStyleChanged,
    this.wakeGestures,
    this.onWakeGesturesChanged,
    this.hideSettings = false,
  });

  /// Root-owned controller (stable identity across rebuilds).
  final FeedbackController controller;

  /// Key for the outer host navigator; the host uses it to pop a feedback
  /// screenshot-preview dialog before falling back to normal back navigation.
  final GlobalKey<NavigatorState> navigatorKey;

  /// Current config (service identity + pageLabel + appVersion + fixed choices).
  final FeedbackConfig config;

  /// The router subtree passed to `MaterialApp.router`'s builder.
  final Widget child;

  /// Host-managed launcher style / wake visual / orb entrance
  /// (feedback_widget >= 0.11.0). When non-null the component renders the host
  /// value instead of its own preference and hides that in-panel setting.
  final FeedbackLauncherStyle? launcherStyle;
  final ValueChanged<FeedbackLauncherStyle>? onLauncherStyleChanged;
  final FeedbackWakeVisual? wakeVisual;
  final ValueChanged<FeedbackWakeVisual>? onWakeVisualChanged;
  final FeedbackOrbEntrance? orbEntrance;
  final ValueChanged<FeedbackOrbEntrance>? onOrbEntranceChanged;

  /// Hides the non-server part of the in-panel settings page: every feedback
  /// setting lives in the host settings page instead.
  final bool hideSettings;

  /// Host-managed orb idle style (feedback_widget >= 0.8.4). When non-null the
  /// component renders this value instead of persisting its own preference.
  final FeedbackOrbIdleStyle? orbIdleStyle;

  /// Persistence callback for [orbIdleStyle]; required for the in-panel setting
  /// to stay visible and to round-trip user changes.
  final ValueChanged<FeedbackOrbIdleStyle>? onOrbIdleStyleChanged;

  /// Host-managed wake gestures. Same contracts as [orbIdleStyle].
  final Set<FeedbackWakeGesture>? wakeGestures;

  final ValueChanged<Set<FeedbackWakeGesture>>? onWakeGesturesChanged;

  @override
  Widget build(BuildContext context) {
    return _FeedbackScope(
      controller: controller,
      config: config,
      routerChild: child,
      launcherStyle: launcherStyle,
      onLauncherStyleChanged: onLauncherStyleChanged,
      wakeVisual: wakeVisual,
      onWakeVisualChanged: onWakeVisualChanged,
      orbEntrance: orbEntrance,
      onOrbEntranceChanged: onOrbEntranceChanged,
      hideSettings: hideSettings,
      orbIdleStyle: orbIdleStyle,
      onOrbIdleStyleChanged: onOrbIdleStyleChanged,
      wakeGestures: wakeGestures,
      onWakeGesturesChanged: onWakeGesturesChanged,
      child: Navigator(
        key: navigatorKey,
        onGenerateRoute: (RouteSettings settings) => PageRouteBuilder<void>(
          settings: settings,
          // The outer route only hosts the component; no transition wanted.
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
          ) => const _FeedbackLayerBody(),
        ),
      ),
    );
  }
}

/// Route body: rebuilds whenever [_FeedbackScope] hands down a new config or
/// router child, without recreating the outer route (so the panel state, and
/// therefore the draft, is preserved).
class _FeedbackLayerBody extends StatelessWidget {
  const _FeedbackLayerBody();

  @override
  Widget build(BuildContext context) {
    final _FeedbackScope scope = _FeedbackScope.of(context);
    return FeedbackWidget(
      config: scope.config,
      controller: scope.controller,
      launcherStyle: scope.launcherStyle,
      onLauncherStyleChanged: scope.onLauncherStyleChanged,
      wakeVisual: scope.wakeVisual,
      onWakeVisualChanged: scope.onWakeVisualChanged,
      orbEntrance: scope.orbEntrance,
      onOrbEntranceChanged: scope.onOrbEntranceChanged,
      hideSettings: scope.hideSettings,
      orbIdleStyle: scope.orbIdleStyle,
      onOrbIdleStyleChanged: scope.onOrbIdleStyleChanged,
      wakeGestures: scope.wakeGestures,
      onWakeGesturesChanged: scope.onWakeGesturesChanged,
      child: scope.routerChild,
    );
  }
}

/// Host half of the system-back (Android) / pop handling for the feedback
/// layer.
///
/// Only the routes the host owns are consumed here: a screenshot-preview or
/// discard-confirmation dialog pushed on the outer navigator (the one mounted
/// by [FeedbackOverlay]) is dismissed first. Everything else returns `false`
/// so the event keeps travelling down the observer chain:
///
/// 1. this host observer (registered first, before `MaterialApp` builds),
/// 2. `WidgetsApp`, which declines because the app uses a router,
/// 3. `FeedbackWidget` (`feedback_widget >= 0.15.0`), mounted above the app
///    router, whose `didPopRoute` asks 「放弃这次反馈？」 when the panel holds
///    text the user typed or files they attached, closes the panel, and
///    consumes the event — the host page is *not* popped,
/// 4. the router's own back dispatcher, which pops the host page when the
///    panel is closed.
///
/// Closing the panel here instead (`controller.close()`, what this helper did
/// before 0.15.0) would be a programmatic close: it skips the component's
/// confirmation and silently drops what the user wrote. Desktop `Esc` is
/// handled inside the component itself and never reaches this function.
bool handleFeedbackBackPop({
  required GlobalKey<NavigatorState> navigatorKey,
}) {
  final NavigatorState? outerNav = navigatorKey.currentState;
  if (outerNav != null && outerNav.canPop()) {
    outerNav.pop(); // dismiss the preview / discard dialog on the outer navigator
    return true;
  }
  return false;
}

class _FeedbackScope extends InheritedWidget {
  const _FeedbackScope({
    required this.controller,
    required this.config,
    required this.routerChild,
    required super.child,
    this.launcherStyle,
    this.onLauncherStyleChanged,
    this.wakeVisual,
    this.onWakeVisualChanged,
    this.orbEntrance,
    this.onOrbEntranceChanged,
    this.hideSettings = false,
    this.orbIdleStyle,
    this.onOrbIdleStyleChanged,
    this.wakeGestures,
    this.onWakeGesturesChanged,
  });

  final FeedbackController controller;
  final FeedbackConfig config;
  final Widget routerChild;
  final FeedbackLauncherStyle? launcherStyle;
  final ValueChanged<FeedbackLauncherStyle>? onLauncherStyleChanged;
  final FeedbackWakeVisual? wakeVisual;
  final ValueChanged<FeedbackWakeVisual>? onWakeVisualChanged;
  final FeedbackOrbEntrance? orbEntrance;
  final ValueChanged<FeedbackOrbEntrance>? onOrbEntranceChanged;
  final bool hideSettings;
  final FeedbackOrbIdleStyle? orbIdleStyle;
  final ValueChanged<FeedbackOrbIdleStyle>? onOrbIdleStyleChanged;
  final Set<FeedbackWakeGesture>? wakeGestures;
  final ValueChanged<Set<FeedbackWakeGesture>>? onWakeGesturesChanged;

  static _FeedbackScope of(BuildContext context) {
    final _FeedbackScope? scope = context
        .dependOnInheritedWidgetOfExactType<_FeedbackScope>();
    assert(scope != null, 'No _FeedbackScope found in context');
    return scope!;
  }

  @override
  bool updateShouldNotify(_FeedbackScope oldWidget) =>
      config != oldWidget.config ||
      controller != oldWidget.controller ||
      routerChild != oldWidget.routerChild ||
      launcherStyle != oldWidget.launcherStyle ||
      onLauncherStyleChanged != oldWidget.onLauncherStyleChanged ||
      wakeVisual != oldWidget.wakeVisual ||
      onWakeVisualChanged != oldWidget.onWakeVisualChanged ||
      orbEntrance != oldWidget.orbEntrance ||
      onOrbEntranceChanged != oldWidget.onOrbEntranceChanged ||
      hideSettings != oldWidget.hideSettings ||
      orbIdleStyle != oldWidget.orbIdleStyle ||
      onOrbIdleStyleChanged != oldWidget.onOrbIdleStyleChanged ||
      !setEquals(wakeGestures, oldWidget.wakeGestures) ||
      onWakeGesturesChanged != oldWidget.onWakeGesturesChanged;
}
