import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/data/library/library_service.dart';
import 'package:media_player/data/models/media_item.dart';
import 'package:media_player/data/moviepilot/models/media_request.dart';
import 'package:media_player/data/moviepilot/models/moviepilot_config.dart';
import 'package:media_player/data/moviepilot/models/mp_media_info.dart';
import 'package:media_player/data/moviepilot/models/mp_season.dart';
import 'package:media_player/data/moviepilot/models/mp_subscribe.dart';
import 'package:media_player/data/moviepilot/moviepilot_service.dart';
import 'package:media_player/data/moviepilot/progress/poll_snapshot.dart';
import 'package:media_player/data/moviepilot/progress/request_notification.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/data/storage/moviepilot_config_store.dart';
import 'package:media_player/data/storage/request_store.dart';
import 'package:media_player/features/request/request_controller.dart';

import '../../support/fake_library_service.dart';
import '../../support/fake_moviepilot_service.dart';

class _Harness {
  _Harness({LibraryService? library}) {
    service = FakeMoviePilotService();
    kv = InMemoryKeyValueStore();
    configStore = MoviePilotConfigStore(kv);
    requestStore = RequestStore(kv);
    libraryService = library;
    heartbeat = StreamController<void>.broadcast();
  }

  late final FakeMoviePilotService service;
  late final InMemoryKeyValueStore kv;
  late final MoviePilotConfigStore configStore;
  late final RequestStore requestStore;
  late final LibraryService? libraryService;
  late final StreamController<void> heartbeat;
  int ids = 0;

  RequestController build({Future<void> Function(Duration)? delay}) {
    return RequestController(
      service: service,
      requestStore: requestStore,
      configStore: configStore,
      library: libraryService,
      heartbeat: heartbeat.stream,
      delay: delay ?? (Duration _) async {},
      clock: () => DateTime.utc(2026, 1, 10, 12),
      idGenerator: () => 'req-${++ids}',
    );
  }

  Future<void> configure() => configStore.write(
    const MoviePilotConfig(
      baseUrl: 'http://nas:3002',
      username: 'admin',
      accessToken: 'token',
    ),
  );
}

Future<void> waitFor(bool Function() predicate, {String? reason}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out${reason == null ? '' : ' waiting for $reason'}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  group('load', () {
    test(
      'without a connection the page reports configuration missing',
      () async {
        final harness = _Harness();
        final controller = harness.build();

        await controller.load();

        expect(controller.state.configured, isFalse);
        expect(controller.state.needsConfiguration, isTrue);
        expect(harness.service.pollCalls, 0);
        controller.dispose();
      },
    );

    test('restores the stored requests before the first round', () async {
      final harness = _Harness();
      await harness.configure();
      final stored = MediaRequest(
        id: 'stored',
        ref: const MpMediaRef(source: MpMediaSource.tmdb, mediaId: '693134'),
        type: MpMediaType.movie,
        title: '沙丘2',
        subscribeId: 100,
        stage: RequestStage.downloading,
        progressPercent: 0.4,
        createdAt: DateTime.utc(2026, 1, 1),
      );
      await harness.requestStore.write(<MediaRequest>[stored]);

      final controller = harness.build();
      await controller.load();

      final request = controller.state.requests.single;
      expect(request.id, 'stored');
      // The round ran and re-derived the stage from the (empty) snapshot, but
      // the record survived; the progress cache is what the first frame shows.
      expect(request.title, '沙丘2');
      controller.dispose();
    });

    test('a corrupt store still opens the page', () async {
      final harness = _Harness();
      await harness.configure();
      await harness.kv.write(RequestStore.key, 'not json');

      final controller = harness.build();
      await controller.load();

      expect(controller.state.loaded, isTrue);
      expect(controller.state.requests, isEmpty);
      expect(controller.state.configured, isTrue);
      controller.dispose();
    });
  });

  group('polling', () {
    test('heartbeat ticks run a round while a request is under way', () async {
      final harness = _Harness();
      await harness.configure();
      final controller = harness.build();
      await controller.load();
      // A stored request gives the heartbeat something to watch.
      harness.service.snapshot = PollSnapshot(
        subscribes: <MpSubscribe>[fakeSubscribe()],
      );
      await controller.subscribe(fakeMedia());
      final initial = harness.service.pollCalls;

      harness.heartbeat.add(null);
      await waitFor(() => harness.service.pollCalls > initial);

      controller.dispose();
    });

    test('the heartbeat idles when nothing can change', () async {
      final harness = _Harness();
      await harness.configure();
      final controller = harness.build();
      await controller.load();
      final initial = harness.service.pollCalls;

      harness.heartbeat.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(harness.service.pollCalls, initial);
      expect(controller.needsPolling, isFalse);
      controller.dispose();
    });

    test('dispose stops the heartbeat', () async {
      final harness = _Harness();
      await harness.configure();
      final controller = harness.build();
      await controller.load();
      controller.dispose();

      harness.heartbeat.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(harness.service.pollCalls, 1);
    });

    test('an overlapping round is skipped rather than queued', () async {
      final harness = _Harness();
      await harness.configure();
      final controller = harness.build();
      await controller.load();
      // The load itself ran one round; hold the next one open.
      final gate = Completer<void>();
      harness.service.pollHold = gate.future;

      final first = controller.pollRound();
      final second = controller.pollRound();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(harness.service.pollCalls, 2);
      gate.complete();
      await first;
      await second;
      controller.dispose();
    });

    test('an idle round asks only for the subscription list', () async {
      final harness = _Harness();
      await harness.configure();
      final controller = harness.build();
      await controller.load();

      expect(harness.service.pollNeedsTasks, <bool>[false]);
      controller.dispose();
    });

    test('a round with progress in flight loads the task half', () async {
      final harness = _Harness();
      await harness.configure();
      final controller = harness.build();
      await controller.load();

      // MoviePilot already handed this subscription a download, so the request
      // is past "submitted" and the next round must fetch the task endpoints.
      harness.service.snapshot = PollSnapshot(
        subscribes: <MpSubscribe>[fakeSubscribe(submittedCount: 1)],
      );
      harness.service.searchResults = <String, List<MpMediaInfo>>{
        '沙丘': <MpMediaInfo>[fakeMedia()],
      };
      await controller.search('沙丘');
      await controller.subscribe(controller.state.searchResults.single);
      // subscribe() schedules its own round; wait for it to derive a stage.
      await waitFor(
        () =>
            controller.state.requests.single.stage == RequestStage.downloading,
        reason: 'the post-subscribe round to derive downloading',
      );
      await controller.refresh();

      expect(harness.service.pollNeedsTasks.last, isTrue);
      controller.dispose();
    });

    test('history is requested for the media types under way', () async {
      final harness = _Harness();
      await harness.configure();
      final controller = harness.build();
      await controller.load();
      harness.service.searchResults = <String, List<MpMediaInfo>>{
        'show': <MpMediaInfo>[
          fakeMedia(mediaId: '1399', type: MpMediaType.series, title: 'Show'),
        ],
      };
      await controller.search('show');

      await controller.subscribe(
        controller.state.searchResults.single,
        season: 1,
      );
      await controller.refresh();

      expect(harness.service.pollHistoryTypes.last, <MpMediaType>{
        MpMediaType.series,
      });
      controller.dispose();
    });
  });

  group('search', () {
    test('a result list belongs to the text that produced it', () async {
      final harness = _Harness();
      await harness.configure();
      harness.service.searchResults = <String, List<MpMediaInfo>>{
        'dune': <MpMediaInfo>[fakeMedia(title: 'Dune')],
      };
      final controller = harness.build();
      await controller.load();

      await controller.search('  dune  ');

      expect(harness.service.searchQueries, <String>['dune']);
      expect(controller.state.query, 'dune');
      expect(controller.state.searchResults.single.title, 'Dune');
      expect(controller.state.searching, isFalse);
      controller.dispose();
    });

    test('a blank query makes no request', () async {
      final harness = _Harness();
      await harness.configure();
      final controller = harness.build();
      await controller.load();

      await controller.search('   ');

      expect(harness.service.searchQueries, isEmpty);
      controller.dispose();
    });

    test('a stale answer is dropped when a newer search replaced it', () async {
      final harness = _Harness();
      await harness.configure();
      final gate = Completer<void>();
      harness.service.searchResults = <String, List<MpMediaInfo>>{
        'first': <MpMediaInfo>[fakeMedia(title: 'First')],
        'second': <MpMediaInfo>[fakeMedia(title: 'Second')],
      };
      final controller = harness.build();
      await controller.load();

      // Make the first search slow by having the gated service await the gate.
      final slow = FakeMoviePilotService();
      slow.searchResults = harness.service.searchResults;
      final controller2 = RequestController(
        service: _GatedService(slow, gate),
        requestStore: harness.requestStore,
        configStore: harness.configStore,
        heartbeat: const Stream<void>.empty(),
        delay: (Duration _) async {},
        idGenerator: () => 'r',
      );
      await controller2.load();

      final first = controller2.search('first');
      final second = controller2.search('second');
      gate.complete();
      await Future.wait(<Future<void>>[first, second]);

      expect(controller2.state.query, 'second');
      expect(controller2.state.searchResults.single.title, 'Second');
      controller.dispose();
      controller2.dispose();
    });

    test('a search failure shows copy, not the exception', () async {
      final harness = _Harness();
      await harness.configure();
      harness.service.searchFailure = mpFailure(
        AppErrorCode.networkUnreachable,
      );
      final controller = harness.build();
      await controller.load();

      await controller.search('dune');

      expect(controller.state.searchError, '无法连接 MoviePilot，请检查网络');
      expect(controller.state.searching, isFalse);
      controller.dispose();
    });

    test('a rejected token marks the connection invalid', () async {
      final harness = _Harness();
      await harness.configure();
      harness.service.searchFailure = mpFailure(AppErrorCode.unauthorized);
      final controller = harness.build();
      await controller.load();

      await controller.search('dune');

      expect(controller.state.configInvalid, isTrue);
      expect(controller.state.unauthorizedToken, isTrue);
      controller.dispose();
    });
  });

  group('seasons', () {
    test('returns the season list', () async {
      final harness = _Harness();
      await harness.configure();
      harness.service.seasonsByMediaId = <String, List<MpSeason>>{
        '1399': <MpSeason>[
          const MpSeason(seasonNumber: 1, episodeCount: 10),
          const MpSeason(seasonNumber: 2, episodeCount: 8),
        ],
      };
      final controller = harness.build();
      await controller.load();

      final choice = await controller.seasons(
        fakeMedia(mediaId: '1399', type: MpMediaType.series, title: 'Show'),
      );

      expect(choice.seasons, hasLength(2));
      expect(choice.error, isNull);
      controller.dispose();
    });

    test('a failure becomes an error on the choice', () async {
      final harness = _Harness();
      await harness.configure();
      harness.service.seasonsFailure = mpFailure(AppErrorCode.serverError);
      final controller = harness.build();
      await controller.load();

      final choice = await controller.seasons(fakeMedia());

      expect(choice.seasons, isEmpty);
      expect(choice.error, isNotNull);
      controller.dispose();
    });
  });

  group('subscribe', () {
    test('creates the subscription and a local record', () async {
      final harness = _Harness();
      await harness.configure();
      final controller = harness.build();
      await controller.load();
      final media = fakeMedia();
      harness.service.searchResults = <String, List<MpMediaInfo>>{
        'x': <MpMediaInfo>[media],
      };

      final record = await controller.subscribe(media);

      expect(record, isNotNull);
      expect(record!.subscribeId, 100);
      expect(record.stage, RequestStage.submitted);
      expect(record.title, '沙丘2');
      expect(harness.service.createRequests.single.type, MpMediaType.movie);
      expect(controller.state.requests, hasLength(1));
      // The request was persisted.
      expect((await harness.requestStore.read()).single.id, record.id);
      // And MoviePilot was asked to search immediately.
      expect(harness.service.searchNowRequests, <int>[100]);
      controller.dispose();
    });

    test('a series subscription carries the chosen season', () async {
      final harness = _Harness();
      await harness.configure();
      final controller = harness.build();
      await controller.load();
      final media = fakeMedia(
        mediaId: '1399',
        type: MpMediaType.series,
        title: 'Show',
      );

      final record = await controller.subscribe(media, season: 2);

      expect(record!.season, 2);
      expect(harness.service.createRequests.single.season, 2);
      controller.dispose();
    });

    test(
      'a title already in the library becomes playable without subscribing',
      () async {
        final harness = _Harness();
        await harness.configure();
        harness.service.existingItems = <String, String>{
          'themoviedb:693134#s0': 'emby-42',
        };
        final controller = harness.build();
        await controller.load();

        final record = await controller.subscribe(fakeMedia());

        expect(record!.stage, RequestStage.inLibrary);
        expect(record.embyItemId, 'emby-42');
        expect(harness.service.createRequests, isEmpty);
        expect(record.message, contains('媒体库已有'));
        controller.dispose();
      },
    );

    test('the same media and season is not subscribed twice', () async {
      final harness = _Harness();
      await harness.configure();
      final controller = harness.build();
      await controller.load();
      final media = fakeMedia();

      final first = await controller.subscribe(media);
      final second = await controller.subscribe(media);

      expect(second!.id, first!.id);
      expect(harness.service.createRequests, hasLength(1));
      expect(controller.state.requests, hasLength(1));
      controller.dispose();
    });

    test('two seasons of the same show are two records', () async {
      final harness = _Harness();
      await harness.configure();
      harness.service.createdIds = <int>[100, 101];
      final controller = harness.build();
      await controller.load();
      final media = fakeMedia(
        mediaId: '1399',
        type: MpMediaType.series,
        title: 'Show',
      );

      await controller.subscribe(media, season: 1);
      await controller.subscribe(media, season: 2);

      expect(controller.state.requests, hasLength(2));
      expect(harness.service.createRequests, hasLength(2));
      controller.dispose();
    });

    test('a failed create surfaces copy and records nothing', () async {
      final harness = _Harness();
      await harness.configure();
      harness.service.createFailure = mpFailure(AppErrorCode.serverError);
      final controller = harness.build();
      await controller.load();

      final record = await controller.subscribe(fakeMedia());

      expect(record, isNull);
      expect(controller.state.requests, isEmpty);
      expect(controller.state.pollError, isNotNull);
      expect(controller.state.subscribeInFlight, isFalse);
      controller.dispose();
    });
  });

  group('actions', () {
    Future<(RequestController, _Harness, MediaRequest)> subscribed() async {
      final harness = _Harness();
      await harness.configure();
      final controller = harness.build();
      await controller.load();
      final record = await controller.subscribe(fakeMedia());
      return (controller, harness, record!);
    }

    test('searchNow posts the subscription id', () async {
      final (controller, harness, request) = await subscribed();

      await controller.searchNow(request);

      expect(harness.service.searchNowRequests, contains(100));
      expect(controller.state.busyRequestIds, isEmpty);
      controller.dispose();
    });

    test('searchNow on an archived request does nothing', () async {
      final (controller, harness, request) = await subscribed();
      final archived = request.copyWith(subscribeId: null);

      await controller.searchNow(archived);

      expect(harness.service.searchNowRequests, hasLength(1));
      controller.dispose();
    });

    test('cancel deletes the subscription and the local record', () async {
      final (controller, harness, request) = await subscribed();

      await controller.cancel(request);

      expect(harness.service.cancelRequests, <int>[100]);
      expect(controller.state.requests, isEmpty);
      expect(await harness.requestStore.read(), isEmpty);
      controller.dispose();
    });

    test(
      'an archived request is removed locally without a delete call',
      () async {
        final (controller, harness, request) = await subscribed();
        final archived = request.copyWith(archived: true);

        await controller.cancel(archived);

        expect(harness.service.cancelRequests, isEmpty);
        expect(controller.state.requests, isEmpty);
        controller.dispose();
      },
    );

    test('a failed cancel keeps the record so the user can retry', () async {
      final (controller, harness, request) = await subscribed();
      harness.service.cancelFailure = mpFailure(AppErrorCode.serverError);

      await controller.cancel(request);

      expect(controller.state.requests, hasLength(1));
      expect(controller.state.busyRequestIds, isEmpty);
      expect(controller.state.requests.single.message, contains('重试'));
      controller.dispose();
    });
  });

  group('sharing between pages', () {
    test('pause stops the heartbeat and resume starts it again', () async {
      final harness = _Harness();
      await harness.configure();
      final controller = harness.build();
      await controller.load();
      final record = await controller.subscribe(fakeMedia());

      await controller.pausePolling();
      final afterPause = harness.service.pollCalls;
      harness.heartbeat.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(harness.service.pollCalls, afterPause);

      await controller.resumePolling();
      harness.heartbeat.add(null);
      await waitFor(() => harness.service.pollCalls > afterPause);

      // Pausing must not lose anything: the record is still there.
      expect(controller.state.requests.single.id, record!.id);
      controller.dispose();
    });

    test('pausing and resuming twice keeps the poll alive', () async {
      // Regression: the default beat used to be a single-subscription
      // Stream.periodic, so the second resume threw
      // "Stream has already been listened to" and silently stopped polling for
      // good (the record sat on 已提交 for 28 minutes on a real instance).
      final harness = _Harness();
      await harness.configure();
      // No injected heartbeat: this exercises the controller's own timer.
      final controller = RequestController(
        service: harness.service,
        requestStore: harness.requestStore,
        configStore: harness.configStore,
        delay: (Duration _) async {},
        clock: () => DateTime.utc(2026, 1, 10, 12),
        idGenerator: () => 'req-1',
        pollInterval: const Duration(milliseconds: 20),
      );
      await controller.load();
      harness.service.snapshot = PollSnapshot(
        subscribes: <MpSubscribe>[fakeSubscribe()],
      );
      await controller.subscribe(fakeMedia());

      for (var i = 0; i < 3; i++) {
        await controller.pausePolling();
        final before = harness.service.pollCalls;
        await controller.resumePolling();
        await waitFor(
          () => harness.service.pollCalls > before,
          reason: 'poll to resume after pause cycle ${i + 1}',
        );
      }

      controller.dispose();
    });

    test('resume on a disposed controller is a no-op', () async {
      final harness = _Harness();
      await harness.configure();
      final controller = harness.build();
      await controller.load();
      controller.dispose();

      await controller.resumePolling();

      // Nothing scheduled: a tick from a stale subscription must not fire.
      expect(harness.service.pollCalls, 1);
    });
  });

  group('errors', () {
    test('a network failure keeps the last snapshot and retries', () async {
      final harness = _Harness();
      await harness.configure();
      final controller = harness.build();
      await controller.load();
      final record = await controller.subscribe(fakeMedia());
      harness.service.pollFailure = mpFailure(AppErrorCode.networkUnreachable);

      await controller.refresh();

      expect(controller.state.pollError, '无法连接 MoviePilot，请检查网络');
      // The request and its last known stage survive.
      expect(controller.state.requests.single.id, record!.id);
      expect(controller.state.polling, isFalse);
      controller.dispose();
    });

    test('a rejected token stops polling and flags the connection', () async {
      final harness = _Harness();
      await harness.configure();
      final controller = harness.build();
      await controller.load();
      harness.service.pollFailure = mpFailure(AppErrorCode.unauthorized);

      await controller.refresh();
      final callsAfterFailure = harness.service.pollCalls;
      harness.heartbeat.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(controller.state.configInvalid, isTrue);
      expect(controller.state.unauthorizedToken, isTrue);
      expect(harness.service.pollCalls, callsAfterFailure);
      controller.dispose();
    });

    test('a cleared connection switches to the configuration state', () async {
      final harness = _Harness();
      await harness.configure();
      final controller = harness.build();
      await controller.load();

      await controller.clearConnection();

      expect(controller.state.configured, isFalse);
      expect(controller.state.configInvalid, isTrue);
      expect(await harness.configStore.read(), isNull);
      controller.dispose();
    });

    test(
      'a poll that reports notConfigured becomes the config state',
      () async {
        final harness = _Harness();
        await harness.configure();
        final controller = harness.build();
        await controller.load();
        harness.service.pollFailure = mpFailure(AppErrorCode.notConfigured);

        await controller.refresh();

        expect(controller.state.configured, isFalse);
        expect(controller.state.configInvalid, isTrue);
        controller.dispose();
      },
    );
  });

  group('connection', () {
    test('saveConnection verifies, persists and resumes polling', () async {
      final harness = _Harness();
      final controller = harness.build();
      await controller.load();
      expect(controller.state.needsConfiguration, isTrue);

      final result = await controller.saveConnection(
        config: const MoviePilotConfig(
          baseUrl: 'http://nas:3002',
          username: 'admin',
          accessToken: 'token',
        ),
      );

      expect(result.ok, isTrue);
      expect(harness.service.connectionTests, hasLength(1));
      expect(await harness.configStore.read(), isNotNull);
      expect(controller.state.configured, isTrue);
      controller.dispose();
    });

    test('a rejected token is not persisted', () async {
      final harness = _Harness();
      harness.service.testFailure = mpFailure(AppErrorCode.unauthorized);
      final controller = harness.build();
      await controller.load();

      final result = await controller.saveConnection(
        config: const MoviePilotConfig(
          baseUrl: 'http://nas:3002',
          username: 'admin',
          accessToken: 'bad',
        ),
      );

      expect(result.ok, isFalse);
      expect(result.error, contains('登录'));
      expect(await harness.configStore.read(), isNull);
      controller.dispose();
    });
  });

  group('notifications', () {
    test(
      'a request that becomes playable notifies its subscribers once',
      () async {
        final library = FakeLibraryService()
          ..lookupItems = <MediaItem>[
            const MediaItem(
              id: 'emby-7',
              name: '沙丘2',
              type: 'Movie',
              productionYear: 2024,
            ),
          ];
        final harness = _Harness(library: library);
        await harness.configure();
        final controller = harness.build();
        await controller.load();
        final events = <RequestNotification>[];
        final unsubscribe = controller.addNotificationListener(events.add);
        await controller.subscribe(fakeMedia());

        harness.service.snapshot = PollSnapshot(
          movieHistory: <MpSubscribe>[fakeSubscribe()],
        );
        await controller.refresh();
        await controller.refresh();

        expect(events, hasLength(1));
        expect(events.single.requestId, controller.state.requests.single.id);
        expect(events.single.body, '已入库，可以播放');
        expect(events.single.embyItemId, 'emby-7');
        unsubscribe();
        controller.dispose();
      },
    );

    test('unsubscribing stops the events', () async {
      final library = FakeLibraryService()
        ..lookupItems = <MediaItem>[
          const MediaItem(
            id: 'emby-7',
            name: '沙丘2',
            type: 'Movie',
            productionYear: 2024,
          ),
        ];
      final harness = _Harness(library: library);
      await harness.configure();
      final controller = harness.build();
      await controller.load();
      final events = <RequestNotification>[];
      final unsubscribe = controller.addNotificationListener(events.add);
      await controller.subscribe(fakeMedia());
      unsubscribe();

      harness.service.snapshot = PollSnapshot(
        movieHistory: <MpSubscribe>[fakeSubscribe()],
      );
      await controller.refresh();

      expect(events, isEmpty);
      controller.dispose();
    });

    test(
      'a throwing listener does not break the round or other listeners',
      () async {
        final library = FakeLibraryService()
          ..lookupItems = <MediaItem>[
            const MediaItem(
              id: 'emby-7',
              name: '沙丘2',
              type: 'Movie',
              productionYear: 2024,
            ),
          ];
        final harness = _Harness(library: library);
        await harness.configure();
        final controller = harness.build();
        await controller.load();
        final events = <RequestNotification>[];
        controller.addNotificationListener((_) => throw StateError('boom'));
        controller.addNotificationListener(events.add);
        await controller.subscribe(fakeMedia());

        harness.service.snapshot = PollSnapshot(
          movieHistory: <MpSubscribe>[fakeSubscribe()],
        );
        await controller.refresh();

        expect(events, hasLength(1));
        expect(controller.state.polling, isFalse);
        expect(controller.state.requests.single.stage, RequestStage.inLibrary);
        controller.dispose();
      },
    );

    test(
      'startWatching keeps the heartbeat running with no page open',
      () async {
        final harness = _Harness();
        await harness.configure();
        final controller = harness.build();
        await controller.load();
        await controller.subscribe(fakeMedia());

        await controller.startWatching();
        final afterStart = harness.service.pollCalls;
        // No page is mounted and none ever called resume: the tick itself must
        // still produce a round, which is what makes an off-screen 求片 notify.
        harness.heartbeat.add(null);
        await waitFor(
          () => harness.service.pollCalls > afterStart,
          reason: 'the app-level heartbeat to poll',
        );

        controller.dispose();
      },
    );
  });

  group('Emby promotion', () {
    test('a finished request becomes playable when Emby has the item', () async {
      final library = FakeLibraryService()
        ..lookupItems = <MediaItem>[
          const MediaItem(
            id: 'emby-7',
            name: '沙丘2',
            type: 'Movie',
            productionYear: 2024,
          ),
        ];
      final harness = _Harness(library: library);
      await harness.configure();
      final controller = harness.build();
      await controller.load();
      final record = await controller.subscribe(fakeMedia());

      // The subscription is gone from the active list: MoviePilot archived it,
      // which is the "files are in the library" signal.
      harness.service.snapshot = PollSnapshot(
        movieHistory: <MpSubscribe>[fakeSubscribe()],
      );
      await controller.refresh();

      final updated = controller.state.requests.single;
      expect(updated.id, record!.id);
      expect(updated.stage, RequestStage.inLibrary);
      expect(updated.embyItemId, 'emby-7');
      expect(library.tmdbLookups, contains(693134));
      controller.dispose();
    });

    test(
      'an unreachable Emby leaves the request pending, not broken',
      () async {
        final library = FakeLibraryService()
          ..lookupFailure = Exception('emby down');
        final harness = _Harness(library: library);
        await harness.configure();
        final controller = harness.build();
        await controller.load();
        await controller.subscribe(fakeMedia());

        harness.service.snapshot = PollSnapshot(
          movieHistory: <MpSubscribe>[fakeSubscribe()],
        );
        await controller.refresh();

        expect(
          controller.state.requests.single.stage,
          RequestStage.organizedPendingLibrary,
        );
        expect(controller.state.pollError, isNull);
        controller.dispose();
      },
    );

    test('a title lookup is used when the request has no TMDB id', () async {
      final library = FakeLibraryService()
        ..lookupItems = <MediaItem>[
          const MediaItem(
            id: 'emby-8',
            name: '沙丘2',
            type: 'Movie',
            productionYear: 2024,
          ),
        ];
      final harness = _Harness(library: library);
      await harness.configure();
      final controller = harness.build();
      await controller.load();
      await controller.subscribe(fakeMedia(tmdbId: null));

      harness.service.snapshot = PollSnapshot(
        movieHistory: <MpSubscribe>[fakeSubscribe()],
      );
      await controller.refresh();

      expect(controller.state.requests.single.embyItemId, 'emby-8');
      expect(library.titleLookups, contains('沙丘2'));
      controller.dispose();
    });
  });
}

/// Wraps a service so the first `search` call waits for [gate].
class _GatedService implements MoviePilotService {
  _GatedService(this._inner, this._gate);

  final FakeMoviePilotService _inner;
  final Completer<void> _gate;
  bool _first = true;

  @override
  Future<List<MpMediaInfo>> search(String title) async {
    if (_first) {
      _first = false;
      await _gate.future;
      // The gated call answers with the *first* query's results so a stale
      // answer is distinguishable from the newest one.
      return _inner.searchResults['first'] ?? const <MpMediaInfo>[];
    }
    return _inner.search(title);
  }

  @override
  Future<PollSnapshot> poll({
    bool needsTasks = true,
    Set<MpMediaType> historyTypes = const <MpMediaType>{},
  }) => _inner.poll(needsTasks: needsTasks, historyTypes: historyTypes);

  @override
  Future<MoviePilotConfig> login({
    required String baseUrl,
    required String username,
    required String password,
    String? otp,
  }) => _inner.login(
    baseUrl: baseUrl,
    username: username,
    password: password,
    otp: otp,
  );

  @override
  Future<MoviePilotConfig> testConnection(MoviePilotConfig config) =>
      _inner.testConnection(config);

  @override
  Future<List<MpSeason>> seasons(MpMediaInfo media) => _inner.seasons(media);

  @override
  Future<String?> existingItemId({
    required MpMediaRef ref,
    required MpMediaType type,
    int season = 0,
  }) => _inner.existingItemId(ref: ref, type: type, season: season);

  @override
  Future<int> createSubscription(MpSubscribeDraft draft) =>
      _inner.createSubscription(draft);

  @override
  Future<void> searchNow(int subscribeId) => _inner.searchNow(subscribeId);

  @override
  Future<void> cancelSubscription(int subscribeId) =>
      _inner.cancelSubscription(subscribeId);
}
