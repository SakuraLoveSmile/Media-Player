import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/models/auth_session.dart';
import 'package:media_player/data/models/server_profile.dart';
import 'package:media_player/data/storage/device_id_store.dart';
import 'package:media_player/data/storage/file_key_value_store.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/data/storage/profile_store.dart';
import 'package:media_player/data/storage/session_store.dart';
import 'package:media_player/data/storage/token_store.dart';

void main() {
  group('TokenStore', () {
    test('writes, reads and deletes', () async {
      final kv = InMemoryKeyValueStore();
      final store = TokenStore(kv);

      expect(await store.read(), isNull);
      await store.write('t1');
      expect(await store.read(), 't1');
      await store.delete();
      expect(await store.read(), isNull);
    });
  });

  group('DeviceIdStore', () {
    test('generates once and keeps the value', () async {
      final kv = InMemoryKeyValueStore();
      final first = await DeviceIdStore(kv).getOrCreate();
      final second = await DeviceIdStore(kv).getOrCreate();

      expect(first, isNotEmpty);
      expect(second, first);
      expect(await kv.read(DeviceIdStore.key), first);
    });

    test('an existing value is preserved', () async {
      final kv = InMemoryKeyValueStore();
      await kv.write(DeviceIdStore.key, 'preexisting');

      expect(await DeviceIdStore(kv).getOrCreate(), 'preexisting');
    });
  });

  group('SessionStore', () {
    test('round-trips metadata without a token', () async {
      final kv = InMemoryKeyValueStore();
      final store = SessionStore(kv);
      const session = AuthSession(
        userId: 'u1',
        userName: 'test',
        accessToken: 'secret',
        deviceId: 'd1',
      );

      await store.write(session);
      final restored = await store.read();

      expect(restored, isNotNull);
      expect(restored!.userId, 'u1');
      expect(restored.userName, 'test');
      expect(restored.deviceId, 'd1');
      expect(restored.accessToken, isEmpty);
      expect(await kv.read(SessionStore.key), isNot(contains('secret')));
    });

    test('corrupt payload reads as null', () async {
      final kv = InMemoryKeyValueStore();
      await kv.write(SessionStore.key, 'not json');
      expect(await SessionStore(kv).read(), isNull);
    });
  });

  group('ProfileStore', () {
    test('round-trips a profile with addresses', () async {
      final store = ProfileStore(InMemoryKeyValueStore());
      const profile = ServerProfile(
        serverId: 's1',
        name: 'Home',
        lanUrl: 'http://192.168.1.10:8096',
        wanUrl: 'https://emby.example.com',
      );

      await store.write(profile);
      final restored = await store.read();

      expect(restored?.serverId, 's1');
      expect(restored?.lanUrl, 'http://192.168.1.10:8096');
    });

    test('rejects unknown schema versions and address-less profiles', () async {
      final kv = InMemoryKeyValueStore();
      final store = ProfileStore(kv);

      await kv.write(
        ProfileStore.key,
        jsonEncode(<String, dynamic>{'schemaVersion': 99, 'profile': <String, dynamic>{}}),
      );
      expect(await store.read(), isNull);

      await kv.write(
        ProfileStore.key,
        jsonEncode(<String, dynamic>{
          'schemaVersion': ProfileStore.schemaVersion,
          'profile': const ServerProfile(serverId: 's1', name: 'Home').toJson(),
        }),
      );
      expect(await store.read(), isNull);
    });

    test('corrupt payload reads as null', () async {
      final kv = InMemoryKeyValueStore();
      await kv.write(ProfileStore.key, '{');
      expect(await ProfileStore(kv).read(), isNull);
    });
  });

  group('FileKeyValueStore', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('mp_store_test');
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    test('persists across instances (restart simulation)', () async {
      final file = File('${dir.path}/nested/store.json');

      await FileKeyValueStore(file).write('token', 'abc');

      final reopened = FileKeyValueStore(file);
      expect(await reopened.read('token'), 'abc');
    });

    test('delete persists across instances', () async {
      final file = File('${dir.path}/store.json');
      await FileKeyValueStore(file).write('token', 'abc');
      await FileKeyValueStore(file).delete('token');

      expect(await FileKeyValueStore(file).read('token'), isNull);
    });

    test('corrupt file reads as empty and can be rewritten', () async {
      final file = File('${dir.path}/store.json');
      await file.writeAsString('not json');

      final store = FileKeyValueStore(file);
      expect(await store.read('token'), isNull);
      await store.write('token', 'abc');
      expect(await FileKeyValueStore(file).read('token'), 'abc');
    });

    test('file is readable only by the owner', () async {
      if (Platform.isWindows) return;

      final file = File('${dir.path}/store.json');
      await FileKeyValueStore(file).write('token', 'abc');

      final stat = await Process.run(
        'stat',
        Platform.isMacOS
            ? <String>['-f', '%Lp', file.path]
            : <String>['-c', '%a', file.path],
      );
      expect(stat.stdout.toString().trim(), '600');
    });
  });
}
