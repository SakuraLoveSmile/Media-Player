import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/emby_exception.dart';
import 'package:media_player/data/models/media_item.dart';
import 'package:media_player/features/series/season_controller.dart';

import '../../support/fake_library_service.dart';

const _series = MediaItem(id: 'show', name: '测试剧集', type: 'Series');
const _season = MediaItem(
  id: 's1',
  name: '第一季',
  type: 'Season',
  seriesId: 'show',
  indexNumber: 1,
  childCount: 3,
);

MediaItem _episode(
  String id,
  int? number, {
  bool played = false,
  int ticks = 0,
  int? seasonNumber = 1,
}) => MediaItem(
  id: id,
  name: 'Episode $id',
  type: 'Episode',
  seriesId: 'show',
  seasonId: 's1',
  indexNumber: number,
  parentIndexNumber: seasonNumber,
  runTimeTicks: const Duration(minutes: 5).inMicroseconds * 10,
  overview: '简介 $id',
  userData: UserItemData(played: played, positionTicks: ticks),
);

class _ControlledLibrary extends FakeLibraryService {
  _ControlledLibrary()
    : super(
        itemsById: <String, MediaItem>{
          _series.id: _series,
          _season.id: _season,
        },
        seasonsBySeries: <String, List<MediaItem>>{
          _series.id: <MediaItem>[_season],
        },
        episodesBySeason: <String, List<MediaItem>>{
          's1': <MediaItem>[_episode('e1', 1), _episode('e2', 2)],
        },
      );

  Future<MediaItem> Function(String itemId)? onItem;
  Future<List<MediaItem>> Function(String seriesId, String seasonId)?
  onEpisodes;

  @override
  Future<MediaItem> item(String itemId) {
    final handler = onItem;
    if (handler == null) return super.item(itemId);
    detailRequests.add(itemId);
    return handler(itemId);
  }

  @override
  Future<List<MediaItem>> episodes({
    required String seriesId,
    required String seasonId,
  }) {
    final handler = onEpisodes;
    if (handler == null) {
      return super.episodes(seriesId: seriesId, seasonId: seasonId);
    }
    episodeRequests.add((seriesId: seriesId, seasonId: seasonId));
    return handler(seriesId, seasonId);
  }
}

void main() {
  late _ControlledLibrary library;
  late SeasonController controller;

  setUp(() {
    library = _ControlledLibrary();
    controller = SeasonController(
      seriesId: _series.id,
      seasonId: _season.id,
      library: library,
    );
  });

  tearDown(() => controller.dispose());

  test('loads the series hero, the season and its episodes', () async {
    await controller.load();

    expect(controller.state.series, _series);
    expect(controller.state.season, _season);
    expect(controller.state.seasonNumber, 1);
    expect(controller.state.episodes.map((item) => item.id), <String>[
      'e1',
      'e2',
    ]);
    expect(library.detailRequests, <String>['show', 's1']);
    expect(library.episodeRequests, <({String seriesId, String seasonId})>[
      (seriesId: 'show', seasonId: 's1'),
    ]);
    expect(controller.state.loading, isFalse);
    expect(controller.state.error, isNull);
  });

  test('episode sorting is numeric and stable', () async {
    library.episodesBySeason['s1'] = <MediaItem>[
      _episode('missing-b', null),
      _episode('ten', 10),
      _episode('missing-a', null),
      _episode('two', 2),
      _episode('two-again', 2),
    ];
    await controller.load();

    expect(controller.state.episodes.map((item) => item.id), <String>[
      'two',
      'two-again',
      'ten',
      'missing-b',
      'missing-a',
    ]);
  });

  test(
    'playTarget prefers progress, then first unwatched, then first',
    () async {
      library.episodesBySeason['s1'] = <MediaItem>[
        _episode('watched', 1, played: true),
        _episode('progress', 2, ticks: 100000000),
        _episode('next', 3),
      ];
      await controller.load();
      expect(controller.state.playTarget!.id, 'progress');

      library.episodesBySeason['s1'] = <MediaItem>[
        _episode('watched', 1, played: true),
        _episode('next', 2),
      ];
      await controller.refreshEpisodes();
      expect(controller.state.playTarget!.id, 'next');

      library.episodesBySeason['s1'] = <MediaItem>[
        _episode('watched', 1, played: true),
      ];
      await controller.refreshEpisodes();
      expect(controller.state.playTarget!.id, 'watched');
    },
  );

  test('watched reflects the season item', () async {
    await controller.load();
    expect(controller.state.watched, isFalse);

    library.itemsById[_season.id] = MediaItem(
      id: _season.id,
      name: _season.name,
      type: 'Season',
      indexNumber: 1,
      userData: const UserItemData(played: true),
    );
    await controller.refresh();
    expect(controller.state.watched, isTrue);
  });

  test('a failed load keeps the retryable error', () async {
    library.failure = EmbyException(AppErrorCode.networkUnreachable);

    await controller.load();

    expect(controller.state.error, '无法连接服务器，请检查网络');
    expect(controller.state.loading, isFalse);
    expect(controller.state.unauthorized, isFalse);
    expect(controller.state.episodes, isEmpty);
    expect(controller.state.season, isNull);

    library.failure = null;
    await controller.load();
    expect(controller.state.error, isNull);
    expect(controller.state.episodes, hasLength(2));
  });

  test('401 during load expires the session without retrying', () async {
    library.unauthorized = true;

    await controller.load();

    expect(controller.state.unauthorized, isTrue);
    expect(controller.state.loading, isFalse);
    expect(controller.state.error, isNull);
    expect(library.episodeRequests, isEmpty);
  });

  test('a failed episode refresh retains rows and can be retried', () async {
    await controller.load();
    final List<MediaItem> oldRows = controller.state.episodes;
    library.failure = EmbyException(AppErrorCode.forbidden);

    await controller.refreshEpisodes();

    expect(controller.state.episodes, same(oldRows));
    expect(controller.state.episodesError, '没有访问该剧集的权限');
    expect(controller.state.unauthorized, isFalse);

    library.failure = null;
    await controller.refreshEpisodes();
    expect(controller.state.episodesError, isNull);
  });

  test('a later episode refresh supersedes an earlier one', () async {
    await controller.load();
    final List<Completer<List<MediaItem>>> pending =
        <Completer<List<MediaItem>>>[];
    library.onEpisodes = (_, _) {
      final response = Completer<List<MediaItem>>();
      pending.add(response);
      return response.future;
    };

    final Future<void> oldRefresh = controller.refreshEpisodes();
    final Future<void> newRefresh = controller.refreshEpisodes();
    pending[1].complete(<MediaItem>[_episode('new', 1, played: true)]);
    await newRefresh;
    pending[0].complete(<MediaItem>[_episode('old', 1)]);
    await oldRefresh;

    expect(controller.state.episodes.single.id, 'new');
    expect(controller.state.episodesLoading, isFalse);
  });

  test('refresh keeps the page populated while re-reading', () async {
    await controller.load();
    final Completer<List<MediaItem>> response = Completer<List<MediaItem>>();
    library.onEpisodes = (_, _) => response.future;

    final Future<void> refreshing = controller.refresh();
    expect(controller.state.loading, isTrue);
    expect(controller.state.episodes, hasLength(2));
    response.complete(<MediaItem>[_episode('new', 1, played: true)]);
    await refreshing;

    expect(controller.state.loading, isFalse);
    expect(controller.state.episodes.single.id, 'new');
  });

  test(
    'favorite and played toggles write the season id with rollback',
    () async {
      await controller.load();

      await controller.toggleFavorite();
      expect(controller.state.season!.userData.isFavorite, isTrue);
      expect(library.favoriteWrites.single, (itemId: 's1', favorite: true));

      await controller.togglePlayed();
      expect(controller.state.season!.userData.played, isTrue);
      expect(library.playedWrites.single, (itemId: 's1', played: true));

      library.writeFailure = EmbyException(AppErrorCode.networkUnreachable);
      await controller.togglePlayed();
      expect(controller.state.season!.userData.played, isTrue);
      expect(controller.state.playedBusy, isFalse);
      expect(controller.state.writeError, '观看状态更新失败，请稍后重试');
    },
  );

  test(
    'dispose before completion suppresses queries and notifications',
    () async {
      final Completer<MediaItem> itemResponse = Completer<MediaItem>();
      library.onItem = (_) => itemResponse.future;
      final SeasonController disposed = SeasonController(
        seriesId: _series.id,
        seasonId: _season.id,
        library: library,
      );
      var notifications = 0;
      disposed.addListener(() => notifications++);
      final Future<void> loading = disposed.load();
      expect(notifications, 1);
      disposed.dispose();
      itemResponse.complete(_series);
      await loading;
      expect(notifications, 1);
      expect(library.episodeRequests, isEmpty);
    },
  );

  test('image helpers answer null without a poster cache', () async {
    await controller.load();

    expect(controller.backdropImage(_series), isNull);
    expect(controller.posterImage('s1'), isNull);
    expect(controller.episodeImage(_episode('e1', 1)), isNull);
  });
}
