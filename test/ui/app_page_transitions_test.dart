import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:media_player/core/router/app_page.dart';
import 'package:media_player/ui/theme/app_page_transitions.dart';
import 'package:media_player/ui/theme/app_theme.dart';
import 'package:media_player/ui/theme/app_tokens.dart';

/// The page below the pushed one; kept identifiable for the "was it still
/// painted underneath the fade" assertions.
class _FirstPage extends StatelessWidget {
  const _FirstPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          key: const Key('open-second'),
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const _SecondPage())),
          child: const Text('first'),
        ),
      ),
    );
  }
}

class _SecondPage extends StatelessWidget {
  const _SecondPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('second')));
  }
}

/// Replaces the initial route with another one, the way the app swaps its
/// 启动页 for the first real destination.
class _GateSwap extends StatefulWidget {
  const _GateSwap();

  @override
  State<_GateSwap> createState() => _GateSwapState();
}

class _GateSwapState extends State<_GateSwap> {
  bool _entered = false;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      pages: <Page<void>>[
        if (!_entered)
          MaterialPage<void>(
            key: const ValueKey<String>('gate'),
            child: Scaffold(
              body: Center(
                child: TextButton(
                  key: const Key('enter'),
                  onPressed: () => setState(() => _entered = true),
                  child: const Text('splash'),
                ),
              ),
            ),
          )
        else
          const MaterialPage<void>(
            key: ValueKey<String>('home'),
            child: Scaffold(body: Center(child: Text('home'))),
          ),
      ],
      onDidRemovePage: (Page<Object?> page) {},
    );
  }
}

/// Pushes through go_router (not the raw Navigator) so the page type
/// go_router picks is part of the test.
class _GoRouterFirstPage extends StatelessWidget {
  const _GoRouterFirstPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          key: const Key('go-second'),
          onPressed: () => context.push('/second'),
          child: const Text('first'),
        ),
      ),
    );
  }
}

Widget _harness({bool reduceMotion = false}) {
  return MaterialApp(
    theme: buildAppTheme(Brightness.light),
    builder: (BuildContext context, Widget? child) {
      if (!reduceMotion) return child!;
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      );
    },
    home: const _FirstPage(),
  );
}

/// Every cross-fade ancestor of [page] (used to prove one is absent).
Finder _fadesAround(Finder page) =>
    find.ancestor(of: page, matching: find.byType(FadeTransition));

/// The cross-fade that wraps [page]. The nearest ancestor is the route's own
/// transition; outer navigators (a harness app's first route) add their own.
Finder _fadeAround(Finder page) => _fadesAround(page).first;

double _opacityOf(WidgetTester tester, Finder page) =>
    tester.widget<FadeTransition>(_fadeAround(page)).opacity.value;

Future<void> _openSecond(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('open-second')));
  await tester.pump();
}

void main() {
  group('theme wiring', () {
    test('every platform cross-fades pages in both brightnesses', () {
      for (final Brightness brightness in Brightness.values) {
        final ThemeData theme = buildAppTheme(brightness);
        for (final TargetPlatform platform in TargetPlatform.values) {
          expect(
            theme.pageTransitionsTheme.builders[platform],
            isA<AppFadePageTransitionsBuilder>(),
            reason: '$platform / $brightness',
          );
        }
      }
    });

    test('the fade stays short enough to keep navigation snappy', () {
      const AppFadePageTransitionsBuilder builder =
          AppFadePageTransitionsBuilder();
      expect(builder.transitionDuration, AppMotion.pageIn);
      expect(builder.reverseTransitionDuration, AppMotion.pageOut);
      expect(
        builder.transitionDuration,
        lessThanOrEqualTo(const Duration(milliseconds: 400)),
      );
      expect(
        builder.reverseTransitionDuration,
        lessThan(builder.transitionDuration),
      );
    });
  });

  group('cross-fade', () {
    testWidgets('the initial route appears without a launch flash', (
      WidgetTester tester,
    ) async {
      // The first route is installed at full opacity; only navigations fade.
      await tester.pumpWidget(_harness());
      expect(find.text('first'), findsOneWidget);
      expect(_opacityOf(tester, find.byType(_FirstPage)), 1);
    });

    testWidgets('a pushed page fades in over the page below', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_harness());
      await _openSecond(tester);
      await tester.pump(const Duration(milliseconds: 60));

      // Partly transparent, and the page below is still painted, so the screen
      // is never empty mid-transition.
      expect(_opacityOf(tester, find.byType(_SecondPage)), greaterThan(0));
      expect(_opacityOf(tester, find.byType(_SecondPage)), lessThan(1));
      expect(find.byType(_FirstPage), findsOneWidget);

      await tester.pumpAndSettle();
      expect(_opacityOf(tester, find.byType(_SecondPage)), 1);
    });

    testWidgets('a replaced initial route dissolves into the replacement', (
      WidgetTester tester,
    ) async {
      // 启动页 → 首页 replaces the first route instead of pushing over it; the
      // destination must still fade in over the gate rather than cut to it.
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: const _GateSwap(),
        ),
      );
      await tester.tap(find.byKey(const Key('enter')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      expect(find.text('home'), findsOneWidget);
      // The gate is still painted underneath, so the frame is never empty.
      expect(find.text('splash'), findsOneWidget);
      final double homeOpacity = _opacityOf(tester, find.text('home'));
      expect(homeOpacity, greaterThan(0));
      expect(homeOpacity, lessThan(1));

      await tester.pumpAndSettle();
      expect(find.text('splash'), findsNothing);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('a popped page fades out and reveals the page below', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_harness());
      await _openSecond(tester);
      await tester.pumpAndSettle();

      Navigator.of(tester.element(find.byType(_SecondPage))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      expect(_opacityOf(tester, find.byType(_SecondPage)), lessThan(1));
      expect(find.byType(_FirstPage), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byType(_SecondPage), findsNothing);
      expect(find.text('first'), findsOneWidget);
    });

    testWidgets('go_router routes still get the cross-fade', (
      WidgetTester tester,
    ) async {
      // go_router's own default page is a NoTransitionPage here (it looks for
      // the standalone material_ui MaterialApp), which silently disabled every
      // transition. The app declares MaterialPage through appPage; if that
      // wiring breaks, this test fails.
      final GoRouter router = GoRouter(
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            pageBuilder: (BuildContext context, GoRouterState state) =>
                appPage(state, const _GoRouterFirstPage()),
          ),
          GoRoute(
            path: '/second',
            pageBuilder: (BuildContext context, GoRouterState state) =>
                appPage(state, const _SecondPage()),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          theme: buildAppTheme(Brightness.light),
          routerConfig: router,
        ),
      );
      await tester.tap(find.byKey(const Key('go-second')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      expect(find.byType(_SecondPage), findsOneWidget);
      // The route must be built from a MaterialPage, not a NoTransitionPage.
      expect(
        ModalRoute.of(tester.element(find.byType(_SecondPage)))?.settings,
        isA<MaterialPage<void>>(),
      );
      expect(_opacityOf(tester, find.byType(_SecondPage)), greaterThan(0));
      expect(_opacityOf(tester, find.byType(_SecondPage)), lessThan(1));

      await tester.pumpAndSettle();
      expect(_opacityOf(tester, find.byType(_SecondPage)), 1);
    });

    testWidgets('reduced motion skips the cross-fade', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_harness(reduceMotion: true));
      await _openSecond(tester);
      // The route itself is built on the frame after the push is scheduled;
      // its own animation still runs, only the fade wrapper is missing.
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(_SecondPage), findsOneWidget);
      expect(_fadesAround(find.byType(_SecondPage)), findsNothing);
      await tester.pumpAndSettle();
    });
  });
}
