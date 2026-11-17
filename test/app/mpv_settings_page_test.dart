import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/playback_settings.dart';
import 'package:media_player/app/subtitle_style_settings.dart';
import 'package:media_player/data/playback/mpv_config.dart';
import 'package:media_player/data/playback/playback_settings.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/features/settings/mpv_settings_page.dart';

void main() {
  Future<void> pump(WidgetTester tester, InMemoryKeyValueStore store) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackSettingsStoreProvider.overrideWith((ref) async => store),
          subtitleStyleStoreProvider.overrideWith((ref) async => store),
        ],
        child: const MaterialApp(home: MpvSettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('mpv-preset-cinema')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('preset persists; invalid editor lines block all writes', (
    tester,
  ) async {
    final store = InMemoryKeyValueStore();
    await pump(tester, store);
    await tester.tap(find.byKey(const Key('mpv-preset-cinema')));
    await tester.pumpAndSettle();
    final before = await store.read(PlaybackSettings.storageKey);
    expect(jsonDecode(before!)['mpvQualityPreset'], 'cinema');
    await tester.tap(find.byKey(const Key('mpv-config-edit')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('mpv-config-input')),
      'scale=lanczos\nscript=unsafe.lua',
    );
    await tester.pumpAndSettle();
    expect(find.text('第 2 行：不允许的选项：script'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('mpv-config-save')))
          .onPressed,
      isNull,
    );
    expect(await store.read(PlaybackSettings.storageKey), before);
    await tester.enterText(
      find.byKey(const Key('mpv-config-input')),
      '# custom\nscale=lanczos',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mpv-config-save')));
    await tester.pumpAndSettle();
    expect(find.text('自定义画质配置'), findsNothing);
    final after = jsonDecode((await store.read(PlaybackSettings.storageKey))!);
    expect(after['mpvCustomConfig'], '# custom\nscale=lanczos');
    expect(after['mpvQualityPreset'], 'cinema');
  });

  testWidgets('copy for AI is local and reset keeps unrelated preferences', (
    tester,
  ) async {
    final store = InMemoryKeyValueStore();
    await store.write(
      PlaybackSettings.storageKey,
      jsonEncode(
        const PlaybackSettings(
          cacheSecs: 90,
          mpvQualityPreset: MpvQualityPreset.animation,
          mpvCustomConfig: 'saturation=8',
        ).toJson(),
      ),
    );
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pump(tester, store);
    await tester.tap(find.byKey(const Key('mpv-config-edit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mpv-config-copy-ai')));
    await tester.pumpAndSettle();
    expect(clipboard, contains('saturation=8'));
    expect(clipboard, contains('不要添加外部文件'));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mpv-config-reset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mpv-config-reset-confirm')));
    await tester.pumpAndSettle();
    final restored = PlaybackSettings.fromJson(
      jsonDecode((await store.read(PlaybackSettings.storageKey))!)
          as Map<String, dynamic>,
    );
    expect(restored.mpvQualityPreset, MpvQualityPreset.standard);
    expect(restored.mpvCustomConfig, '');
    expect(restored.cacheSecs, 90);
  });
}
