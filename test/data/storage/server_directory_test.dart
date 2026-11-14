import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/models/auth_session.dart';
import 'package:media_player/data/models/server_entry.dart';
import 'package:media_player/data/models/server_profile.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/data/storage/profile_store.dart';
import 'package:media_player/data/storage/server_directory.dart';
import 'package:media_player/data/storage/session_store.dart';
import 'package:media_player/data/storage/token_store.dart';

void main() {
  late InMemoryKeyValueStore kv;
  late ServerDirectory directory;

  setUp(() {
    kv = InMemoryKeyValueStore();
    directory = ServerDirectory(kv);
  });

  const home = ServerEntry(
    id: 'a',
    name: 'Home',
    lanUrl: 'http://192.168.1.10:8096',
    wanUrl: 'https://home.example.com',
  );
  const office = ServerEntry(
    id: 'b',
    name: 'Office',
    lanUrl: 'http://10.0.0.5:8096',
  );

  group('add / read / persist', () {
    test('starts empty', () async {
      expect(await directory.read(), isEmpty);
      expect(await directory.activeId(), defaultServerId);
    });

    test('add persists entries in order and survives a reopen', () async {
      await directory.add(home);
      await directory.add(office);

      final reopened = ServerDirectory(kv);
      final entries = await reopened.read();
      expect(entries.map((e) => e.id), <String>['a', 'b']);
      expect(entries.first.name, 'Home');
      expect(entries.first.lanUrl, 'http://192.168.1.10:8096');
      expect(entries.first.wanUrl, 'https://home.example.com');
      expect(entries.last.wanUrl, isNull);
    });

    test('upsert replaces an existing id without duplicating', () async {
      await directory.add(home);
      await directory.upsert(home.copyWith(name: 'Home 2'));

      final entries = await directory.read();
      expect(entries.length, 1);
      expect(entries.single.name, 'Home 2');
    });

    test('the stored payload is non-secret name/address only', () async {
      await directory.add(home);
      final raw = (await kv.read(ServerDirectory.key))!;
      expect(raw, contains('192.168.1.10'));
      expect(raw, isNot(contains('token')));
      expect(raw, isNot(contains('accessToken')));
    });
  });

  group('remove', () {
    test('removes an entry and keeps the active one', () async {
      await directory.add(home);
      await directory.add(office);
      await directory.setActive('b');

      await directory.remove('a');

      expect((await directory.read()).map((e) => e.id), <String>['b']);
      expect(await directory.activeId(), 'b');
    });

    test(
      'removing the active entry falls back to the first remaining',
      () async {
        await directory.add(home);
        await directory.add(office);
        await directory.setActive('a');

        await directory.remove('a');

        expect(await directory.activeId(), 'b');
      },
    );

    test('removing the last entry resets active to default', () async {
      await directory.add(home);
      await directory.setActive('a');

      await directory.remove('a');

      expect(await directory.read(), isEmpty);
      expect(await directory.activeId(), defaultServerId);
    });
  });

  group('rename', () {
    test('updates only the name', () async {
      await directory.add(home);
      await directory.rename('a', '客厅');

      final entry = (await directory.read()).single;
      expect(entry.name, '客厅');
      expect(entry.lanUrl, home.lanUrl);
      expect(entry.id, 'a');
    });

    test('renaming an unknown id is a no-op', () async {
      await directory.add(home);
      await directory.rename('missing', 'X');
      expect((await directory.read()).single.name, 'Home');
    });
  });

  group('activeId', () {
    test('setActive persists and a dangling id falls back', () async {
      await directory.add(home);
      await directory.setActive('a');
      expect(await ServerDirectory(kv).activeId(), 'a');

      // Point at a removed entry: the directory recovers to the first entry.
      await directory.setActive('ghost');
      expect(await directory.activeId(), 'a');
    });

    test('find returns the matching entry or null', () async {
      await directory.add(home);
      expect((await directory.find('a'))?.name, 'Home');
      expect(await directory.find('nope'), isNull);
    });
  });

  group('corrupt / versioned payload', () {
    test('corrupt json reads as empty', () async {
      await kv.write(ServerDirectory.key, 'not json');
      expect(await directory.read(), isEmpty);
      expect(await directory.activeId(), defaultServerId);
    });

    test('an unknown schema version reads as empty', () async {
      await kv.write(
        ServerDirectory.key,
        jsonEncode(<String, dynamic>{
          'schemaVersion': 99,
          'activeId': 'a',
          'servers': <Map<String, dynamic>>[home.toJson()],
        }),
      );
      expect(await directory.read(), isEmpty);
    });
  });

  group('legacy migration', () {
    test('creates a default entry from the legacy profile', () async {
      const profile = ServerProfile(
        serverId: 'server-1',
        name: 'Home',
        lanUrl: 'http://192.168.1.10:8096',
        wanUrl: 'https://home.example.com',
      );

      final migrated = await directory.migrateLegacyProfile(profile);

      expect(migrated, isTrue);
      final entries = await directory.read();
      expect(entries.single.id, defaultServerId);
      expect(entries.single.name, 'Home');
      expect(entries.single.lanUrl, profile.lanUrl);
      expect(await directory.activeId(), defaultServerId);
    });

    test(
      'the legacy single session becomes the default server session',
      () async {
        // A legacy install: token + metadata under the original keys.
        await TokenStore(kv).write('legacy-token');
        await SessionStore(kv).write(
          const AuthSession(
            userId: 'u1',
            userName: 'test',
            accessToken: 'legacy-token',
            deviceId: 'd1',
          ),
        );
        await ProfileStore(kv).write(
          const ServerProfile(
            serverId: 'server-1',
            name: 'Home',
            lanUrl: 'http://192.168.1.10:8096',
          ),
        );

        await directory.migrateLegacyProfile(await ProfileStore(kv).read());

        // The default id reuses the original keys, so no credential is moved.
        expect(
          await TokenStore(kv, serverId: defaultServerId).read(),
          'legacy-token',
        );
        expect(await kv.read(TokenStore.key), 'legacy-token');
        final meta = await SessionStore(kv, serverId: defaultServerId).read();
        expect(meta?.userId, 'u1');
        expect((await directory.read()).single.id, defaultServerId);
      },
    );

    test('does not migrate when entries already exist', () async {
      await directory.add(home);
      final migrated = await directory.migrateLegacyProfile(
        const ServerProfile(serverId: 's', name: 'X', lanUrl: 'http://x'),
      );
      expect(migrated, isFalse);
      expect((await directory.read()).map((e) => e.id), <String>['a']);
    });

    test('does not migrate a null or address-less profile', () async {
      expect(await directory.migrateLegacyProfile(null), isFalse);
      expect(
        await directory.migrateLegacyProfile(
          const ServerProfile(serverId: 's', name: 'X'),
        ),
        isFalse,
      );
      expect(await directory.read(), isEmpty);
    });
  });
}
