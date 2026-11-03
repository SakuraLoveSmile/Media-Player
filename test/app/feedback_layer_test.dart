import 'package:feedback_widget/feedback_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/feedback_config.dart';
import 'package:media_player/app/feedback_layer.dart';

FeedbackServiceConfig _testService() => const FeedbackServiceConfig(
  apiBase: 'http://localhost:8787',
  appId: 'dev.mediaplayer.media_player.test',
);

/// Mirrors the host wiring: `MaterialApp.builder` would wrap the router child,
/// so the test builds the same structure by hand — an outer feedback navigator
/// above an app navigator, both below a MaterialApp.
Widget _host({
  required FeedbackController controller,
  required GlobalKey<NavigatorState> feedbackNavigatorKey,
  required GlobalKey<NavigatorState> routerKey,
  String pageLabel = 'startup',
  FeedbackOrbIdleStyle? orbIdleStyle,
  ValueChanged<FeedbackOrbIdleStyle>? onOrbIdleStyleChanged,
  Set<FeedbackWakeGesture>? wakeGestures,
  ValueChanged<Set<FeedbackWakeGesture>>? onWakeGesturesChanged,
}) {
  return MaterialApp(
    home: FeedbackOverlay(
      controller: controller,
      navigatorKey: feedbackNavigatorKey,
      config: buildFeedbackConfig(
        service: _testService(),
        pageLabel: pageLabel,
      ),
      orbIdleStyle: orbIdleStyle,
      onOrbIdleStyleChanged: onOrbIdleStyleChanged,
      wakeGestures: wakeGestures,
      onWakeGesturesChanged: onWakeGesturesChanged,
      child: Navigator(
        key: routerKey,
        onGenerateRoute: (RouteSettings settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (BuildContext context) =>
              const Scaffold(body: Center(child: Text('startup page'))),
        ),
      ),
    ),
  );
}

Future<GlobalKey<NavigatorState>> _pumpOuterNavigator(
  WidgetTester tester,
) async {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      home: Navigator(
        key: navigatorKey,
        onGenerateRoute: (RouteSettings settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (BuildContext context) => const SizedBox.shrink(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return navigatorKey;
}

void main() {
  group('mounted layer (orb above the router)', () {
    testWidgets('mounts FeedbackWidget with the shared controller and orb', (
      WidgetTester tester,
    ) async {
      // Disposed in the test body: flutter_test checks for leaked handles
      // before teardown callbacks run.
      final SemanticsHandle semantics = tester.ensureSemantics();

      final FeedbackController controller = FeedbackController();
      addTearDown(controller.dispose);
      final GlobalKey<NavigatorState> feedbackNavigatorKey =
          GlobalKey<NavigatorState>();
      final GlobalKey<NavigatorState> routerKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        _host(
          controller: controller,
          feedbackNavigatorKey: feedbackNavigatorKey,
          routerKey: routerKey,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FeedbackWidget), findsOneWidget);
      expect(find.byKey(const Key('feedback-orb')), findsOneWidget);
      expect(find.text('startup page'), findsOneWidget);

      // The orb is an interactive launcher for accessibility tooling.
      final SemanticsNode orbNode = tester.getSemantics(
        find.byKey(const Key('feedback-orb')),
      );
      expect(orbNode.label, '灵感球');
      expect(orbNode.getSemanticsData().flagsCollection.isButton, isTrue);

      // The layer uses the root-owned controller and the current config.
      final FeedbackWidget widget = tester.widget<FeedbackWidget>(
        find.byType(FeedbackWidget),
      );
      expect(identical(widget.controller, controller), isTrue);
      expect(widget.config.launcherMode, FeedbackLauncherMode.orb);
      expect(widget.config.captureMode, FeedbackCaptureMode.viewport);
      expect(widget.config.pageLabel, 'startup');

      // The outer navigator (panel host) is the one the host owns.
      expect(feedbackNavigatorKey.currentState, isNotNull);

      semantics.dispose();
    });

    testWidgets('survives navigation underneath without being rebuilt', (
      WidgetTester tester,
    ) async {
      final FeedbackController controller = FeedbackController();
      addTearDown(controller.dispose);
      final GlobalKey<NavigatorState> feedbackNavigatorKey =
          GlobalKey<NavigatorState>();
      final GlobalKey<NavigatorState> routerKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        _host(
          controller: controller,
          feedbackNavigatorKey: feedbackNavigatorKey,
          routerKey: routerKey,
        ),
      );
      await tester.pumpAndSettle();

      final State<FeedbackWidget> before = tester.state<State<FeedbackWidget>>(
        find.byType(FeedbackWidget),
      );

      routerKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (BuildContext context) =>
              const Scaffold(body: Center(child: Text('library page'))),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('library page'), findsOneWidget);
      final State<FeedbackWidget> after = tester.state<State<FeedbackWidget>>(
        find.byType(FeedbackWidget),
      );
      expect(
        identical(before, after),
        isTrue,
        reason:
            'route push/pop must not rebuild the layer, otherwise the '
            'draft and login token would be lost',
      );
      expect(find.byKey(const Key('feedback-orb')), findsOneWidget);
    });

    testWidgets('a config update reaches the component without a rebuild', (
      WidgetTester tester,
    ) async {
      final FeedbackController controller = FeedbackController();
      addTearDown(controller.dispose);
      final GlobalKey<NavigatorState> feedbackNavigatorKey =
          GlobalKey<NavigatorState>();
      final GlobalKey<NavigatorState> routerKey = GlobalKey<NavigatorState>();

      await tester.pumpWidget(
        _host(
          controller: controller,
          feedbackNavigatorKey: feedbackNavigatorKey,
          routerKey: routerKey,
        ),
      );
      await tester.pumpAndSettle();
      final State<FeedbackWidget> before = tester.state<State<FeedbackWidget>>(
        find.byType(FeedbackWidget),
      );

      // The app builder rebuilds the layer with the new page label.
      await tester.pumpWidget(
        _host(
          controller: controller,
          feedbackNavigatorKey: feedbackNavigatorKey,
          routerKey: routerKey,
          pageLabel: 'library',
        ),
      );
      await tester.pumpAndSettle();

      final State<FeedbackWidget> after = tester.state<State<FeedbackWidget>>(
        find.byType(FeedbackWidget),
      );
      expect(identical(before, after), isTrue);
      expect(
        tester
            .widget<FeedbackWidget>(find.byType(FeedbackWidget))
            .config
            .pageLabel,
        'library',
      );
    });

    testWidgets('host-managed orb settings reach the component; hidden hides only idle',
        (
      WidgetTester tester,
    ) async {
      final FeedbackController controller = FeedbackController();
      addTearDown(controller.dispose);
      final GlobalKey<NavigatorState> feedbackNavigatorKey =
          GlobalKey<NavigatorState>();
      final GlobalKey<NavigatorState> routerKey = GlobalKey<NavigatorState>();
      FeedbackOrbIdleStyle? changedStyle;
      Set<FeedbackWakeGesture>? changedGestures;

      await tester.pumpWidget(
        _host(
          controller: controller,
          feedbackNavigatorKey: feedbackNavigatorKey,
          routerKey: routerKey,
          orbIdleStyle: FeedbackOrbIdleStyle.hidden,
          onOrbIdleStyleChanged: (FeedbackOrbIdleStyle style) {
            changedStyle = style;
          },
          wakeGestures: const <FeedbackWakeGesture>{
            FeedbackWakeGesture.twoFingerHold,
          },
          onWakeGesturesChanged: (Set<FeedbackWakeGesture> gestures) {
            changedGestures = gestures;
          },
        ),
      );
      await tester.pumpAndSettle();

      final FeedbackWidget widget = tester.widget<FeedbackWidget>(
        find.byType(FeedbackWidget),
      );
      expect(widget.orbIdleStyle, FeedbackOrbIdleStyle.hidden);
      expect(widget.wakeGestures, <FeedbackWakeGesture>{
        FeedbackWakeGesture.twoFingerHold,
      });
      // v0.8.5: the hidden style only hides the idle/collapsed entry. The full
      // orb is shown first; after the idle timer the launcher slot disappears
      // (the controller can still open the panel).
      expect(find.byKey(const Key('feedback-orb')), findsOneWidget);
      expect(find.byKey(const Key('feedback-launcher-slot')), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 420));
      expect(find.byKey(const Key('feedback-orb')), findsNothing);
      expect(find.byKey(const Key('feedback-launcher-slot')), findsNothing);

      widget.onOrbIdleStyleChanged!(FeedbackOrbIdleStyle.edge);
      widget.onWakeGesturesChanged!(<FeedbackWakeGesture>{
        FeedbackWakeGesture.twoFingerDoubleTap,
      });
      expect(changedStyle, FeedbackOrbIdleStyle.edge);
      expect(changedGestures, <FeedbackWakeGesture>{
        FeedbackWakeGesture.twoFingerDoubleTap,
      });
    });
  });

  group('shared controller', () {
    test('tracks open/close and notifies listeners', () {
      final FeedbackController controller = FeedbackController();
      addTearDown(controller.dispose);

      int notifications = 0;
      controller.addListener(() => notifications++);

      controller.open();
      expect(controller.isOpen, isTrue);
      controller.close();
      expect(controller.isOpen, isFalse);
      expect(notifications, greaterThanOrEqualTo(2));
    });
  });

  group('back handling (panel / preview dialog first)', () {
    testWidgets(
      'returns false when neither a panel nor an outer route is open',
      (WidgetTester tester) async {
        final GlobalKey<NavigatorState> navigatorKey =
            await _pumpOuterNavigator(tester);
        final FeedbackController controller = FeedbackController();
        addTearDown(controller.dispose);

        expect(navigatorKey.currentState!.canPop(), isFalse);
        expect(
          handleFeedbackBackPop(
            navigatorKey: navigatorKey,
            controller: controller,
          ),
          isFalse,
        );
        expect(controller.isOpen, isFalse);
      },
    );

    testWidgets('closes an open panel and consumes the event', (
      WidgetTester tester,
    ) async {
      final GlobalKey<NavigatorState> navigatorKey = await _pumpOuterNavigator(
        tester,
      );
      final FeedbackController controller = FeedbackController();
      addTearDown(controller.dispose);

      controller.open();
      expect(
        handleFeedbackBackPop(
          navigatorKey: navigatorKey,
          controller: controller,
        ),
        isTrue,
      );
      expect(controller.isOpen, isFalse);
    });

    testWidgets('pops the outer preview dialog before closing the panel', (
      WidgetTester tester,
    ) async {
      final GlobalKey<NavigatorState> navigatorKey = await _pumpOuterNavigator(
        tester,
      );
      final FeedbackController controller = FeedbackController();
      addTearDown(controller.dispose);

      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (BuildContext context) =>
              const Center(child: Text('preview')),
        ),
      );
      await tester.pumpAndSettle();
      controller.open();
      expect(navigatorKey.currentState!.canPop(), isTrue);

      expect(
        handleFeedbackBackPop(
          navigatorKey: navigatorKey,
          controller: controller,
        ),
        isTrue,
      );
      await tester.pumpAndSettle();

      // Dialog dismissed first; the panel stays open for the next back event.
      expect(find.text('preview'), findsNothing);
      expect(navigatorKey.currentState!.canPop(), isFalse);
      expect(controller.isOpen, isTrue);

      expect(
        handleFeedbackBackPop(
          navigatorKey: navigatorKey,
          controller: controller,
        ),
        isTrue,
      );
      expect(controller.isOpen, isFalse);
    });
  });
}
