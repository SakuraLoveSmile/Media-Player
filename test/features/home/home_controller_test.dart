import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/emby_exception.dart';
import 'package:media_player/data/models/library_view.dart';
import 'package:media_player/data/models/media_item.dart';
import 'package:media_player/features/home/home_controller.dart';

import '../../support/fake_library_service.dart';
import '../../support/fake_poster_cache.dart';

void main() {
  late FakeLibraryService service;
  late HomeController controller;

  setUp(() {
    service = FakeLibraryService(
      viewList: const <LibraryView>[fakeMoviesView, fakeShowsView],
      itemsByView: <String, List<MediaItem>>{
        fakeMoviesView.id: <MediaItem>[
          fakeItem('m1', name: 'Movie 1'),
          fakeItem('m2', name: 'Movie 2'),
        ],
        fakeShowsView.id: const <MediaItem>[
          MediaItem(id: 's1', name: 'Show 1', type: 'Series'),
        ],
      },
    );
    service.resumableResults = <MediaItem>[
      MediaItem(
        id: 'r1',
        name: 'Resume 1',
        type: 'Movie',
        runTimeTicks: 6000000000,
        userData: const UserItemData(positionTicks: 1200000000),
      ),
    ];
    controller = HomeController(service, FakePosterCache());
  });

  tearDown(() => controller.dispose());

  test(
    'load fills the banner, continue-watching row and per-library rows',
    () async {
      await controller.load();

      final state = controller.state;
      expect(state.loaded, isTrue);
      expect(state.loading, isFalse);
      expect(state.error, isNull);
      expect(state.banner.map((i) => i.id), <String>['m1', 'm2']);
      expect(state.resumable.map((i) => i.id), <String>['r1']);
      expect(state.rows, hasLength(2));
      expect(state.rows.first.view.id, fakeMoviesView.id);
      expect(state.rows.first.items.map((i) => i.id), <String>['m1', 'm2']);
      expect(state.rows.last.view.id, fakeShowsView.id);
      expect(state.rows.last.items.map((i) => i.id), <String>['s1']);
    },
  );

  test('the banner asks the movie view for DateCreated descending', () async {
    await controller.load();

    // The banner is the first items() call of a load.
    expect(service.itemsSorts.first, (
      sortBy: 'DateCreated',
      sortOrder: 'Descending',
    ));
    expect(service.resumableRequests, <int>[20]);
  });

  test(
    'without a movie view the banner falls back to the first view',
    () async {
      service.viewList = const <LibraryView>[fakeShowsView];

      await controller.load();

      expect(controller.state.banner.map((i) => i.id), <String>['s1']);
      expect(controller.state.rows.single.view.id, fakeShowsView.id);
    },
  );

  test('an empty server ends in a loaded empty state', () async {
    service.viewList = const <LibraryView>[];

    await controller.load();

    expect(controller.state.loaded, isTrue);
    expect(controller.state.isEmpty, isTrue);
    expect(controller.state.loading, isFalse);
  });

  test('no resumable items leaves the continue-watching row empty', () async {
    service.resumableResults = const <MediaItem>[];

    await controller.load();

    expect(controller.state.resumable, isEmpty);
    expect(controller.state.banner, isNotEmpty);
  });

  test(
    'an unauthorized load flags the state without an error banner',
    () async {
      service.unauthorized = true;

      await controller.load();

      expect(controller.state.unauthorized, isTrue);
      expect(controller.state.error, isNull);
      expect(controller.state.loading, isFalse);
    },
  );

  test('a transport error is shown and can be retried', () async {
    service.failure = EmbyException(AppErrorCode.networkUnreachable);

    await controller.load();
    expect(controller.state.error, '无法连接服务器，请检查网络');
    expect(controller.state.isEmpty, isTrue);

    service.failure = null;
    await controller.load();

    expect(controller.state.error, isNull);
    expect(controller.state.banner, isNotEmpty);
  });

  test('a resumable failure surfaces as an error', () async {
    service.resumableFailure = EmbyException(AppErrorCode.serverError);

    await controller.load();

    expect(controller.state.error, '加载失败，请稍后重试');
    expect(controller.state.loading, isFalse);
  });
}
