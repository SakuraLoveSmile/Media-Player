import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/dandanplay_exception.dart';
import 'package:media_player/data/danmaku/api/dandanplay_client.dart';
import 'package:media_player/data/danmaku/models/danmaku_anime.dart';
import 'package:media_player/data/danmaku/models/danmaku_comment.dart';

import '../../support/fake_dandanplay_server.dart';

void main() {
  late FakeDandanPlayServer server;
  late List<String> logs;
  late DandanPlayClient client;

  setUp(() async {
    server = FakeDandanPlayServer();
    await server.start();
    logs = <String>[];
    client = DandanPlayClient(Dio(), baseUrl: server.base, logSink: logs.add);
  });

  tearDown(() async {
    await server.stop();
  });

  group('search/episodes parsing', () {
    test('parses animes and episodes and sends the query', () async {
      server.animes = <Map<String, dynamic>>[
        fakeAnime(100, '测试动画', <(int, String)>[(1001, '第1话'), (1002, '第2话')]),
      ];

      final List<DanmakuAnime> animes = await client.searchEpisodes(
        '测试动画',
        episode: '2',
      );

      expect(server.lastQuery['/api/v2/search/episodes'], <String, String>{
        'anime': '测试动画',
        'episode': '2',
      });
      expect(animes, hasLength(1));
      expect(animes.single.id, 100);
      expect(animes.single.title, '测试动画');
      expect(animes.single.episodes, hasLength(2));
      expect(animes.single.episodes[1].id, 1002);
      expect(animes.single.episodes[1].title, '第2话');
    });

    test('omits the episode filter when none is given', () async {
      await client.searchEpisodes('测试动画');

      expect(server.lastQuery['/api/v2/search/episodes'], <String, String>{
        'anime': '测试动画',
      });
    });

    test('an empty or malformed reply degrades to no animes', () async {
      server.animes = <Map<String, dynamic>>[];
      expect(await client.searchEpisodes('nothing'), isEmpty);
    });
  });

  group('match', () {
    test(
      'a movie (no episode) takes the first episode of the best anime',
      () async {
        server.animes = <Map<String, dynamic>>[
          fakeAnime(100, '测试动画', <(int, String)>[(1001, '第1话'), (1002, '第2话')]),
        ];

        expect(await client.match('测试动画'), 1001);
      },
    );

    test('an exact title wins over the first relevance hit', () async {
      server.animes = <Map<String, dynamic>>[
        fakeAnime(200, '测试动画 第二季', <(int, String)>[(2001, '第1话')]),
        fakeAnime(100, '测试动画', <(int, String)>[(1001, '第1话')]),
      ];

      final DanmakuMatch? match = await client.matchEpisode('测试动画');
      expect(match?.episodeId, 1001);
      expect(match?.animeTitle, '测试动画');
      expect(match?.episodeTitle, '第1话');
    });

    test(
      'an episode number picks the matching title, not the position',
      () async {
        server.animes = <Map<String, dynamic>>[
          fakeAnime(100, '测试动画', <(int, String)>[
            (1002, '第2话'),
            (1001, '第1话'),
            (1003, '第3话'),
          ]),
        ];

        expect(await client.match('测试动画', episode: '3'), 1003);
      },
    );

    test('numberless titles fall back to the 1-based position', () async {
      server.animes = <Map<String, dynamic>>[
        fakeAnime(100, '测试动画', <(int, String)>[(1001, 'OVA'), (1002, 'SP')]),
      ];

      expect(await client.match('测试动画', episode: '2'), 1002);
    });

    test('no animes or no episodes means no match', () async {
      server.animes = <Map<String, dynamic>>[];
      expect(await client.match('nothing'), isNull);

      server.animes = <Map<String, dynamic>>[
        fakeAnime(100, '测试动画', <(int, String)>[]),
      ];
      expect(await client.match('测试动画'), isNull);
    });
  });

  group('comment p-field parsing', () {
    test('parses time, mode and color and sorts by time', () async {
      server.commentsByEpisode[1001] = <Map<String, dynamic>>[
        fakeComment(3, '12.5,1,16777215,25', '滚动弹幕'),
        fakeComment(1, '0,5,16711680,25', '顶部弹幕'),
        fakeComment(2, '3.25,4,255,25', '底部弹幕'),
      ];

      final List<DanmakuComment> comments = await client.fetchComments(1001);

      expect(server.lastQuery['/api/v2/comment/1001'], <String, String>{
        'withRelated': 'true',
      });
      expect(comments, hasLength(3));
      // Sorted by time: 0 → 3.25 → 12.5.
      expect(comments[0].id, 1);
      expect(comments[0].time, Duration.zero);
      expect(comments[0].mode, 5);
      expect(comments[0].color, 16711680);
      expect(comments[0].text, '顶部弹幕');
      expect(comments[0].isPinned, isTrue);
      expect(comments[1].time, const Duration(milliseconds: 3250));
      expect(comments[1].mode, 4);
      expect(comments[1].isPinned, isTrue);
      expect(comments[2].time, const Duration(milliseconds: 12500));
      expect(comments[2].mode, 1);
      expect(comments[2].color, 16777215);
      expect(comments[2].isPinned, isFalse);
    });

    test('malformed entries are skipped, never fatal', () async {
      server.commentsByEpisode[1001] = <Map<String, dynamic>>[
        fakeComment(1, '1,1,16777215,25', 'ok'),
        fakeComment(2, '', 'missing p'),
        fakeComment(3, '1,1', 'short p'),
        fakeComment(4, 'abc,1,16777215,25', 'bad time'),
        fakeComment(5, '1,x,16777215,25', 'bad mode'),
        fakeComment(6, '-2,1,16777215,25', 'negative time'),
        fakeComment(7, '1,1,16777215,25', ''),
        <String, dynamic>{'cid': 8, 'm': 'no p at all'},
      ];

      final List<DanmakuComment> comments = await client.fetchComments(1001);

      expect(comments, hasLength(1));
      expect(comments.single.id, 1);
      expect(comments.single.text, 'ok');
    });

    test('an empty comment list is a valid reply', () async {
      expect(await client.fetchComments(9999), isEmpty);
    });
  });

  group('failure guarding', () {
    test('a 500 becomes a DandanPlayException', () async {
      server.failingPaths.add('/api/v2/search/episodes');

      await expectLater(
        client.searchEpisodes('测试动画'),
        throwsA(
          isA<DandanPlayException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.serverError,
          ),
        ),
      );
    });

    test('a closed port becomes networkUnreachable', () async {
      final DandanPlayClient closed = DandanPlayClient(
        Dio(),
        baseUrl: 'http://127.0.0.1:1',
      );

      await expectLater(
        closed.fetchComments(1),
        throwsA(
          isA<DandanPlayException>().having(
            (e) => e.code,
            'code',
            AppErrorCode.networkUnreachable,
          ),
        ),
      );
    });

    test('a non-JSON body becomes serverError', () async {
      server.nonJson = true;

      await expectLater(
        client.searchEpisodes('测试动画'),
        throwsA(isA<DandanPlayException>()),
      );
    });

    test('logs the path but never the searched title', () async {
      await client.searchEpisodes('secret-title', episode: '2');

      expect(logs, hasLength(1));
      expect(logs.single, startsWith('GET '));
      expect(logs.single, contains('/api/v2/search/episodes'));
      expect(logs.single, isNot(contains('secret-title')));
    });
  });
}
