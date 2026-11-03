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
    this.orbIdleStyle,
    this.onOrbIdleStyleChanged,
    this.wakeGestures,
    this.onWakeGesturesChanged,
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
      orbIdleStyle: scope.orbIdleStyle,
      onOrbIdleStyleChanged: scope.onOrbIdleStyleChanged,
      wakeGestures: scope.wakeGestures,
      onWakeGesturesChanged: scope.onWakeGesturesChanged,
      child: scope.routerChild,
    );
  }
}

/// Consumes a system-back (Android) / pop event on behalf of the feedback
/// layer. Order matters: dismiss a screenshot-preview dialog sitting on the
/// outer navigator first, then close the panel; only when neither is open does
/// the event fall through to normal navigation. Returns `true` when consumed.
///
/// Desktop `Esc` is handled inside the component itself; this covers the
/// platform back gesture, which the host owns because the layer lives above the
/// router and is therefore not reached by the router's own back handling.
bool handleFeedbackBackPop({
  required GlobalKey<NavigatorState> navigatorKey,
  required FeedbackController controller,
}) {
  final NavigatorState? outerNav = navigatorKey.currentState;
  if (outerNav != null && outerNav.canPop()) {
    outerNav.pop(); // dismiss the preview dialog on the outer navigator
    return true;
  }
  if (controller.isOpen) {
    controller.close();
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
    this.orbIdleStyle,
    this.onOrbIdleStyleChanged,
    this.wakeGestures,
    this.onWakeGesturesChanged,
  });

  final FeedbackController controller;
  final FeedbackConfig config;
  final Widget routerChild;
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
      orbIdleStyle != oldWidget.orbIdleStyle ||
      onOrbIdleStyleChanged != oldWidget.onOrbIdleStyleChanged ||
      !setEquals(wakeGestures, oldWidget.wakeGestures) ||
      onWakeGesturesChanged != oldWidget.onWakeGesturesChanged;
}
