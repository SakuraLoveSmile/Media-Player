import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/moviepilot/models/media_request.dart';
import 'package:media_player/data/moviepilot/models/mp_media_info.dart';
import 'package:media_player/data/moviepilot/progress/request_notification.dart';

MediaRequest _request({
  String id = 'req-1',
  RequestStage stage = RequestStage.searching,
  MpMediaType type = MpMediaType.movie,
  int season = 0,
  String? embyItemId,
  String title = '沙丘',
}) {
  return MediaRequest(
    id: id,
    ref: const MpMediaRef(
      source: MpMediaSource.tmdb,
      mediaId: '438631',
      tmdbId: 438631,
      title: '沙丘',
      year: '2021',
    ),
    type: type,
    title: title,
    year: '2021',
    season: season,
    createdAt: DateTime.utc(2026, 1, 1),
    stage: stage,
    embyItemId: embyItemId,
  );
}

void main() {
  group('requestNotificationsFor', () {
    test('announces a request that just became playable', () {
      final events = requestNotificationsFor(
        before: <MediaRequest>[
          _request(stage: RequestStage.organizedPendingLibrary),
        ],
        after: <MediaRequest>[
          _request(stage: RequestStage.inLibrary, embyItemId: 'emby-9'),
        ],
      );

      expect(events, hasLength(1));
      final event = events.single;
      expect(event.requestId, 'req-1');
      expect(event.title, '沙丘');
      expect(event.body, '已入库，可以播放');
      expect(event.embyItemId, 'emby-9');
      expect(event.isSeries, isFalse);
      expect(event.dedupeKey, 'request:req-1:inLibrary');
    });

    test('a series names the season in the body', () {
      final events = requestNotificationsFor(
        before: <MediaRequest>[
          _request(
            type: MpMediaType.series,
            season: 2,
            stage: RequestStage.organizing,
          ),
        ],
        after: <MediaRequest>[
          _request(
            type: MpMediaType.series,
            season: 2,
            stage: RequestStage.inLibrary,
            embyItemId: 'series-1',
          ),
        ],
      );

      expect(events.single.body, '第 2 季 已入库，可以播放');
      expect(events.single.isSeries, isTrue);
    });

    test(
      'a request already in the library when the app starts is not news',
      () {
        final events = requestNotificationsFor(
          before: <MediaRequest>[
            _request(stage: RequestStage.inLibrary, embyItemId: 'emby-9'),
          ],
          after: <MediaRequest>[
            _request(stage: RequestStage.inLibrary, embyItemId: 'emby-9'),
          ],
        );

        expect(events, isEmpty);
      },
    );

    test('a newly created request announces nothing', () {
      // The user is looking at the page that just created it.
      final events = requestNotificationsFor(
        before: const <MediaRequest>[],
        after: <MediaRequest>[
          _request(stage: RequestStage.inLibrary, embyItemId: 'emby-9'),
        ],
      );

      expect(events, isEmpty);
    });

    test('a cancelled request never announces anything', () {
      final events = requestNotificationsFor(
        before: <MediaRequest>[
          _request(stage: RequestStage.organizedPendingLibrary),
        ],
        after: <MediaRequest>[_request(stage: RequestStage.cancelled)],
      );

      expect(events, isEmpty);
    });

    test('forward progress between other stages announces nothing', () {
      final events = requestNotificationsFor(
        before: <MediaRequest>[_request(stage: RequestStage.searching)],
        after: <MediaRequest>[_request(stage: RequestStage.downloading)],
      );

      expect(events, isEmpty);
    });

    test('a request that shrank back to searching announces nothing', () {
      // "No resource this round" is visible on the page and repeats every
      // round; it is not worth an interruption.
      final events = requestNotificationsFor(
        before: <MediaRequest>[_request(stage: RequestStage.downloading)],
        after: <MediaRequest>[_request(stage: RequestStage.noResource)],
      );

      expect(events, isEmpty);
    });

    test(
      'several requests finishing in one round each get an event, in order',
      () {
        final events = requestNotificationsFor(
          before: <MediaRequest>[
            _request(id: 'a', stage: RequestStage.organizing),
            _request(id: 'b', stage: RequestStage.downloading),
          ],
          after: <MediaRequest>[
            _request(id: 'a', stage: RequestStage.inLibrary, embyItemId: 'e-a'),
            _request(id: 'b', stage: RequestStage.inLibrary, embyItemId: 'e-b'),
          ],
        );

        expect(events.map((e) => e.requestId), <String>['a', 'b']);
      },
    );

    test('a record that disappeared mid-round produces no event', () {
      final events = requestNotificationsFor(
        before: <MediaRequest>[
          _request(id: 'a', stage: RequestStage.organizing),
        ],
        after: const <MediaRequest>[],
      );

      expect(events, isEmpty);
    });
  });
}
