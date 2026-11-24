import 'dart:async';

import 'package:feedback_widget/feedback_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:media_player/app/feedback_config.dart';
import 'package:media_player/app/feedback_layer.dart';

FeedbackServiceConfig _testService() => const FeedbackServiceConfig(
  apiBase: 'http://localhost:8787',
  appId: 'dev.mediaplayer.media_player.test',
);

/// Mirrors `AppShell` + `MaterialApp.router`: the host observer is registered
/// before `MaterialApp` builds (so it sees the system back first), the feedback
/// layer sits in `builder` above the app router, and the host only consumes the
/// back event for its own dialogs.
class _HostShell extends StatefulWidget {
  const _HostShell({
    required this.controller,
    required this.feedbackNavigatorKey,
    required this.routerConfig,
  });

  final FeedbackController controller;
  final GlobalKey<NavigatorState> feedbackNavigatorKey;
  final RouterConfig<Object> routerConfig;

  @override
  State<_HostShell> createState() => _HostShellState();
}

class _HostShellState extends State<_HostShell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async =>
      handleFeedbackBackPop(navigatorKey: widget.feedbackNavigatorKey);

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: widget.routerConfig,
      builder: (BuildContext context, Widget? child) => FeedbackOverlay(
        controller: widget.controller,
        navigatorKey: widget.feedbackNavigatorKey,
        config: buildFeedbackConfig(
          service: _testService(),
          pageLabel: 'library',
        ),
        hideSettings: true,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}

/// Pumps frames until the tree settles, failing fast instead of waiting the
/// 10-minute default when an animation never stops.
Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 15),
);

/// Delivers a real `popRoute` platform message, i.e. the Android back key.
///
/// Not awaited: the message handler only completes once every observer chain
/// is done, and the component's confirmation waits for the dialog — awaiting it
/// here would deadlock the test against its own tap.
Future<void> _systemBack(WidgetTester tester) async {
  final ByteData message = const JSONMethodCodec().encodeMethodCall(
    const MethodCall('popRoute'),
  );
  unawaited(
    tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      message,
      (ByteData? _) {},
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  late FeedbackController controller;
  late GlobalKey<NavigatorState> feedbackNavigatorKey;
  late GoRouter router;

  Future<void> pumpHost(WidgetTester tester) async {
    controller = FeedbackController();
    addTearDown(controller.dispose);
    feedbackNavigatorKey = GlobalKey<NavigatorState>();
    router = GoRouter(
      initialLocation: '/library',
      routes: <RouteBase>[
        GoRoute(
          path: '/library',
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(body: Center(child: Text('library page'))),
        ),
        GoRoute(
          path: '/detail',
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(body: Center(child: Text('detail page'))),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      _HostShell(
        controller: controller,
        feedbackNavigatorKey: feedbackNavigatorKey,
        routerConfig: router,
      ),
    );
    await _settle(tester);
  }

  testWidgets('back asks before discarding a typed draft and keeps the page', (
    WidgetTester tester,
  ) async {
    await pumpHost(tester);
    router.push('/detail');
    await _settle(tester);
    expect(find.text('detail page'), findsOneWidget);

    controller.open();
    await _settle(tester);
    await tester.enterText(
      find.byKey(const Key('feedback-input')),
      '播放到一半会卡住',
    );
    await _settle(tester);

    await _systemBack(tester);

    // The component asked; the panel and the typed text are still there and
    // the host page was not popped.
    expect(find.byKey(const Key('feedback-discard-confirm')), findsOneWidget);
    expect(controller.isOpen, isTrue);
    expect(find.text('detail page'), findsOneWidget);

    await tester.tap(find.byKey(const Key('feedback-discard-cancel')));
    await _settle(tester);
    expect(find.byKey(const Key('feedback-discard-confirm')), findsNothing);
    expect(controller.isOpen, isTrue);
    expect(find.text('播放到一半会卡住'), findsOneWidget);

    // Second back: give up for real.
    await _systemBack(tester);
    await tester.tap(find.byKey(const Key('feedback-discard-ok')));
    await _settle(tester);
    expect(controller.isOpen, isFalse);
    expect(find.text('detail page'), findsOneWidget);
  });

  testWidgets('back closes a panel without user content and keeps the page', (
    WidgetTester tester,
  ) async {
    await pumpHost(tester);
    router.push('/detail');
    await _settle(tester);

    controller.open();
    await _settle(tester);

    await _systemBack(tester);

    // Only an empty compose page: no confirmation, immediate close.
    expect(find.byKey(const Key('feedback-discard-confirm')), findsNothing);
    expect(controller.isOpen, isFalse);
    expect(find.text('detail page'), findsOneWidget);
  });

  testWidgets('back pops the host page once the panel is closed', (
    WidgetTester tester,
  ) async {
    await pumpHost(tester);
    router.push('/detail');
    await _settle(tester);
    expect(find.text('detail page'), findsOneWidget);

    await _systemBack(tester);

    expect(find.text('detail page'), findsNothing);
    expect(find.text('library page'), findsOneWidget);
  });
}
