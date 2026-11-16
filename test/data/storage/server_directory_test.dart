import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/network/endpoint_kind.dart';
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

  group('profile reconciliation (S81)', () {
    test('repairs a stale profile from card addresses', () async {
      await directory.add(home);
      final profiles = ProfileStore(kv, serverId: 'a');
      await profiles.write(
        const ServerProfile(
          serverId: 'server-1',
          name: 'Home',
          lanUrl: 'http://old:8096',
          wanUrl: 'https://old.example.com',
          preference: EndpointPreference.wan,
        ),
      );

      await directory.reconcileProfiles();

      final repaired = (await profiles.read())!;
      expect(repaired.lanUrl, home.lanUrl);
      expect(repaired.wanUrl, home.wanUrl);
      expect(repaired.serverId, 'server-1');
      expect(repaired.preference, EndpointPreference.wan);
    });

    test('does not clear a profile address the card does not have', () async {
      await directory.add(
        const ServerEntry(
          id: 'a',
          name: 'Home',
          lanUrl: 'http://192.168.1.10:8096',
        ),
      );
      final profiles = ProfileStore(kv, serverId: 'a');
      await profiles.write(
        const ServerProfile(
          serverId: 'server-1',
          name: 'Home',
          lanUrl: 'http://old:8096',
          wanUrl: 'https://keep.example.com',
        ),
      );

      await directory.reconcileProfiles();

      final repaired = (await profiles.read())!;
      expect(repaired.lanUrl, 'http://192.168.1.10:8096');
      expect(repaired.wanUrl, 'https://keep.example.com');
    });

    test('falls back to auto when the forced address is missing', () async {
      await directory.add(
        const ServerEntry(
          id: 'a',
          name: 'Home',
          wanUrl: 'https://new.example.com',
        ),
      );
      final profiles = ProfileStore(kv, serverId: 'a');
      await profiles.write(
        const ServerProfile(
          serverId: 'server-1',
          name: 'Home',
          wanUrl: 'https://old.example.com',
          preference: EndpointPreference.lan,
        ),
      );

      await directory.reconcileProfiles();

      final repaired = (await profiles.read())!;
      expect(repaired.wanUrl, 'https://new.example.com');
      expect(repaired.preference, EndpointPreference.auto);
    });

    test('leaves a matching profile untouched', () async {
      await directory.add(home);
      final profiles = ProfileStore(kv, serverId: 'a');
      await profiles.write(
        const ServerProfile(
          serverId: 'server-1',
          name: 'Home',
          lanUrl: 'http://192.168.1.10:8096',
          wanUrl: 'https://home.example.com',
        ),
      );
      final before = await kv.read(ProfileStore(kv, serverId: 'a').scopedKey);

      await directory.reconcileProfiles();

      final after = await kv.read(ProfileStore(kv, serverId: 'a').scopedKey);
      expect(after, before);
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

  group('per-server display preferences (S80)', () {
    test('update applies a change and keeps the default flags', () async {
      await directory.add(home);

      await directory.update(
        'a',
        (entry) => entry.copyWith(customIcon: 'tv', showLastPlayed: true),
      );

      final entry = (await directory.read()).single;
      expect(entry.customIcon, 'tv');
      expect(entry.showLastPlayed, isTrue);
      // A v1 payload had no flags: the defaults must survive the rewrite.
      expect(entry.showUserName, isTrue);
      expect(entry.name, 'Home');
    });

    test('update on an unknown id is a no-op', () async {
      await directory.add(home);
      await directory.update('missing', (entry) => entry.copyWith(name: 'X'));
      expect((await directory.read()).single.name, 'Home');
    });

    test('the new fields round-trip through storage', () async {
      final at = DateTime.fromMillisecondsSinceEpoch(1794814299000);
      await directory.add(
        home.copyWith(
          customIcon: 'router',
          showUserName: false,
          showLastPlayed: true,
          lastPlayedAt: at,
        ),
      );

      final entry = (await ServerDirectory(kv).read()).single;
      expect(entry.customIcon, 'router');
      expect(entry.showUserName, isFalse);
      expect(entry.showLastPlayed, isTrue);
      expect(
        entry.lastPlayedAt?.millisecondsSinceEpoch,
        at.millisecondsSinceEpoch,
      );
    });

    test('clearing copyWith drops an address and the time', () async {
      await directory.add(home.copyWith(lastPlayedAt: DateTime(2026, 11, 16)));

      await directory.update(
        'a',
        (entry) => entry.copyWith(wanUrl: '', clearLastPlayed: true),
      );

      final entry = (await directory.read()).single;
      expect(entry.wanUrl, isNull);
      expect(entry.lanUrl, 'http://192.168.1.10:8096');
      expect(entry.lastPlayedAt, isNull);
    });

    test('a v1 payload still loads and is rewritten as v2', () async {
      await kv.write(
        ServerDirectory.key,
        jsonEncode(<String, dynamic>{
          'schemaVersion': 1,
          'activeId': 'a',
          'servers': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'a',
              'name': 'Home',
              'lanUrl': 'http://192.168.1.10:8096',
            },
          ],
        }),
      );

      final entries = await directory.read();
      expect(entries.single.name, 'Home');
      // S80 fields fall back to their defaults on a v1 entry.
      expect(entries.single.customIcon, '');
      expect(entries.single.showUserName, isTrue);
      expect(entries.single.showLastPlayed, isFalse);
      expect(entries.single.lastPlayedAt, isNull);

      await directory.rename('a', '客厅');
      final raw = jsonDecode(
        (await kv.read(ServerDirectory.key))!,
      ) as Map<String, dynamic>;
      expect(raw['schemaVersion'], 2);
    });
  });
}
