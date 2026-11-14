import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/storage/backup_service.dart';
import 'package:media_player/data/storage/key_value_store.dart';

import '../../support/fake_backup_file_picker.dart';

void main() {
  // A credential key that must never appear in a backup, plus a couple of
  // unrelated preference-shaped keys outside the whitelist.
  const String tokenKey = 'mp.token.v1';
  const String sessionKey = 'mp.session.v1';
  const String moviePilotKey = 'mp.moviepilot.v1';
  const String strangerKey = 'app.unknown.v1';

  late InMemoryKeyValueStore store;
  late FakeBackupFilePicker picker;
  late BackupService service;

  setUp(() {
    store = InMemoryKeyValueStore();
    picker = FakeBackupFilePicker();
    service = BackupService(store, picker);
  });

  Future<void> seedPreferences() async {
    await store.write('player.subtitleStyle.v1', '{"fontSize":24}');
    await store.write('player.trackPrefs.v1', '{"audio":"jpn"}');
    await store.write('player.playbackSettings.v1', '{"hwdecEnabled":false}');
    await store.write('app.themeMode.v1', 'dark');
    await store.write('search.history.v1', '["one","two"]');
  }

  group('export', () {
    test(
      'includes only whitelisted keys and excludes planted credentials',
      () async {
        await seedPreferences();
        await store.write(tokenKey, 'super-secret-access-token');
        await store.write(sessionKey, '{"userId":"u1"}');
        await store.write(moviePilotKey, '{"token":"bearer-secret"}');
        await store.write(strangerKey, 'not-a-preference');

        final Map<String, dynamic> document = await service.export();
        final Map<String, dynamic> prefs =
            document['prefs'] as Map<String, dynamic>;

        expect(document['version'], BackupService.schemaVersion);
        expect(document['exportedAt'], isA<String>());
        expect(prefs.keys.toSet(), BackupService.preferenceKeys.toSet());
        expect(prefs.containsKey(tokenKey), isFalse);
        expect(prefs.containsKey(sessionKey), isFalse);
        expect(prefs.containsKey(moviePilotKey), isFalse);
        expect(prefs.containsKey(strangerKey), isFalse);
        // The serialized form must not leak the credential values either.
        final String encoded = jsonEncode(document);
        expect(encoded.contains('super-secret-access-token'), isFalse);
        expect(encoded.contains('bearer-secret'), isFalse);
      },
    );

    test('omits whitelisted keys that have no stored value', () async {
      await store.write('app.themeMode.v1', 'light');

      final Map<String, dynamic> prefs =
          (await service.export())['prefs'] as Map<String, dynamic>;

      expect(prefs.keys, <String>['app.themeMode.v1']);
      expect(prefs['app.themeMode.v1'], 'light');
    });
  });

  group('restore', () {
    test('round-trips an exported document into a fresh store', () async {
      await seedPreferences();
      final Map<String, dynamic> document = await service.export();

      final InMemoryKeyValueStore target = InMemoryKeyValueStore();
      final BackupService targetService = BackupService(
        target,
        FakeBackupFilePicker(),
      );
      await targetService.restore(document);

      for (final String key in BackupService.preferenceKeys) {
        expect(await target.read(key), await store.read(key));
      }
    });

    test('rejects an unsupported version and writes nothing', () async {
      await store.write('app.themeMode.v1', 'dark');
      final Map<String, dynamic> document = <String, dynamic>{
        'version': 2,
        'exportedAt': '2026-01-02T00:00:00.000Z',
        'prefs': <String, dynamic>{'app.themeMode.v1': 'light'},
      };

      await expectLater(
        service.restore(document),
        throwsA(isA<BackupException>()),
      );
      expect(await store.read('app.themeMode.v1'), 'dark');
    });

    test('rejects an unknown key and writes nothing', () async {
      final Map<String, dynamic> document = <String, dynamic>{
        'version': 1,
        'prefs': <String, dynamic>{
          'app.themeMode.v1': 'light',
          tokenKey: 'smuggled-token',
        },
      };

      await expectLater(
        service.restore(document),
        throwsA(isA<BackupException>()),
      );
      // Validation precedes any write, so even the valid key is untouched.
      expect(await store.read('app.themeMode.v1'), isNull);
      expect(await store.read(tokenKey), isNull);
    });

    test('rejects a non-map prefs shape and a non-string value', () async {
      await expectLater(
        service.restore(<String, dynamic>{'version': 1, 'prefs': 'nope'}),
        throwsA(isA<BackupException>()),
      );
      await expectLater(
        service.restore(<String, dynamic>{
          'version': 1,
          'prefs': <String, dynamic>{'app.themeMode.v1': 42},
        }),
        throwsA(isA<BackupException>()),
      );
    });

    test('writes only the whitelisted keys present in the document', () async {
      await store.write(tokenKey, 'keep-me');
      final Map<String, dynamic> document = <String, dynamic>{
        'version': 1,
        'prefs': <String, dynamic>{'app.themeMode.v1': 'light'},
      };

      await service.restore(document);

      expect(await store.read('app.themeMode.v1'), 'light');
      expect(await store.read('player.subtitleStyle.v1'), isNull);
      // A credential already in the store is never read or overwritten.
      expect(await store.read(tokenKey), 'keep-me');
    });
  });

  group('file orchestration', () {
    test('exportToFile saves JSON containing the prefs', () async {
      await seedPreferences();

      final bool saved = await service.exportToFile();

      expect(saved, isTrue);
      expect(picker.saveCalls, 1);
      expect(picker.savedName, endsWith('.json'));
      final Map<String, dynamic> document =
          jsonDecode(utf8.decode(picker.savedBytes!)) as Map<String, dynamic>;
      expect(document['version'], 1);
      expect(
        (document['prefs'] as Map<String, dynamic>).keys.toSet(),
        BackupService.preferenceKeys.toSet(),
      );
    });

    test('exportToFile reports a cancelled save dialog', () async {
      picker.saveResult = false;
      expect(await service.exportToFile(), isFalse);
      expect(picker.saveCalls, 1);
    });

    test('importFromFile applies prefs from the opened bytes', () async {
      final Uint8List bytes = utf8.encode(
        jsonEncode(<String, dynamic>{
          'version': 1,
          'prefs': <String, dynamic>{
            'app.themeMode.v1': 'dark',
            'player.playbackSettings.v1': '{"cacheSecs":45}',
          },
        }),
      );
      picker.openBytes = bytes;

      final bool restored = await service.importFromFile();

      expect(restored, isTrue);
      expect(picker.openCalls, 1);
      expect(await store.read('app.themeMode.v1'), 'dark');
      expect(
        await store.read('player.playbackSettings.v1'),
        '{"cacheSecs":45}',
      );
    });

    test(
      'importFromFile reports a cancelled open dialog and writes nothing',
      () async {
        picker.openBytes = null;
        expect(await service.importFromFile(), isFalse);
        expect(await store.read('app.themeMode.v1'), isNull);
      },
    );

    test('importFromFile rejects an unparseable file', () async {
      picker.openBytes = utf8.encode('not json');
      await expectLater(
        service.importFromFile(),
        throwsA(isA<BackupException>()),
      );
    });
  });
}
