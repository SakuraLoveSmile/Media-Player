import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/models/media_item.dart';
import 'package:media_player/data/playback/playback_engine.dart';
import 'package:media_player/features/player/player_controller.dart';

import '../../support/fake_library_service.dart';
import '../../support/fake_playback_engine.dart';
import '../../support/fake_playback_reporter.dart';
import '../../support/fake_playback_service.dart';

Chapter _ch(String name, int seconds) =>
    Chapter(name: name, startTicks: seconds * 10000000);

MediaItem _episode({List<Chapter> chapters = const <Chapter>[]}) => MediaItem(
  id: 'ep-1',
  name: '测试分集',
  type: 'Episode',
  runTimeTicks: const Duration(seconds: 1440).inMicroseconds * 10,
  chapters: chapters,
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

  PlayerController build(MediaItem item) {
    library.itemsByView = <String, List<MediaItem>>{
      fakeMoviesView.id: <MediaItem>[item],
    };
    return controller = PlayerController(
      itemId: item.id,
      library: library,
      playback: playback,
      engine: engine,
      reporter: reporter,
      delay: (_) async {},
    );
  }

  final chapters = <Chapter>[
    _ch('Intro', 0),
    _ch('正片', 90),
    _ch('Credits', 1320),
  ];

  test(
    'intro flag is live at the start and skipIntro seeks to content',
    () async {
      final player = build(_episode(chapters: chapters));
      await player.load();

      expect(player.state.canSkipIntro, isTrue);
      expect(player.state.canSkipCredits, isFalse);

      await player.skipIntro();
      expect(engine.seeks.last, const Duration(seconds: 90));
      expect(player.state.canSkipIntro, isFalse);
    },
  );

  test('the intro flag clears once content starts', () async {
    final player = build(_episode(chapters: chapters));
    await player.load();

    engine.emit(
      const PlaybackSnapshot(position: Duration(seconds: 90), playing: true),
    );
    await pumpEventQueue();
    expect(player.state.canSkipIntro, isFalse);
    expect(player.state.canSkipCredits, isFalse);
  });

  test(
    'credits flag appears at the chapter and skipCredits seeks to the end',
    () async {
      final player = build(_episode(chapters: chapters));
      await player.load();

      engine.emit(
        const PlaybackSnapshot(
          position: Duration(seconds: 1320),
          playing: true,
        ),
      );
      await pumpEventQueue();
      expect(player.state.canSkipCredits, isTrue);
      expect(player.state.canSkipIntro, isFalse);

      await player.skipCredits();
      expect(engine.seeks.last, const Duration(seconds: 1440));
    },
  );

  test('an item without chapters never offers a skip', () async {
    final player = build(_episode());
    await player.load();

    engine.emit(const PlaybackSnapshot(position: Duration.zero, playing: true));
    await pumpEventQueue();
    expect(player.state.canSkipIntro, isFalse);
    expect(player.state.canSkipCredits, isFalse);

    await player.skipIntro();
    await player.skipCredits();
    expect(engine.seeks, isEmpty);
  });

  test('a resume inside the intro still offers the skip', () async {
    final item = MediaItem(
      id: 'ep-1',
      name: '测试分集',
      type: 'Episode',
      runTimeTicks: const Duration(seconds: 1440).inMicroseconds * 10,
      chapters: chapters,
      userData: const UserItemData(positionTicks: 30 * 10000000),
    );
    final player = build(item);
    await player.load();

    expect(player.state.position, const Duration(seconds: 30));
    expect(player.state.canSkipIntro, isTrue);
  });
}
