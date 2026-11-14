import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/moviepilot/models/moviepilot_config.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/data/storage/moviepilot_config_store.dart';

import '../../support/fake_moviepilot_server.dart';

void main() {
  group('MoviePilotConfig', () {
    test('round-trips the account, token and expiry', () {
      final config = MoviePilotConfig(
        baseUrl: 'http://nas:3002',
        username: 'admin',
        accessToken: 'jwt',
        expiresAt: DateTime.utc(2026, 11, 18, 10),
      );

      final restored = MoviePilotConfig.fromJson(config.toJson());

      expect(restored, isNotNull);
      expect(restored!.baseUrl, 'http://nas:3002');
      expect(restored.username, 'admin');
      expect(restored.accessToken, 'jwt');
      expect(restored.expiresAt, DateTime.utc(2026, 11, 18, 10));
    });

    test('a record without an expiry is still usable', () {
      final restored = MoviePilotConfig.fromJson(<String, dynamic>{
        'baseUrl': 'http://nas',
        'username': 'admin',
        'accessToken': 'jwt',
      });

      expect(restored!.expiresAt, isNull);
      expect(restored.isExpired, isFalse);
    });

    test('a half-written record reads as null', () {
      expect(
        MoviePilotConfig.fromJson(<String, dynamic>{
          'baseUrl': 'http://nas',
          'accessToken': 'jwt',
        }),
        isNull,
      );
      expect(
        MoviePilotConfig.fromJson(<String, dynamic>{
          'baseUrl': 'http://nas',
          'username': 'admin',
        }),
        isNull,
      );
      expect(
        MoviePilotConfig.fromJson(<String, dynamic>{
          'username': 'admin',
          'accessToken': 'jwt',
        }),
        isNull,
      );
    });

    test('isExpired compares the stored expiry with now', () {
      MoviePilotConfig at(Duration offset) => MoviePilotConfig(
        baseUrl: 'http://nas',
        username: 'admin',
        accessToken: 'jwt',
        expiresAt: DateTime.now().add(offset),
      );

      expect(at(const Duration(minutes: 5)).isExpired, isFalse);
      expect(at(const Duration(minutes: -5)).isExpired, isTrue);
    });

    test('the expiry is read from the JWT exp claim', () {
      final expiry = DateTime.now().add(const Duration(days: 8));
      final token = fakeAccessToken(expiresAt: expiry);

      final parsed = MoviePilotConfig.expiryFromAccessToken(token);

      expect(
        parsed!.millisecondsSinceEpoch,
        (expiry.millisecondsSinceEpoch ~/ 1000) * 1000,
      );
      expect(parsed.isUtc, isTrue);
    });

    test('an unreadable token simply has no known expiry', () {
      expect(MoviePilotConfig.expiryFromAccessToken('not-a-jwt'), isNull);
      expect(
        MoviePilotConfig.expiryFromAccessToken('a.b.c'),
        isNull,
        reason: 'b is not base64 JSON',
      );
      expect(
        MoviePilotConfig.expiryFromAccessToken(
          fakeAccessToken(claims: <String, dynamic>{'exp': null}),
        ),
        isNull,
      );
    });

    test('resolve appends the path to the base, with query', () {
      const config = MoviePilotConfig(
        baseUrl: 'https://example.com/mp',
        username: 'admin',
        accessToken: 't',
      );

      expect(
        config.resolve('/api/v1/subscribe/').toString(),
        'https://example.com/mp/api/v1/subscribe/',
      );
      expect(
        config.resolve('/api/v1/mediaserver/exists', <String, String>{
          'mtype': '电影',
        }).toString(),
        'https://example.com/mp/api/v1/mediaserver/exists?mtype=%E7%94%B5%E5%BD%B1',
      );
    });

    test('toString names the account but never the token', () {
      const config = MoviePilotConfig(
        baseUrl: 'https://example.com',
        username: 'admin',
        accessToken: 'super-secret',
      );

      expect(config.toString(), contains('admin'));
      expect(config.toString(), isNot(contains('super-secret')));
    });
  });

  group('MoviePilotConfigStore', () {
    MoviePilotConfig config() => MoviePilotConfig(
      baseUrl: 'http://nas:3002',
      username: 'admin',
      accessToken: 'token-1',
      expiresAt: DateTime.utc(2026, 11, 18),
    );

    test('round-trips the connection', () async {
      final kv = InMemoryKeyValueStore();
      final store = MoviePilotConfigStore(kv);

      expect(await store.read(), isNull);
      await store.write(config());

      final restored = await store.read();
      expect(restored, isNotNull);
      expect(restored!.baseUrl, 'http://nas:3002');
      expect(restored.username, 'admin');
      expect(restored.accessToken, 'token-1');
      expect(restored.expiresAt, DateTime.utc(2026, 11, 18));
    });

    test('delete clears the record', () async {
      final kv = InMemoryKeyValueStore();
      final store = MoviePilotConfigStore(kv);
      await store.write(config());

      await store.delete();

      expect(await store.read(), isNull);
      expect(await kv.read(MoviePilotConfigStore.key), isNull);
    });

    test('writes a schema envelope', () async {
      final kv = InMemoryKeyValueStore();
      await MoviePilotConfigStore(kv).write(config());

      final decoded = jsonDecode(
        (await kv.read(MoviePilotConfigStore.key))!,
      ) as Map<String, dynamic>;
      expect(decoded['schemaVersion'], MoviePilotConfigStore.schemaVersion);
      expect(decoded['config'], isA<Map<String, dynamic>>());
    });

    test('drops the old API-key record instead of reading it', () async {
      final kv = InMemoryKeyValueStore();
      final store = MoviePilotConfigStore(kv);
      // v1 held the instance-wide administrator key; it must not survive.
      await kv.write(
        MoviePilotConfigStore.key,
        jsonEncode(<String, dynamic>{
          'schemaVersion': 1,
          'config': <String, dynamic>{
            'baseUrl': 'http://nas',
            'apiToken': 'old-admin-key',
          },
        }),
      );

      expect(await store.read(), isNull);
      expect(await kv.read(MoviePilotConfigStore.key), isNull);
    });

    test('a corrupt or foreign-schema record reads as null', () async {
      final kv = InMemoryKeyValueStore();
      final store = MoviePilotConfigStore(kv);

      await kv.write(MoviePilotConfigStore.key, 'not json');
      expect(await store.read(), isNull);

      await kv.write(
        MoviePilotConfigStore.key,
        jsonEncode(<String, dynamic>{
          'schemaVersion': 999,
          'config': <String, dynamic>{
            'baseUrl': 'http://nas',
            'username': 'admin',
            'accessToken': 'jwt',
          },
        }),
      );
      expect(await store.read(), isNull);

      // A half-written config must not produce a half-configured client.
      await kv.write(
        MoviePilotConfigStore.key,
        jsonEncode(<String, dynamic>{
          'schemaVersion': MoviePilotConfigStore.schemaVersion,
          'config': <String, dynamic>{'baseUrl': 'http://nas'},
        }),
      );
      expect(await store.read(), isNull);
    });
  });
}
