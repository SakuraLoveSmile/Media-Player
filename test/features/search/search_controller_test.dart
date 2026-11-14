import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/emby_exception.dart';
import 'package:media_player/data/library/library_service.dart';
import 'package:media_player/data/models/items_page.dart';
import 'package:media_player/data/models/media_item.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/features/search/search_controller.dart';

import '../../support/fake_library_service.dart';
import '../../support/fake_poster_cache.dart';

/// Gates every search behind a completer so tests can finish an older query
/// after a newer one and prove the stale answer is discarded. The inner fake
/// only records the request; answers arrive when the test completes a gate.
class GatedLibrary extends FakeLibraryService {
  final List<Completer<ItemsPage>> gates = <Completer<ItemsPage>>[];

  @override
  Future<ItemsPage> search(
    String term, {
    String types = 'Movie,Series',
    int limit = 60,
  }) {
    unawaited(super.search(term, types: types, limit: limit));
    final gate = Completer<ItemsPage>();
    gates.add(gate);
    return gate.future;
  }
}

MediaItem item(String id, String name, {String type = 'Movie'}) {
  return MediaItem(id: id, name: name, type: type);
}

void main() {
  late FakeLibraryService library;
  late InMemoryKeyValueStore store;
  LibrarySearchController? controller;

  setUp(() {
    library = FakeLibraryService();
    store = InMemoryKeyValueStore();
  });

  tearDown(() => controller?.dispose());

  LibrarySearchController build({LibraryService? service}) {
    return controller = LibrarySearchController(
      service ?? library,
      FakePosterCache(),
      store: store,
    );
  }

  test('typing settles into a single debounced request', () {
    fakeAsync((async) {
      final search = build();
      library.searchResults = <MediaItem>[item('m-1', '冰海战记')];

      search.setQuery('冰');
      async.elapse(const Duration(milliseconds: 200));
      search.setQuery('冰海');
      async.elapse(const Duration(milliseconds: 200));
      expect(library.searchRequests, isEmpty);

      async.elapse(const Duration(milliseconds: 150));
      expect(library.searchRequests, hasLength(1));
      expect(library.searchRequests.single.term, '冰海');
      expect(search.state.results.single.id, 'm-1');
      expect(search.state.loaded, isTrue);
    });
  });

  test('submit skips the remaining debounce', () {
    fakeAsync((async) {
      final search = build();
      library.searchResults = <MediaItem>[item('m-1', '冰海战记')];

      search.setQuery('冰海');
      search.submit();
      async.flushMicrotasks();

      expect(library.searchRequests, hasLength(1));
    });
  });

  test('an older answer never overwrites a newer one', () {
    fakeAsync((async) {
      final gated = GatedLibrary();
      final search = build(service: gated);
      gated.searchResults = <MediaItem>[item('m-1', '旧结果')];

      search.setQuery('旧');
      async.elapse(const Duration(milliseconds: 350));
      gated.searchResults = <MediaItem>[item('m-2', '新结果')];
      search.setQuery('新');
      async.elapse(const Duration(milliseconds: 350));
      expect(gated.gates, hasLength(2));

      gated.gates[1].complete(
        const ItemsPage(
          items: <MediaItem>[],
          totalRecordCount: 0,
          startIndex: 0,
        ),
      );
      async.flushMicrotasks();
      // The newer query finished first with its own (empty) answer.
      expect(search.state.results, isEmpty);

      gated.gates[0].complete(
        ItemsPage(
          items: <MediaItem>[item('m-1', '旧结果')],
          totalRecordCount: 1,
          startIndex: 0,
        ),
      );
      async.flushMicrotasks();

      expect(search.state.results, isEmpty);
      expect(search.state.query, '新');
    });
  });

  test('clearing the query resets results without a request', () {
    fakeAsync((async) {
      final search = build();
      library.searchResults = <MediaItem>[item('m-1', '冰海战记')];
      search.setQuery('冰海');
      async.elapse(const Duration(milliseconds: 350));
      expect(search.state.results, hasLength(1));

      search.setQuery('  ');
      async.elapse(const Duration(milliseconds: 350));

      expect(search.state.results, isEmpty);
      expect(search.state.loaded, isFalse);
      expect(library.searchRequests, hasLength(1));
    });
  });

  test('type filters combine, and 全部 clears them (S50)', () {
    fakeAsync((async) {
      final search = build();
      search.setQuery('冰海');
      search.submit();
      async.flushMicrotasks();
      expect(library.searchRequests.last.types, 'Movie,Series,BoxSet,Person');

      search.toggleFilter(SearchFilter.collections);
      async.flushMicrotasks();
      expect(library.searchRequests.last.types, 'BoxSet');

      search.toggleFilter(SearchFilter.persons);
      async.flushMicrotasks();
      expect(library.searchRequests.last.types, 'BoxSet,Person');

      search.toggleFilter(SearchFilter.all);
      async.flushMicrotasks();
      expect(search.state.filters, <SearchFilter>{SearchFilter.all});
      expect(library.searchRequests.last.types, 'Movie,Series,BoxSet,Person');
    });
  });
  test('toggling a type off falls back to 全部 (S50)', () {
    fakeAsync((async) {
      final search = build();
      library.searchResults = <MediaItem>[
        item('m-1', '冰海战记 剧场版'),
        item('s-1', '冰海战记', type: 'Series'),
      ];
      search.setQuery('冰海');
      async.elapse(const Duration(milliseconds: 350));
      expect(search.state.results, hasLength(2));

      search.toggleFilter(SearchFilter.series);
      async.flushMicrotasks();

      expect(library.searchRequests.last.types, 'Series');
      expect(search.state.results.single.id, 's-1');

      search.toggleFilter(SearchFilter.series);
      async.flushMicrotasks();
      expect(search.state.filters, <SearchFilter>{SearchFilter.all});
      expect(library.searchRequests.last.types, 'Movie,Series,BoxSet,Person');
    });
  });

  test('a network failure becomes copy, not an exception string', () {
    fakeAsync((async) {
      final search = build();
      library.searchFailure = EmbyException(AppErrorCode.networkUnreachable);

      search.setQuery('冰海');
      async.elapse(const Duration(milliseconds: 350));

      expect(search.state.error, '无法连接服务器，请检查网络');
      expect(search.state.unauthorized, isFalse);
      expect(search.state.loaded, isTrue);
    });
  });

  test('a 401 flags unauthorized for the login redirect', () {
    fakeAsync((async) {
      final search = build();
      library.searchFailure = EmbyException(AppErrorCode.unauthorized);

      search.setQuery('冰海');
      async.elapse(const Duration(milliseconds: 350));

      expect(search.state.unauthorized, isTrue);
      expect(search.state.error, isNull);
    });
  });

  test('successful terms are remembered, deduped and capped', () {
    fakeAsync((async) {
      final search = build();
      library.searchResults = <MediaItem>[item('m-1', '结果')];

      for (int i = 0; i < 10; i++) {
        search.setQuery('词$i');
        async.elapse(const Duration(milliseconds: 350));
      }
      search.setQuery('词0');
      async.elapse(const Duration(milliseconds: 350));

      expect(search.state.history, hasLength(8));
      expect(search.state.history.first, '词0');
      expect(search.state.history.where((t) => t == '词0'), hasLength(1));
    });
  });

  test('history survives a new controller through the store', () {
    fakeAsync((async) {
      final first = build();
      library.searchResults = <MediaItem>[item('m-1', '结果')];
      first.setQuery('冰海');
      async.elapse(const Duration(milliseconds: 350));
      first.dispose();
      controller = null;

      final second = build();
      second.loadHistory();
      async.flushMicrotasks();

      expect(second.state.history, <String>['冰海']);
    });
  });

  test('corrupt history JSON is ignored', () {
    fakeAsync((async) {
      store.write(LibrarySearchController.historyKey, '{not json');
      final search = build();

      search.loadHistory();
      async.flushMicrotasks();

      expect(search.state.history, isEmpty);
    });
  });
}
