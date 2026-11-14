import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/appearance_settings.dart';
import 'package:media_player/ui/app_loader.dart';
import 'package:media_player/ui/theme/app_theme.dart';
import 'package:media_player/ui/theme/app_tokens.dart';

void main() {
  Future<void> pumpLoading(WidgetTester tester, {Widget? child}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // No stored preference: the controller falls back to the defaults.
          appearanceSettingsStoreProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: Scaffold(body: child ?? const AppLoadingView()),
        ),
      ),
    );
  }

  double opacityOf(WidgetTester tester) => tester
      .widget<Opacity>(
        find.descendant(
          of: find.byType(AppLoadingView),
          matching: find.byType(Opacity),
        ),
      )
      .opacity;

  testWidgets('renders the configured app loader', (WidgetTester tester) async {
    await pumpLoading(tester);
    expect(find.byKey(const Key('app-loader')), findsOneWidget);
  });

  testWidgets('fades in instead of popping while a page is arriving', (
    WidgetTester tester,
  ) async {
    await pumpLoading(tester);
    expect(opacityOf(tester), 0);
    await tester.pump(AppMotion.fast);
    expect(opacityOf(tester), 1);
  });

  testWidgets('forwards its size to the loader', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appearanceSettingsStoreProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: const Scaffold(body: AppLoadingView(size: 22)),
        ),
      ),
    );
    final Size size = tester.getSize(find.byKey(const Key('app-loader')));
    expect(size, const Size(22, 22));
  });

  testWidgets('announces the wait to screen readers', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await pumpLoading(tester);
    expect(find.bySemanticsLabel('加载中'), findsOneWidget);
    semantics.dispose();
  });
}
