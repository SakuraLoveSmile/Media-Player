import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/cast/dlna_device.dart';
import 'package:media_player/data/models/media_item.dart';
import 'package:media_player/data/playback/playback_engine.dart';
import 'package:media_player/features/player/player_controller.dart';

import '../../support/fake_dlna_cast_service.dart';
import '../../support/fake_library_service.dart';
import '../../support/fake_playback_engine.dart';
import '../../support/fake_playback_reporter.dart';
import '../../support/fake_playback_service.dart';

const _device = DlnaDevice(
  id: 'uuid:tv',
  name: '客厅电视',
  controlUrl: 'http://192.168.0.5:8080/AVTransport/control',
  address: '192.168.0.5:8080',
);

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
  late FakeDlnaCastService cast;
  PlayerController? controller;

  setUp(() {
    library = FakeLibraryService();
    playback = FakePlaybackService();
    engine = FakePlaybackEngine();
    reporter = FakePlaybackReporter();
    cast = FakeDlnaCastService();
  });

  tearDown(() => controller?.dispose());

  PlayerController build({FakeDlnaCastService? castService}) {
    library.itemsByView = <String, List<MediaItem>>{
      fakeMoviesView.id: <MediaItem>[_item()],
    };
    return controller = PlayerController(
      itemId: 'item-1',
      library: library,
      playback: playback,
      engine: engine,
      reporter: reporter,
      cast: castService,
      delay: (_) async {},
    );
  }

  test('discover populates the device list and clears the spinner', () async {
    cast.devices = <DlnaDevice>[_device];
    final player = build(castService: cast);
    await player.load();

    await player.discoverCastDevices();

    expect(player.state.castDiscovering, isFalse);
    expect(player.state.castDevices, <DlnaDevice>[_device]);
    expect(player.state.castError, isNull);
    expect(cast.discoverCalls, 1);
  });

  test('a failed scan is a picker line, not a playback error', () async {
    cast.discoverError = Exception('no lan');
    final player = build(castService: cast);
    await player.load();

    await player.discoverCastDevices();

    expect(player.state.castDiscovering, isFalse);
    expect(player.state.castDevices, isEmpty);
    expect(player.state.castError, isNotNull);
    expect(player.state.error, isNull);
  });

  test(
    'castTo hands the stream to the renderer and pauses local playback',
    () async {
      final player = build(castService: cast);
      await player.load();
      engine.emit(const PlaybackSnapshot(playing: true));
      await pumpEventQueue();

      await player.castTo(_device);

      expect(cast.casts, hasLength(1));
      expect(cast.casts.single.device, _device);
      expect(cast.casts.single.url, 'http://lan.example/videos/item-1/stream');
      expect(cast.casts.single.title, '测试影片');
      expect(player.state.castingTo, _device);
      expect(engine.pauseCalls, 1);
    },
  );

  test('a failed cast surfaces an error and keeps no target', () async {
    cast.castError = Exception('renderer refused');
    final player = build(castService: cast);
    await player.load();

    await player.castTo(_device);

    expect(player.state.castingTo, isNull);
    expect(player.state.castError, isNotNull);
  });

  test('stopCast clears the target and stops the renderer', () async {
    final player = build(castService: cast);
    await player.load();
    await player.castTo(_device);

    await player.stopCast();

    expect(player.state.castingTo, isNull);
    expect(cast.stops, <DlnaDevice>[_device]);
  });

  test('without a cast service the calls are no-ops', () async {
    final player = build();
    await player.load();

    await player.discoverCastDevices();
    await player.castTo(_device);
    await player.stopCast();

    expect(player.state.castDevices, isEmpty);
    expect(player.state.castingTo, isNull);
  });
}
