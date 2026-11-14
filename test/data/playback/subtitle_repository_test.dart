import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/emby_exception.dart';
import 'package:media_player/core/network/endpoint_kind.dart';
import 'package:media_player/data/auth/api_session.dart';
import 'package:media_player/data/models/media_stream.dart';
import 'package:media_player/data/models/resolved_endpoint.dart';
import 'package:media_player/data/models/server_profile.dart';
import 'package:media_player/data/playback/subtitle_repository.dart';

class FakeSession implements ApiSession {
  FakeSession({ResolvedEndpoint? endpoint, this.accessToken = 'token-1'})
    : endpoint = endpoint ?? _endpoint;

  static final ResolvedEndpoint _endpoint = ResolvedEndpoint(
    baseUrl: 'http://lan.example:8096',
    kind: EndpointKind.lan,
    serverId: 'server-1',
    resolvedAt: DateTime(2026),
  );

  @override
  ResolvedEndpoint? endpoint;

  @override
  String? accessToken;

  @override
  String? get userId => 'user-1';

  @override
  String? get deviceId => 'device-1';

  @override
  ServerProfile? get profile => null;

  @override
  Future<Map<String, dynamic>> authorizedGet(Uri url) async =>
      <String, dynamic>{};

  @override
  Future<Map<String, dynamic>> authorizedPost(Uri url, {Object? body}) async =>
      <String, dynamic>{};

  @override
  Future<Map<String, dynamic>> authorizedDelete(Uri url) async =>
      <String, dynamic>{};
}

MediaStream externalStream({
  int index = 3,
  String? codec = 'subrip',
  String? deliveryUrl,
}) {
  return MediaStream(
    type: MediaStreamType.subtitle,
    index: index,
    codec: codec,
    isExternal: true,
    deliveryUrl: deliveryUrl,
  );
}

void main() {
  late Directory directory;
  late FakeSession session;
  late List<({Uri url, String? token})> fetches;
  late Object? fetchError;
  late Uint8List bytes;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('subtitles_test');
    session = FakeSession();
    fetches = <({Uri url, String? token})>[];
    fetchError = null;
    bytes = Uint8List.fromList(
      '1\n00:00:01,000 --> 00:00:02,000\n你好\n'.codeUnits,
    );
  });

  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  SubtitleRepository build() {
    return SubtitleRepository(
      session,
      directory: directory,
      fetch: (Uri url, {String? token, Duration? timeout}) async {
        fetches.add((url: url, token: token));
        final error = fetchError;
        if (error != null) throw error;
        return bytes;
      },
    );
  }

  test('downloads through the documented stream path with api_key', () async {
    final repo = build();

    final path = await repo.externalFile(
      itemId: 'item-1',
      mediaSourceId: 'source-1',
      stream: externalStream(),
    );

    expect(fetches, hasLength(1));
    expect(
      fetches.single.url.toString(),
      'http://lan.example:8096/Videos/item-1/source-1/Subtitles/3/Stream.srt'
      '?api_key=token-1',
    );
    expect(fetches.single.token, 'token-1');
    expect(path, '${directory.path}/item-1_source-1_3.srt');
    expect(File(path).readAsBytesSync(), bytes);
  });

  test('a second request is served from the cache without fetching', () async {
    final repo = build();

    final first = await repo.externalFile(
      itemId: 'item-1',
      mediaSourceId: 'source-1',
      stream: externalStream(),
    );
    final second = await repo.externalFile(
      itemId: 'item-1',
      mediaSourceId: 'source-1',
      stream: externalStream(),
    );

    expect(second, first);
    expect(fetches, hasLength(1));
  });

  test('different streams and sources get different cache files', () async {
    final repo = build();

    final a = await repo.externalFile(
      itemId: 'item-1',
      mediaSourceId: 'source-1',
      stream: externalStream(index: 3),
    );
    final b = await repo.externalFile(
      itemId: 'item-1',
      mediaSourceId: 'source-1',
      stream: externalStream(index: 4),
    );
    final c = await repo.externalFile(
      itemId: 'item-1',
      mediaSourceId: 'source-2',
      stream: externalStream(index: 3),
    );

    expect(<String>{a, b, c}, hasLength(3));
    expect(fetches, hasLength(3));
  });

  test(
    'a relative DeliveryUrl is resolved against the session endpoint',
    () async {
      final repo = build();

      await repo.externalFile(
        itemId: 'item-1',
        mediaSourceId: 'source-1',
        stream: externalStream(
          deliveryUrl: '/Videos/item-1/source-1/Subtitles/3/Stream.srt',
        ),
      );

      expect(
        fetches.single.url.toString(),
        'http://lan.example:8096/Videos/item-1/source-1/Subtitles/3/Stream.srt'
        '?api_key=token-1',
      );
    },
  );

  test('an absolute DeliveryUrl keeps its host and gains api_key', () async {
    final repo = build();

    await repo.externalFile(
      itemId: 'item-1',
      mediaSourceId: 'source-1',
      stream: externalStream(
        deliveryUrl: 'http://cdn.example/sub/3.srt?foo=bar',
      ),
    );

    expect(
      fetches.single.url.toString(),
      'http://cdn.example/sub/3.srt?foo=bar&api_key=token-1',
    );
  });

  test('an existing api_key in the DeliveryUrl is not replaced', () async {
    final repo = build();

    await repo.externalFile(
      itemId: 'item-1',
      mediaSourceId: 'source-1',
      stream: externalStream(
        deliveryUrl:
            '/Videos/item-1/source-1/Subtitles/3/Stream.srt'
            '?api_key=server-key',
      ),
    );

    expect(fetches.single.url.queryParameters['api_key'], 'server-key');
  });

  for (final (String codec, String extension) in <(String, String)>[
    ('ass', 'ass'),
    ('ssa', 'ass'),
    ('subrip', 'srt'),
    ('srt', 'srt'),
    ('pgssub', 'sup'),
    ('webvtt', 'webvtt'),
  ]) {
    test('codec $codec caches as .$extension', () async {
      final repo = build();

      final path = await repo.externalFile(
        itemId: 'item-1',
        mediaSourceId: 'source-1',
        stream: externalStream(codec: codec),
      );

      expect(path, endsWith('.$extension'));
    });
  }

  test('a missing codec falls back to srt', () async {
    final repo = build();

    final path = await repo.externalFile(
      itemId: 'item-1',
      mediaSourceId: 'source-1',
      stream: externalStream(codec: null),
    );

    expect(path, endsWith('.srt'));
  });

  test('the cache directory is created on first download', () async {
    final nested = Directory('${directory.path}/a/b');
    final repo = SubtitleRepository(
      session,
      directory: nested,
      fetch: (Uri url, {String? token, Duration? timeout}) async => bytes,
    );

    final path = await repo.externalFile(
      itemId: 'item-1',
      mediaSourceId: 'source-1',
      stream: externalStream(),
    );

    expect(File(path).existsSync(), isTrue);
  });

  test('empty bytes are a subtitle failure and write no file', () async {
    bytes = Uint8List(0);
    final repo = build();

    await expectLater(
      repo.externalFile(
        itemId: 'item-1',
        mediaSourceId: 'source-1',
        stream: externalStream(),
      ),
      throwsA(
        isA<EmbyException>().having(
          (e) => e.code,
          'code',
          AppErrorCode.subtitleFailed,
        ),
      ),
    );
    expect(directory.listSync(), isEmpty);
  });

  test('a transport error becomes subtitleFailed', () async {
    fetchError = const SocketException('connection reset');
    final repo = build();

    await expectLater(
      repo.externalFile(
        itemId: 'item-1',
        mediaSourceId: 'source-1',
        stream: externalStream(),
      ),
      throwsA(
        isA<EmbyException>().having(
          (e) => e.code,
          'code',
          AppErrorCode.subtitleFailed,
        ),
      ),
    );
  });

  test('an EmbyException from the fetch passes through unchanged', () async {
    fetchError = EmbyException(AppErrorCode.unauthorized);
    final repo = build();

    await expectLater(
      repo.externalFile(
        itemId: 'item-1',
        mediaSourceId: 'source-1',
        stream: externalStream(),
      ),
      throwsA(
        isA<EmbyException>().having(
          (e) => e.code,
          'code',
          AppErrorCode.unauthorized,
        ),
      ),
    );
  });

  test('a logged-out session refuses to download', () async {
    session.accessToken = null;
    final repo = build();

    await expectLater(
      repo.externalFile(
        itemId: 'item-1',
        mediaSourceId: 'source-1',
        stream: externalStream(),
      ),
      throwsA(
        isA<EmbyException>().having(
          (e) => e.code,
          'code',
          AppErrorCode.unauthorized,
        ),
      ),
    );
    expect(fetches, isEmpty);
  });
}
