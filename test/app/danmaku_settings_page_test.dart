import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/danmaku_settings.dart';
import 'package:media_player/data/danmaku/danmaku_settings.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/features/settings/danmaku_settings_page.dart';
import 'package:media_player/ui/theme/app_theme.dart';

void main() {
  Future<void> pumpPage(
    WidgetTester tester,
    InMemoryKeyValueStore store,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          danmakuSettingsStoreProvider.overrideWith((ref) async => store),
        ],
        child: MaterialApp(
          theme: buildAppTheme(Brightness.dark),
          home: const DanmakuSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the enable switch persists the blob (S36)', (tester) async {
    final store = InMemoryKeyValueStore();
    await pumpPage(tester, store);

    await tester.tap(find.byKey(const Key('danmaku-settings-enabled')));
    await tester.pumpAndSettle();

    final Map<String, dynamic> json = jsonDecode(
      (await store.read(DanmakuSettings.storageKey))!,
    ) as Map<String, dynamic>;
    expect(json['enabled'], true);
  });

  testWidgets('the density and area controls persist', (tester) async {
    final store = InMemoryKeyValueStore();
    await pumpPage(tester, store);

    await tester.tap(find.byKey(const Key('danmaku-settings-full-area')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.descendant(
        of: find.byKey(const Key('danmaku-settings-density')),
        matching: find.byType(Slider),
      ),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();

    final Map<String, dynamic> json = jsonDecode(
      (await store.read(DanmakuSettings.storageKey))!,
    ) as Map<String, dynamic>;
    expect(json['fullArea'], true);
    expect(json['density'] as num, lessThan(1.0));
    expect(json['density'] as num, greaterThanOrEqualTo(0.1));
  });
}
