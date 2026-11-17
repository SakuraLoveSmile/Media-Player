import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/models/media_item.dart';
import 'package:media_player/data/playback/mpv_config.dart';
import 'package:media_player/data/playback/playback_engine.dart';
import 'package:media_player/data/playback/playback_settings.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/features/player/player_controller.dart';

import '../../support/fake_library_service.dart';
import '../../support/fake_playback_engine.dart';
import '../../support/fake_playback_reporter.dart';
import '../../support/fake_playback_service.dart';

class ConfigurableEngine extends FakePlaybackEngine implements MpvConfigEngine {
  final configs = <Map<String, String>>[];
  int failures = 0;

  @override
  Future<void> applyMpvConfig(Map<String, String> properties) async {
    configs.add(Map.of(properties));
    if (failures > 0) {
      failures--;
      throw StateError('unsupported renderer option');
    }
  }
}

void main() {
  Future<PlayerController> load(
    ConfigurableEngine engine,
    PlaybackSettings settings,
  ) async {
    final store = InMemoryKeyValueStore();
    await store.write(
      PlaybackSettings.storageKey,
      jsonEncode(settings.toJson()),
    );
    final controller = PlayerController(
      itemId: 'item-1',
      library: FakeLibraryService(
        itemsById: {
          'item-1': const MediaItem(id: 'item-1', name: 'Movie', type: 'Movie'),
        },
      ),
      playback: FakePlaybackService(),
      engine: engine,
      reporter: FakePlaybackReporter(),
      store: store,
      delay: (_) async {},
    );
    addTearDown(controller.dispose);
    await controller.load();
    return controller;
  }

  test('stored preset and overrides reach engine after open', () async {
    final engine = ConfigurableEngine();
    final controller = await load(
      engine,
      const PlaybackSettings(
        mpvQualityPreset: MpvQualityPreset.animation,
        mpvCustomConfig: 'saturation=8',
      ),
    );
    expect(controller.state.ready, true);
    expect(controller.state.qualityWarning, isNull);
    expect(engine.openedPlans, hasLength(1));
    expect(engine.configs.single['sigmoid-upscaling'], 'yes');
    expect(engine.configs.single['saturation'], '8');
    expect(engine.configs.single.keys.toSet(), MpvConfig.defaults.keys.toSet());
  });

  test(
    'rejected quality resets full defaults and keeps playback ready',
    () async {
      final engine = ConfigurableEngine()..failures = 1;
      final controller = await load(
        engine,
        const PlaybackSettings(mpvQualityPreset: MpvQualityPreset.cinema),
      );
      expect(controller.state.ready, true);
      expect(controller.state.error, isNull);
      expect(engine.configs.last, MpvConfig.defaults);
      expect(controller.state.qualityWarning, contains('已恢复默认'));
    },
  );

  test(
    'reset rejection keeps playback but never claims reset succeeded',
    () async {
      final engine = ConfigurableEngine()..failures = 2;
      final controller = await load(engine, const PlaybackSettings());
      expect(controller.state.ready, true);
      expect(controller.state.qualityWarning, '画质配置无法应用，请检查 MPV 设置');
    },
  );

  test(
    'corrupted stored config never sends forbidden option to engine',
    () async {
      final engine = ConfigurableEngine();
      final controller = await load(
        engine,
        const PlaybackSettings(mpvCustomConfig: 'include=/tmp/untrusted.conf'),
      );
      expect(controller.state.ready, true);
      expect(controller.state.qualityWarning, contains('已恢复默认'));
      expect(engine.configs.single, MpvConfig.defaults);
    },
  );
}
