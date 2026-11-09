import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/moviepilot/models/moviepilot_config.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/data/storage/moviepilot_config_store.dart';

void main() {
  group('MoviePilotConfig', () {
    test('fromInput normalizes the address and trims the token', () {
      final config = MoviePilotConfig.fromInput(
        rawBaseUrl: '  nas.local:3002/  ',
        rawApiToken: '  secret-token  ',
      );

      expect(config, isNotNull);
      expect(config!.baseUrl, 'http://nas.local:3002');
      expect(config.apiToken, 'secret-token');
    });

    test('fromInput keeps a reverse-proxy sub-path', () {
      final config = MoviePilotConfig.fromInput(
        rawBaseUrl: 'https://example.com/mp/',
        rawApiToken: 't',
      );

      expect(config!.baseUrl, 'https://example.com/mp');
    });

    test('fromInput rejects an unusable address or an empty token', () {
      expect(
        MoviePilotConfig.fromInput(rawBaseUrl: 'ftp://nas', rawApiToken: 't'),
        isNull,
      );
      expect(
        MoviePilotConfig.fromInput(rawBaseUrl: '', rawApiToken: 't'),
        isNull,
      );
      expect(
        MoviePilotConfig.fromInput(rawBaseUrl: 'nas.local', rawApiToken: '  '),
        isNull,
      );
    });

    test('resolve appends the path to the base, with query', () {
      const config = MoviePilotConfig(
        baseUrl: 'https://example.com/mp',
        apiToken: 't',
      );

      expect(
        config.resolve('/api/v1/subscribe/').toString(),
        'https://example.com/mp/api/v1/subscribe/',
      );
      expect(
        config
            .resolve('/api/v1/mediaserver/exists', <String, String>{
              'mtype': '电影',
            })
            .toString(),
        'https://example.com/mp/api/v1/mediaserver/exists?mtype=%E7%94%B5%E5%BD%B1',
      );
    });

    test('toString never leaks the token', () {
      const config = MoviePilotConfig(
        baseUrl: 'https://example.com',
        apiToken: 'super-secret',
      );

      expect(config.toString(), isNot(contains('super-secret')));
    });
  });

  group('MoviePilotConfigStore', () {
    test('round-trips the connection', () async {
      final kv = InMemoryKeyValueStore();
      final store = MoviePilotConfigStore(kv);
      const config = MoviePilotConfig(
        baseUrl: 'http://nas:3002',
        apiToken: 'token-1',
      );

      expect(await store.read(), isNull);
      await store.write(config);

      final restored = await store.read();
      expect(restored, isNotNull);
      expect(restored!.baseUrl, 'http://nas:3002');
      expect(restored.apiToken, 'token-1');
    });

    test('delete clears the record', () async {
      final kv = InMemoryKeyValueStore();
      final store = MoviePilotConfigStore(kv);
      await store.write(
        const MoviePilotConfig(baseUrl: 'http://nas', apiToken: 't'),
      );

      await store.delete();

      expect(await store.read(), isNull);
      expect(await kv.read(MoviePilotConfigStore.key), isNull);
    });

    test('writes a schema envelope', () async {
      final kv = InMemoryKeyValueStore();
      await MoviePilotConfigStore(
        kv,
      ).write(const MoviePilotConfig(baseUrl: 'http://nas', apiToken: 't'));

      final decoded =
          jsonDecode((await kv.read(MoviePilotConfigStore.key))!)
              as Map<String, dynamic>;
      expect(decoded['schemaVersion'], MoviePilotConfigStore.schemaVersion);
      expect(decoded['config'], isA<Map<String, dynamic>>());
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
          'config': <String, dynamic>{'baseUrl': 'http://nas', 'apiToken': 't'},
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
