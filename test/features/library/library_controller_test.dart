import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/emby_exception.dart';
import 'package:media_player/data/models/library_view.dart';
import 'package:media_player/data/models/media_item.dart';
import 'package:media_player/features/library/library_controller.dart';

import '../../support/fake_library_service.dart';

void main() {
  late FakeLibraryService service;
  late LibraryController controller;

  setUp(() {
    service = FakeLibraryService(
      viewList: const <LibraryView>[fakeMoviesView, fakeShowsView],
      itemsByView: <String, List<MediaItem>>{
        fakeMoviesView.id: List<MediaItem>.generate(
          75,
          (index) => fakeItem('${index + 1}'),
        ),
        fakeShowsView.id: List<MediaItem>.generate(
          3,
          (index) => fakeItem('s${index + 1}', name: 'Show ${index + 1}'),
        ),
      },
    );
    controller = LibraryController(service);
  });

  tearDown(() => controller.dispose());

  test('load selects the first view and the first page', () async {
    await controller.load();

    final state = controller.state;
    expect(state.views, hasLength(2));
    expect(state.selectedView?.id, fakeMoviesView.id);
    expect(state.items, hasLength(60));
    expect(state.total, 75);
    expect(state.hasMore, isTrue);
    expect(state.loaded, isTrue);
    expect(state.error, isNull);
  });

  test('loadMore appends until the total is reached', () async {
    await controller.load();
    await controller.loadMore();

    expect(controller.state.items, hasLength(75));
    expect(controller.state.hasMore, isFalse);
    expect(service.itemCalls, 2);

    await controller.loadMore();
    expect(service.itemCalls, 2, reason: 'no request past the last page');
  });

  test('switching views reloads from the first page', () async {
    await controller.load();
    await controller.loadMore();

    await controller.selectView(fakeShowsView);

    expect(controller.state.selectedView?.id, fakeShowsView.id);
    expect(controller.state.items.map((i) => i.id), <String>['s1', 's2', 's3']);
    expect(controller.state.total, 3);
    expect(controller.state.hasMore, isFalse);
  });

  test('refresh keeps the selected view', () async {
    await controller.load();
    await controller.selectView(fakeShowsView);

    await controller.load(refresh: true);

    expect(controller.state.selectedView?.id, fakeShowsView.id);
    expect(controller.state.items, hasLength(3));
  });

  test('an unauthorized load flags the state without an error banner',
      () async {
    await controller.load();
    service.unauthorized = true;

    await controller.load(refresh: true);

    expect(controller.state.unauthorized, isTrue);
    expect(controller.state.error, isNull);
    expect(controller.state.loading, isFalse);
  });

  test('a transport error is shown and can be retried', () async {
    service.failure = EmbyException(AppErrorCode.networkUnreachable);

    await controller.load();
    expect(controller.state.error, '无法连接服务器，请检查网络');
    expect(controller.state.items, isEmpty);

    service.failure = null;
    await controller.load();

    expect(controller.state.error, isNull);
    expect(controller.state.items, hasLength(60));
  });

  test('an empty server ends in a loaded empty state', () async {
    service.viewList = const [];

    await controller.load();

    expect(controller.state.loaded, isTrue);
    expect(controller.state.views, isEmpty);
    expect(controller.state.loading, isFalse);
  });

  test('a load more failure keeps the loaded items', () async {
    await controller.load();
    service.failure = EmbyException(AppErrorCode.networkUnreachable);

    await controller.loadMore();

    expect(controller.state.items, hasLength(60));
    expect(controller.state.error, '无法连接服务器，请检查网络');
    expect(controller.state.loadingMore, isFalse);
  });
}
