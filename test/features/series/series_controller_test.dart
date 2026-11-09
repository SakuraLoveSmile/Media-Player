import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/emby_exception.dart';
import 'package:media_player/data/models/media_item.dart';
import 'package:media_player/features/series/series_controller.dart';

import '../../support/fake_library_service.dart';

const _series = MediaItem(id: 'show', name: 'The show', type: 'Series');

MediaItem _season(String id, int? number) => MediaItem(
  id: id,
  name: 'Season $id',
  type: 'Season',
  seriesId: _series.id,
  indexNumber: number,
);

MediaItem _episode(
  String id,
  int? number, {
  bool played = false,
  int ticks = 0,
}) => MediaItem(
  id: id,
  name: 'Episode $id',
  type: 'Episode',
  seriesId: _series.id,
  indexNumber: number,
  userData: UserItemData(played: played, positionTicks: ticks),
);

class _ControlledLibrary extends FakeLibraryService {
  _ControlledLibrary()
    : super(
        itemsById: <String, MediaItem>{_series.id: _series},
        seasonsBySeries: <String, List<MediaItem>>{
          _series.id: <MediaItem>[_season('a', 1), _season('b', 2)],
        },
        episodesBySeason: <String, List<MediaItem>>{
          'a': <MediaItem>[_episode('a-1', 1)],
          'b': <MediaItem>[_episode('b-1', 1)],
        },
      );

  Future<List<MediaItem>> Function(String seriesId, String seasonId)?
  onEpisodes;
  Future<MediaItem> Function(String itemId)? onItem;
  Future<List<MediaItem>> Function(String seriesId)? onSeasons;

  @override
  Future<MediaItem> item(String itemId) {
    final handler = onItem;
    if (handler == null) return super.item(itemId);
    detailRequests.add(itemId);
    return handler(itemId);
  }

  @override
  Future<List<MediaItem>> seasons(String seriesId) {
    final handler = onSeasons;
    if (handler == null) return super.seasons(seriesId);
    seasonsRequests.add(seriesId);
    return handler(seriesId);
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
  late SeriesController controller;

  setUp(() {
    library = _ControlledLibrary();
    controller = SeriesController(seriesId: _series.id, library: library);
  });

  tearDown(() => controller.dispose());

  test(
    'loads detail and selects the lowest positive season numerically',
    () async {
      library.seasonsBySeries[_series.id] = <MediaItem>[
        _season('unknown', null),
        _season('ten', 10),
        _season('specials', 0),
        _season('two', 2),
        _season('two-again', 2),
      ];

      await controller.load();

      expect(controller.state.series, _series);
      expect(controller.state.seasons.map((season) => season.id), <String>[
        'specials',
        'two',
        'two-again',
        'ten',
        'unknown',
      ]);
      expect(controller.state.selectedSeasonId, 'two');
      expect(library.detailRequests, <String>['show']);
      expect(library.seasonsRequests, <String>['show']);
      expect(library.episodeRequests, <({String seriesId, String seasonId})>[
        (seriesId: 'show', seasonId: 'two'),
      ]);
      expect(controller.state.loading, isFalse);
      expect(controller.state.episodesLoading, isFalse);
    },
  );

  test('specials remain selectable with their real season id', () async {
    library.seasonsBySeries[_series.id] = <MediaItem>[
      _season('specials-id', 0),
      _season('a', 1),
    ];
    library.episodesBySeason['specials-id'] = <MediaItem>[
      _episode('special', 1),
    ];
    await controller.load();
    await controller.selectSeason('specials-id');

    expect(controller.state.selectedSeasonId, 'specials-id');
    expect(controller.state.episodes.single.id, 'special');
    expect(library.episodeRequests.last, (
      seriesId: 'show',
      seasonId: 'specials-id',
    ));
  });

  test(
    'without positive numbers defaults to the sorted first season',
    () async {
      library.seasonsBySeries[_series.id] = <MediaItem>[
        _season('missing', null),
        _season('specials', 0),
      ];
      await controller.load();
      expect(controller.state.selectedSeasonId, 'specials');
    },
  );

  test('missing season numbers retain server order at the end', () async {
    library.seasonsBySeries[_series.id] = <MediaItem>[
      _season('missing-b', null),
      _season('missing-a', null),
    ];
    await controller.load();
    expect(controller.state.selectedSeasonId, 'missing-b');
    expect(controller.state.seasons.map((season) => season.id), <String>[
      'missing-b',
      'missing-a',
    ]);
  });

  test('no seasons makes no episodes request', () async {
    library.seasonsBySeries[_series.id] = <MediaItem>[];
    await controller.load();
    expect(controller.state.seasons, isEmpty);
    expect(controller.state.selectedSeasonId, isNull);
    expect(controller.state.episodes, isEmpty);
    expect(controller.state.error, isNull);
    expect(library.episodeRequests, isEmpty);
    await controller.refreshEpisodes();
    expect(library.episodeRequests, isEmpty);
  });

  test('an empty season is a successful empty response', () async {
    library.episodesBySeason['a'] = <MediaItem>[];
    await controller.load();
    expect(controller.state.selectedSeasonId, 'a');
    expect(controller.state.episodes, isEmpty);
    expect(controller.state.episodesError, isNull);
    expect(controller.state.episodesLoading, isFalse);
  });

  test(
    'episode sorting is numeric, stable and never truncated to 60',
    () async {
      final episodes = <MediaItem>[
        _episode('missing-b', null),
        _episode('missing-a', null),
        _episode('same-b', 2),
        _episode('same-a', 2),
        ...List<MediaItem>.generate(
          75,
          (i) => _episode('number-${75 - i}', 75 - i),
        ),
      ];
      library.episodesBySeason['a'] = episodes;
      await controller.load();

      expect(controller.state.episodes, hasLength(79));
      expect(controller.state.episodes.first.id, 'number-1');
      expect(controller.state.episodes.take(4).map((item) => item.id), <String>[
        'number-1',
        'same-b',
        'same-a',
        'number-2',
      ]);
      expect(
        controller.state.episodes.skip(77).map((item) => item.id),
        <String>['missing-b', 'missing-a'],
      );
      expect(
        episodes.first.id,
        'missing-b',
        reason: 'does not sort service data in place',
      );
    },
  );

  test('non-Series detail is rejected before season queries', () async {
    library.itemsById[_series.id] = fakeItem(_series.id);
    await controller.load();
    expect(controller.state.error, contains('不是剧集'));
    expect(controller.state.loading, isFalse);
    expect(library.seasonsRequests, isEmpty);
    expect(library.episodeRequests, isEmpty);
  });

  test('unknown season id cannot trigger a query', () async {
    await controller.load();
    await controller.selectSeason('not-a-season');
    expect(library.episodeRequests, hasLength(1));
    expect(controller.state.selectedSeasonId, 'a');
  });

  test(
    'switching clears rows and repeated loading selection is deduplicated',
    () async {
      await controller.load();
      final response = Completer<List<MediaItem>>();
      library.onEpisodes = (_, _) => response.future;
      final switched = controller.selectSeason('b');

      expect(controller.state.selectedSeasonId, 'b');
      expect(controller.state.episodes, isEmpty);
      expect(controller.state.episodesLoading, isTrue);
      await controller.selectSeason('b');
      expect(library.episodeRequests, hasLength(2));

      response.complete(<MediaItem>[_episode('b-new', 1)]);
      await switched;
      await controller.selectSeason('b');
      expect(library.episodeRequests, hasLength(2));
    },
  );

  test(
    'A to B to A ignores obsolete successes with the same season id',
    () async {
      await controller.load();
      final pending = <Completer<List<MediaItem>>>[];
      library.onEpisodes = (_, _) {
        final response = Completer<List<MediaItem>>();
        pending.add(response);
        return response.future;
      };
      final oldA = controller.refreshEpisodes();
      final oldB = controller.selectSeason('b');
      final currentA = controller.selectSeason('a');

      pending[2].complete(<MediaItem>[_episode('current-a', 1)]);
      await currentA;
      pending[1].complete(<MediaItem>[_episode('old-b', 1)]);
      await oldB;
      pending[0].complete(<MediaItem>[_episode('old-a', 1)]);
      await oldA;

      expect(controller.state.selectedSeasonId, 'a');
      expect(controller.state.episodes.single.id, 'current-a');
      expect(controller.state.episodesLoading, isFalse);
      expect(controller.state.episodesError, isNull);
    },
  );

  test(
    'obsolete errors do not stop current loading or replace its error',
    () async {
      await controller.load();
      final pending = <Completer<List<MediaItem>>>[];
      library.onEpisodes = (_, _) {
        final response = Completer<List<MediaItem>>();
        pending.add(response);
        return response.future;
      };
      final oldA = controller.refreshEpisodes();
      final oldB = controller.selectSeason('b');
      final currentA = controller.selectSeason('a');
      pending[0].completeError(EmbyException(AppErrorCode.networkUnreachable));
      await oldA;
      expect(controller.state.episodesLoading, isTrue);
      expect(controller.state.episodesError, isNull);

      pending[2].completeError(EmbyException(AppErrorCode.forbidden));
      await currentA;
      pending[1].completeError(EmbyException(AppErrorCode.networkUnreachable));
      await oldB;
      expect(controller.state.episodesLoading, isFalse);
      expect(controller.state.episodesError, '没有访问该剧集的权限');
      expect(controller.state.unauthorized, isFalse);
    },
  );

  test(
    'a failed selection allows manually choosing the same season to retry',
    () async {
      await controller.load();
      library.failure = EmbyException(AppErrorCode.networkUnreachable);
      await controller.selectSeason('b');
      expect(controller.state.episodesError, '无法连接服务器，请检查网络');
      expect(controller.state.error, isNull);
      expect(controller.state.episodes, isEmpty);

      library.failure = null;
      await controller.selectSeason('b');
      expect(controller.state.episodesError, isNull);
      expect(controller.state.episodes.single.id, 'b-1');
    },
  );

  test(
    'refresh retains selection and rows then applies server viewing status',
    () async {
      await controller.load();
      await controller.selectSeason('b');
      final oldRows = controller.state.episodes;
      final response = Completer<List<MediaItem>>();
      library.onEpisodes = (_, _) => response.future;
      final refreshed = controller.refreshEpisodes();
      expect(controller.state.selectedSeasonId, 'b');
      expect(controller.state.episodes, same(oldRows));
      expect(controller.state.episodesLoading, isTrue);

      response.complete(<MediaItem>[
        _episode('b-1', 1, played: true, ticks: 500000000),
      ]);
      await refreshed;
      expect(controller.state.episodes.single.userData.played, isTrue);
      expect(
        controller.state.episodes.single.userData.position,
        const Duration(seconds: 50),
      );
      expect(controller.state.selectedSeasonId, 'b');
    },
  );

  test(
    'failed refresh retains server data and can be manually retried',
    () async {
      await controller.load();
      final oldRows = controller.state.episodes;
      library.failure = EmbyException(AppErrorCode.forbidden);
      await controller.refreshEpisodes();
      expect(controller.state.episodes, same(oldRows));
      expect(controller.state.episodes.single.userData.played, isFalse);
      expect(controller.state.episodesError, '没有访问该剧集的权限');
      expect(controller.state.unauthorized, isFalse);
      expect(
        library.episodeRequests,
        hasLength(2),
        reason: '403 is never automatically retried',
      );

      library.failure = null;
      await controller.refreshEpisodes();
      expect(controller.state.episodesError, isNull);
      expect(controller.state.episodesLoading, isFalse);
    },
  );

  test('a later refresh supersedes an earlier refresh', () async {
    await controller.load();
    final pending = <Completer<List<MediaItem>>>[];
    library.onEpisodes = (_, _) {
      final response = Completer<List<MediaItem>>();
      pending.add(response);
      return response.future;
    };
    final oldRefresh = controller.refreshEpisodes();
    final newRefresh = controller.refreshEpisodes();
    pending[1].complete(<MediaItem>[_episode('new-progress', 1, played: true)]);
    await newRefresh;
    pending[0].complete(<MediaItem>[_episode('old-progress', 1)]);
    await oldRefresh;
    expect(controller.state.episodes.single.id, 'new-progress');
  });

  test(
    'page-level transport failure can retry without becoming an empty page',
    () async {
      library.failure = EmbyException(AppErrorCode.networkUnreachable);
      await controller.load();
      expect(controller.state.error, '无法连接服务器，请检查网络');
      expect(controller.state.loading, isFalse);
      expect(controller.state.episodesError, isNull);

      library.failure = null;
      await controller.load();
      expect(controller.state.error, isNull);
      expect(controller.state.episodes.single.id, 'a-1');
    },
  );

  test(
    'page-level 403 stays distinct from 401 and is not retried automatically',
    () async {
      library.failure = EmbyException(AppErrorCode.forbidden);
      await controller.load();
      expect(controller.state.error, '没有访问该剧集的权限');
      expect(controller.state.unauthorized, isFalse);
      expect(library.detailRequests, hasLength(1));
    },
  );

  test('401 during initial load marks the expired session', () async {
    library.unauthorized = true;
    await controller.load();
    expect(controller.state.unauthorized, isTrue);
    expect(controller.state.error, isNull);
    expect(controller.state.episodesError, isNull);
    expect(controller.state.loading, isFalse);
    expect(library.seasonsRequests, isEmpty);
  });

  for (final code in <AppErrorCode>[
    AppErrorCode.unauthorized,
    AppErrorCode.forbidden,
  ]) {
    test(
      '${code.name} during seasons does not query episodes or retry',
      () async {
        library.onSeasons = (_) async => throw EmbyException(code);

        await controller.load();

        expect(library.detailRequests, <String>['show']);
        expect(library.seasonsRequests, <String>['show']);
        expect(library.episodeRequests, isEmpty);
        expect(controller.state.loading, isFalse);
        expect(controller.state.episodesLoading, isFalse);
        expect(controller.state.episodesError, isNull);
        expect(
          controller.state.unauthorized,
          code == AppErrorCode.unauthorized,
        );
        expect(
          controller.state.error,
          code == AppErrorCode.unauthorized ? isNull : '没有访问该剧集的权限',
        );
      },
    );
  }

  test(
    '401 during episodes stops loading and does not become an empty error',
    () async {
      await controller.load();
      library.unauthorized = true;
      await controller.selectSeason('b');
      expect(controller.state.unauthorized, isTrue);
      expect(controller.state.episodesLoading, isFalse);
      expect(controller.state.episodesError, isNull);
      expect(controller.state.error, isNull);
    },
  );

  test(
    'obsolete 401 still invalidates session and prevents a newer success',
    () async {
      await controller.load();
      final pending = <Completer<List<MediaItem>>>[];
      library.onEpisodes = (_, _) {
        final response = Completer<List<MediaItem>>();
        pending.add(response);
        return response.future;
      };
      final oldA = controller.refreshEpisodes();
      final currentB = controller.selectSeason('b');
      pending[0].completeError(EmbyException(AppErrorCode.unauthorized));
      await oldA;
      expect(controller.state.unauthorized, isTrue);
      pending[1].complete(<MediaItem>[_episode('new-b', 1)]);
      await currentB;
      expect(controller.state.unauthorized, isTrue);
      expect(controller.state.episodes, isEmpty);
      expect(controller.state.episodesLoading, isFalse);

      await controller.refreshEpisodes();
      await controller.load();
      await controller.selectSeason('a');
      expect(
        pending,
        hasLength(2),
        reason: 'expired sessions cannot start more requests',
      );
    },
  );

  test('dispose before detail completion sends no further queries or notifications', () async {
    final response = Completer<MediaItem>();
    library.onItem = (_) => response.future;
    final disposed = SeriesController(seriesId: _series.id, library: library);
    var notifications = 0;
    disposed.addListener(() => notifications++);
    final loading = disposed.load();
    expect(notifications, 1);
    disposed.dispose();
    response.complete(_series);
    await loading;
    expect(notifications, 1);
    expect(library.seasonsRequests, isEmpty);
    expect(library.episodeRequests, isEmpty);
  });

  test(
    'dispose before seasons completion sends no episode query or notification',
    () async {
      final requested = Completer<void>();
      final response = Completer<List<MediaItem>>();
      library.onSeasons = (_) {
        requested.complete();
        return response.future;
      };
      final disposed = SeriesController(seriesId: _series.id, library: library);
      var notifications = 0;
      disposed.addListener(() => notifications++);
      final loading = disposed.load();
      await requested.future;
      expect(notifications, 1);

      disposed.dispose();
      response.complete(<MediaItem>[_season('a', 1)]);
      await loading;

      expect(notifications, 1);
      expect(library.episodeRequests, isEmpty);
    },
  );

  for (final fails in <bool>[false, true]) {
    test(
      'dispose before episode ${fails ? 'failure' : 'success'} suppresses notifications',
      () async {
        final disposed = SeriesController(
          seriesId: _series.id,
          library: library,
        );
        await disposed.load();
        final response = Completer<List<MediaItem>>();
        library.onEpisodes = (_, _) => response.future;
        var notifications = 0;
        disposed.addListener(() => notifications++);
        final refreshing = disposed.refreshEpisodes();
        expect(notifications, 1);
        disposed.dispose();
        if (fails) {
          response.completeError(EmbyException(AppErrorCode.unauthorized));
        } else {
          response.complete(<MediaItem>[_episode('late', 1)]);
        }
        await refreshing;
        expect(notifications, 1);
      },
    );
  }
}
