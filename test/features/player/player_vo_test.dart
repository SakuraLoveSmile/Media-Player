import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/models/media_item.dart';
import 'package:media_player/data/playback/playback_engine.dart';
import 'package:media_player/data/playback/playback_settings.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/features/player/player_controller.dart';

import '../../support/fake_library_service.dart';
import '../../support/fake_playback_engine.dart';
import '../../support/fake_playback_reporter.dart';
import '../../support/fake_playback_service.dart';

MediaItem _item() => MediaItem(
  id: 'item-1',
  name: '测试影片',
  type: 'Movie',
  runTimeTicks: const Duration(minutes: 90).inMicroseconds * 10,
);

void main() {
  late FakeLibraryService library;
  late FakePlaybackService playback;
  late FakePlaybackEngine engine;
  late FakePlaybackReporter reporter;
  PlayerController? controller;

  setUp(() {
    library = FakeLibraryService();
    playback = FakePlaybackService();
    engine = FakePlaybackEngine();
    reporter = FakePlaybackReporter();
  });

  tearDown(() => controller?.dispose());

  PlayerController build({KeyValueStore? store}) {
    library.itemsByView = <String, List<MediaItem>>{
      fakeMoviesView.id: <MediaItem>[_item()],
    };
    return controller = PlayerController(
      itemId: 'item-1',
      library: library,
      playback: playback,
      engine: engine,
      reporter: reporter,
      store: store,
      delay: (_) async {},
    );
  }

  test(
    'load never forces the VO before the Android surface is attached',
    () async {
      final player = build();
      await player.load();

      // The WinID assertion crash regression: the load pass must defer the VO
      // switch (applyVo:false) so media_kit selects it once wid is ready.
      expect(engine.advancedApplyVo, isNotEmpty);
      expect(engine.advancedApplyVo.first, isFalse);
    },
  );

  test('a live gpu-next toggle switches the VO', () async {
    final player = build();
    await player.load();

    await player.setAdvancedVideo(gpuNext: true);

    expect(engine.advancedApplyVo.last, isTrue);
    expect(engine.advancedVideo.last.gpuNext, isTrue);
  });

  test(
    'a persisted gpu-next applies on the first rendered frame, not at load',
    () async {
      final store = InMemoryKeyValueStore();
      await store.write(
        PlaybackSettings.storageKey,
        jsonEncode(const PlaybackSettings(gpuNext: true).toJson()),
      );
      final player = build(store: store);
      await player.load();

      // Deferred at load; no frame rendered yet, so the VO was never switched.
      expect(engine.advancedApplyVo.first, isFalse);
      expect(engine.advancedApplyVo.every((bool v) => !v), isTrue);

      engine.emit(
        const PlaybackSnapshot(
          videoWidth: 1920,
          videoHeight: 1080,
          playing: true,
        ),
      );
      await pumpEventQueue();

      expect(engine.advancedVideo.last.gpuNext, isTrue);
      expect(engine.advancedApplyVo.last, isTrue);
    },
  );
}
