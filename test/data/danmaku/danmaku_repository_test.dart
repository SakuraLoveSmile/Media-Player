import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/dandanplay_exception.dart';
import 'package:media_player/core/errors/emby_exception.dart';
import 'package:media_player/data/danmaku/danmaku_repository.dart';
import 'package:media_player/data/danmaku/models/danmaku_anime.dart';
import 'package:media_player/data/danmaku/models/danmaku_comment.dart';
import 'package:media_player/data/models/media_item.dart';
import 'package:media_player/data/storage/key_value_store.dart';

import '../../support/fake_dandanplay_client.dart';
import '../../support/fake_library_service.dart';

const DanmakuComment comment = DanmakuComment(
  time: Duration(seconds: 2),
  mode: 1,
  color: 16777215,
  text: '弹幕',
);

MediaItem movie() => const MediaItem(id: 'm1', name: '测试电影', type: 'Movie');

MediaItem episode({int? index = 3, String? seriesId = 's1'}) => MediaItem(
  id: 'e1',
  name: '第3集 自己的标题',
  type: 'Episode',
  seriesId: seriesId,
  seasonId: 'season1',
  indexNumber: index,
);

void main() {
  late FakeDandanPlayClient client;
  late FakeLibraryService library;
  late DanmakuRepository repository;

  setUp(() {
    client = FakeDandanPlayClient();
    library = FakeLibraryService(
      itemsById: <String, MediaItem>{
        's1': const MediaItem(id: 's1', name: '测试剧集', type: 'Series'),
      },
    );
    repository = DanmakuRepository(client: client, library: library);
    client.matchResult = const DanmakuMatch(
      episodeId: 1001,
      animeTitle: '测试剧集',
      episodeTitle: '第3话',
    );
    client.comments = <DanmakuComment>[comment];
  });

  test(
    'a manual match is remembered and wins over the automatic one',
    () async {
      final store = InMemoryKeyValueStore();
      final DanmakuRepository repo = DanmakuRepository(
        client: client,
        library: library,
        store: store,
      );
      const DanmakuAnime anime = DanmakuAnime(
        id: 9,
        title: '另一部番',
        episodes: <DanmakuEpisode>[DanmakuEpisode(id: 77, title: '第1话')],
      );

      final DanmakuLoad applied = await repo.applyManual(
        movie(),
        anime,
        anime.episodes.first,
      );
      expect(applied.status, DanmakuStatus.matched);
      expect(applied.episodeLabel, '另一部番 · 第1话');
      expect(client.commentRequests.last, 77);
      expect(await repo.isManual(movie()), isTrue);

      // A fresh repository over the same store reuses the memory and never runs
      // the automatic match.
      final int matchesBefore = client.matchRequests.length;
      final DanmakuRepository second = DanmakuRepository(
        client: client,
        library: library,
        store: store,
      );
      final DanmakuLoad again = await second.loadFor(movie());
      expect(again.status, DanmakuStatus.matched);
      expect(again.episodeLabel, '另一部番 · 第1话');
      expect(client.matchRequests.length, matchesBefore);
      expect(await second.isManual(movie()), isTrue);

      await second.clearManual(movie().id);
      expect(await second.isManual(movie()), isFalse);
    },
  );
  test('a movie searches by its own title without an episode filter', () async {
    final DanmakuLoad load = await repository.loadFor(movie());

    expect(client.matchRequests, hasLength(1));
    expect(client.matchRequests.single.title, '测试电影');
    expect(client.matchRequests.single.episode, isNull);
    expect(client.commentRequests, <int>[1001]);
    expect(load.status, DanmakuStatus.matched);
    expect(load.comments, <DanmakuComment>[comment]);
    expect(load.episodeLabel, '测试剧集 · 第3话');
  });

  test('an episode searches by the series title plus its index', () async {
    final DanmakuLoad load = await repository.loadFor(episode());

    expect(client.matchRequests.single.title, '测试剧集');
    expect(client.matchRequests.single.episode, '3');
    expect(load.status, DanmakuStatus.matched);
  });

  test('an episode without an index searches without the filter', () async {
    await repository.loadFor(episode(index: null));

    expect(client.matchRequests.single.title, '测试剧集');
    expect(client.matchRequests.single.episode, isNull);
  });

  test('a missing series falls back to the episode title', () async {
    await repository.loadFor(episode(seriesId: null));

    expect(client.matchRequests.single.title, '第3集 自己的标题');
    expect(client.matchRequests.single.episode, '3');
  });

  test('a failed series lookup falls back to the episode title', () async {
    library.failure = EmbyException(AppErrorCode.networkUnreachable);

    final DanmakuLoad load = await repository.loadFor(episode());

    expect(client.matchRequests.single.title, '第3集 自己的标题');
    expect(load.status, DanmakuStatus.matched);
  });

  test('no library wired still matches by the episode title', () async {
    final DanmakuRepository bare = DanmakuRepository(client: client);

    await bare.loadFor(episode());

    expect(client.matchRequests.single.title, '第3集 自己的标题');
  });

  test('results are cached per item in memory', () async {
    final MediaItem item = movie();
    await repository.loadFor(item);
    await repository.loadFor(item);

    expect(client.matchRequests, hasLength(1));
    expect(client.commentRequests, hasLength(1));

    // A different item is a different cache entry.
    await repository.loadFor(
      const MediaItem(id: 'm2', name: '另一部', type: 'Movie'),
    );
    expect(client.matchRequests, hasLength(2));
  });

  test('no match is a status, not an error, and is cached', () async {
    client.matchResult = null;

    final DanmakuLoad first = await repository.loadFor(movie());
    final DanmakuLoad second = await repository.loadFor(movie());

    expect(first.status, DanmakuStatus.noMatch);
    expect(first.comments, isEmpty);
    expect(second.status, DanmakuStatus.noMatch);
    expect(client.matchRequests, hasLength(1));
    expect(client.commentRequests, isEmpty);
  });

  test(
    'a match failure is error with empty comments and is not cached',
    () async {
      client.matchFailure = DandanPlayException(
        AppErrorCode.networkUnreachable,
      );

      final DanmakuLoad first = await repository.loadFor(movie());
      expect(first.status, DanmakuStatus.error);
      expect(first.comments, isEmpty);

      // The retry can succeed: errors are not cached.
      client.matchFailure = null;
      final DanmakuLoad second = await repository.loadFor(movie());
      expect(second.status, DanmakuStatus.matched);
      expect(client.matchRequests, hasLength(2));
    },
  );

  test('a comment failure is error with empty comments', () async {
    client.commentsFailure = DandanPlayException(AppErrorCode.serverError);

    final DanmakuLoad load = await repository.loadFor(movie());

    expect(load.status, DanmakuStatus.error);
    expect(load.comments, isEmpty);
  });

  test('a matched episode with zero comments stays matched', () async {
    client.comments = <DanmakuComment>[];

    final DanmakuLoad load = await repository.loadFor(movie());

    expect(load.status, DanmakuStatus.matched);
    expect(load.comments, isEmpty);
  });
}
