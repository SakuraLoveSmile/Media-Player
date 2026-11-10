import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/moviepilot/models/media_request.dart';
import 'package:media_player/data/moviepilot/models/mp_downloader_torrent.dart';
import 'package:media_player/data/moviepilot/models/mp_media_info.dart';
import 'package:media_player/data/moviepilot/models/mp_subscribe.dart';
import 'package:media_player/data/moviepilot/progress/poll_snapshot.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/data/storage/request_store.dart';

MediaRequest request({
  String id = 'req-1',
  int? subscribeId = 7,
  int season = 0,
  MpMediaType type = MpMediaType.movie,
  RequestStage stage = RequestStage.submitted,
  DateTime? createdAt,
}) {
  return MediaRequest(
    id: id,
    ref: const MpMediaRef(
      source: MpMediaSource.tmdb,
      mediaId: '693134',
      tmdbId: 693134,
    ),
    type: type,
    title: '沙丘2',
    year: '2024',
    season: season,
    subscribeId: subscribeId,
    createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
    stage: stage,
  );
}

void main() {
  group('MediaRequest', () {
    test('round-trips through JSON', () {
      final original = request(stage: RequestStage.downloading).copyWith(
        progressPercent: 0.42,
        downloadSpeed: '5 MB/s',
        eta: '10m',
        completedEpisodes: 3,
        totalEpisodes: 10,
        activeTaskCount: 2,
        embyItemId: 'emby-1',
        lastUpdatedAt: DateTime.utc(2026, 1, 2),
        message: '下载中',
        archived: true,
      );

      final restored = MediaRequest.fromJson(original.toJson())!;

      expect(restored.id, original.id);
      expect(restored.title, '沙丘2');
      expect(restored.stage, RequestStage.downloading);
      expect(restored.progressPercent, 0.42);
      expect(restored.downloadSpeed, '5 MB/s');
      expect(restored.completedEpisodes, 3);
      expect(restored.totalEpisodes, 10);
      expect(restored.activeTaskCount, 2);
      expect(restored.embyItemId, 'emby-1');
      expect(restored.message, '下载中');
      expect(restored.archived, isTrue);
      expect(restored.lastUpdatedAt, DateTime.utc(2026, 1, 2));
      expect(restored.ref.identityKey, 'themoviedb:693134');
    });

    test('an unknown stage falls back to submitted', () {
      final json = request().toJson()..['stage'] = 'a stage from the future';

      expect(MediaRequest.fromJson(json)!.stage, RequestStage.submitted);
    });

    test('a record without id, type or title is dropped', () {
      expect(MediaRequest.fromJson(<String, dynamic>{
        'type': '电影',
        'title': 'x',
      }), isNull);
      expect(MediaRequest.fromJson(<String, dynamic>{
        'id': 'r',
        'title': 'x',
      }), isNull);
      expect(MediaRequest.fromJson(<String, dynamic>{
        'id': 'r',
        'type': '电影',
      }), isNull);
    });

    test('identityKey separates season and type but not the id', () {
      final movie = request();
      final seriesS1 = request(season: 1, type: MpMediaType.series);
      final seriesS2 = request(season: 2, type: MpMediaType.series);

      expect(movie.identityKey, isNot(seriesS1.identityKey));
      expect(seriesS1.identityKey, isNot(seriesS2.identityKey));
      expect(seriesS1.identityKey, contains('s1'));
    });

    test('an unidentified request falls back to title plus year', () {
      final unidentified = MediaRequest(
        id: 'r',
        ref: const MpMediaRef(source: MpMediaSource.unknown, mediaId: ''),
        type: MpMediaType.movie,
        title: 'Some Movie',
        year: '1999',
        createdAt: DateTime.utc(2026),
      );

      expect(unidentified.identityKey, 'title:some movie|1999|s0');
    });

    test('copyWith can clear the nullable fields', () {
      final cleared = request().copyWith(
        subscribeId: null,
        embyItemId: null,
        progressPercent: null,
      );

      expect(cleared.subscribeId, isNull);
      expect(cleared.embyItemId, isNull);
      expect(cleared.progressPercent, isNull);
    });

    test('copyWith keeps fields it was not given', () {
      final updated = request().copyWith(stage: RequestStage.searching);

      expect(updated.stage, RequestStage.searching);
      expect(updated.title, '沙丘2');
      expect(updated.subscribeId, 7);
    });
  });

  group('RequestStage', () {
    test('parses names and defaults to submitted', () {
      expect(RequestStage.parse('downloading'), RequestStage.downloading);
      expect(RequestStage.parse('nonsense'), RequestStage.submitted);
      expect(RequestStage.parse(null), RequestStage.submitted);
    });

    test('the chain is ordered and skips the side branches', () {
      expect(RequestStage.chain.first, RequestStage.submitted);
      expect(RequestStage.chain.last, RequestStage.inLibrary);
      expect(RequestStage.chain, isNot(contains(RequestStage.noResource)));
      expect(RequestStage.chain, isNot(contains(RequestStage.paused)));
    });

    test('side branches report their nearest chain position', () {
      expect(
        RequestStage.noResource.chainIndex,
        RequestStage.chain.indexOf(RequestStage.searching),
      );
      expect(
        RequestStage.paused.chainIndex,
        RequestStage.chain.indexOf(RequestStage.searching),
      );
      expect(RequestStage.organizing.chainIndex, 3);
    });

    test('stage affordances', () {
      expect(RequestStage.downloading.hasDeterminateProgress, isTrue);
      expect(RequestStage.searching.isBusy, isTrue);
      expect(RequestStage.organizing.isBusy, isTrue);
      expect(RequestStage.inLibrary.isTerminal, isTrue);
      expect(RequestStage.cancelled.isTerminal, isTrue);
      expect(RequestStage.downloading.isTerminal, isFalse);
    });
  });

  group('RequestStore', () {
    test('round-trips the request list in newest-first order', () async {
      final kv = InMemoryKeyValueStore();
      final store = RequestStore(kv);
      final older = request(
        id: 'a',
        createdAt: DateTime.utc(2026, 1, 1),
      );
      final newer = request(
        id: 'b',
        createdAt: DateTime.utc(2026, 2, 1),
      );

      await store.write(<MediaRequest>[older, newer]);
      final restored = await store.read();

      expect(restored.map((r) => r.id), <String>['b', 'a']);
    });

    test('persists the snapshot alongside the requests', () async {
      final kv = InMemoryKeyValueStore();
      final store = RequestStore(kv);
      final snapshot = PollSnapshot(
        subscribes: <MpSubscribe>[
          MpSubscribe.fromJson(<String, dynamic>{
            'id': 7,
            'type': '电影',
            'media_source': 'themoviedb',
            'media_id': '693134',
          })!,
        ],
        downloads: <MpDownloaderTorrent>[
          MpDownloaderTorrent.fromJson(<String, dynamic>{
            'hash': 'h',
            'progress': 50,
          })!,
        ],
        tasksLoaded: true,
        fetchedAt: DateTime.utc(2026, 1, 3),
      );

      await store.write(<MediaRequest>[request()], snapshot: snapshot);

      final restored = await store.readSnapshot();
      expect(restored, isNotNull);
      expect(restored!.subscribes.single.id, 7);
      expect(restored.downloads.single.progress, 0.5);
      expect(restored.tasksLoaded, isTrue);
      expect(restored.fetchedAt, DateTime.utc(2026, 1, 3));
    });

    test('writeRequests keeps the stored snapshot', () async {
      final kv = InMemoryKeyValueStore();
      final store = RequestStore(kv);
      await store.write(
        <MediaRequest>[request()],
        snapshot: PollSnapshot(fetchedAt: DateTime.utc(2026)),
      );

      await store.writeRequests(<MediaRequest>[request(id: 'other')]);

      final restored = await store.read();
      expect(restored.single.id, 'other');
      expect(await store.readSnapshot(), isNotNull);
    });

    test('a corrupt payload reads as empty', () async {
      final kv = InMemoryKeyValueStore();
      final store = RequestStore(kv);

      await kv.write(RequestStore.key, 'not json');
      expect(await store.read(), isEmpty);
      expect(await store.readSnapshot(), isNull);

      await kv.write(
        RequestStore.key,
        '{"schemaVersion":999,"requests":[]}',
      );
      expect(await store.read(), isEmpty);
    });

    test('one unreadable record does not take the others down', () async {
      final kv = InMemoryKeyValueStore();
      final store = RequestStore(kv);
      await store.write(<MediaRequest>[request(id: 'good')]);
      final raw = await kv.read(RequestStore.key);

      // Splice in a record the parser must reject.
      final decoded = raw!.replaceFirst(
        '"requests":[{',
        '"requests":[{"type":"音乐","title":"x"}, {',
      );
      await kv.write(RequestStore.key, decoded);

      final restored = await store.read();
      expect(restored.map((r) => r.id), <String>['good']);
    });

    test('delete clears everything', () async {
      final kv = InMemoryKeyValueStore();
      final store = RequestStore(kv);
      await store.write(<MediaRequest>[request()]);

      await store.delete();

      expect(await store.read(), isEmpty);
      expect(await kv.read(RequestStore.key), isNull);
    });
  });
}
