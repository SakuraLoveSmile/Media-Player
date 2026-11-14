import 'dart:convert';

import 'package:flutter/material.dart' show Brightness, Color, ColorScheme;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/accent_settings.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/ui/theme/app_accent.dart';

ProviderContainer _container(KeyValueStore? store) {
  final ProviderContainer container = ProviderContainer(
    overrides: [accentStoreProvider.overrideWith((Ref ref) async => store)],
  );
  addTearDown(container.dispose);
  return container;
}

Future<AccentPreference> _load(ProviderContainer container) =>
    container.read(accentControllerProvider.future);

void main() {
  group('load', () {
    test('defaults to the brand palette with Monet off', () async {
      expect(
        await _load(_container(InMemoryKeyValueStore())),
        AccentPreference.defaults,
      );
    });

    test('loads a persisted preset selection', () async {
      final store = InMemoryKeyValueStore();
      await store.write(
        accentStorageKey,
        jsonEncode(<String, Object?>{'mode': 'preset', 'preset': 'green'}),
      );
      expect(
        await _load(_container(store)),
        const AccentPreference(mode: AccentMode.preset, preset: 'green'),
      );
    });

    test(
      'loads a persisted Monet selection with its fallback preset',
      () async {
        final store = InMemoryKeyValueStore();
        await store.write(
          accentStorageKey,
          jsonEncode(<String, Object?>{'mode': 'monet', 'preset': 'purple'}),
        );
        expect(
          await _load(_container(store)),
          const AccentPreference(mode: AccentMode.monet, preset: 'purple'),
        );
      },
    );

    test('corrupt persisted values fall back to the default', () async {
      for (final String raw in <String>[
        '',
        '   ',
        'neon',
        '{',
        '[]',
        '42',
        '{"mode":"neon"}',
        '{"mode":"preset"}',
        '{"mode":"preset","preset":"neon"}',
        '{"mode":"preset","preset":5}',
        '{"mode":1}',
        '<html>',
      ]) {
        final store = InMemoryKeyValueStore();
        await store.write(accentStorageKey, raw);
        expect(
          await _load(_container(store)),
          AccentPreference.defaults,
          reason: 'raw value "$raw" must not pick a colour',
        );
      }
    });

    test('surrounding whitespace still decodes', () async {
      final store = InMemoryKeyValueStore();
      await store.write(
        accentStorageKey,
        '  {"mode":"preset","preset":"blue"}  ',
      );
      expect(
        await _load(_container(store)),
        const AccentPreference(mode: AccentMode.preset, preset: 'blue'),
      );
    });

    test('a legacy bare preset name still decodes', () async {
      for (final String raw in <String>['green', '"green"', ' green ']) {
        final store = InMemoryKeyValueStore();
        await store.write(accentStorageKey, raw);
        expect(
          await _load(_container(store)),
          const AccentPreference(mode: AccentMode.preset, preset: 'green'),
          reason: 'legacy value "$raw"',
        );
      }
    });

    test('a legacy default name decodes to the brand default', () async {
      final store = InMemoryKeyValueStore();
      await store.write(accentStorageKey, 'default');
      expect(await _load(_container(store)), AccentPreference.defaults);
    });

    test('a missing store uses the default', () async {
      expect(await _load(_container(null)), AccentPreference.defaults);
    });

    test('a read failure falls back to the default', () async {
      expect(
        await _load(_container(_UnreadableStore())),
        AccentPreference.defaults,
      );
    });
  });

  group('persist', () {
    test('persists a preset change and reloads it after a restart', () async {
      final store = InMemoryKeyValueStore();
      final container = _container(store);
      await _load(container);

      await container
          .read(accentControllerProvider.notifier)
          .selectPreset('green');
      expect(
        jsonDecode((await store.read(accentStorageKey))!),
        <String, Object?>{'mode': 'preset', 'preset': 'green'},
      );
      expect(
        container.read(accentControllerProvider).value,
        const AccentPreference(mode: AccentMode.preset, preset: 'green'),
      );

      // A fresh container is the next app launch reading the same store.
      expect(
        await _load(_container(store)),
        const AccentPreference(mode: AccentMode.preset, preset: 'green'),
      );
    });

    test('selecting default clears the preset', () async {
      final store = InMemoryKeyValueStore();
      final container = _container(store);
      await _load(container);
      await container
          .read(accentControllerProvider.notifier)
          .selectPreset('pink');
      await container
          .read(accentControllerProvider.notifier)
          .selectPreset('default');
      expect(
        jsonDecode((await store.read(accentStorageKey))!),
        <String, Object?>{'mode': 'default'},
      );
      expect(
        container.read(accentControllerProvider).value,
        AccentPreference.defaults,
      );
    });

    test(
      'Monet keeps the preset as fallback and restores it when turned off',
      () async {
        final store = InMemoryKeyValueStore();
        final container = _container(store);
        await _load(container);
        await container
            .read(accentControllerProvider.notifier)
            .selectPreset('orange');

        await container.read(accentControllerProvider.notifier).setMonet(true);
        expect(
          jsonDecode((await store.read(accentStorageKey))!),
          <String, Object?>{'mode': 'monet', 'preset': 'orange'},
        );
        expect(
          container.read(accentControllerProvider).value,
          const AccentPreference(mode: AccentMode.monet, preset: 'orange'),
        );

        await container.read(accentControllerProvider.notifier).setMonet(false);
        expect(
          container.read(accentControllerProvider).value,
          const AccentPreference(mode: AccentMode.preset, preset: 'orange'),
        );
      },
    );

    test(
      'Monet with no preset falls back to the brand default when off',
      () async {
        final store = InMemoryKeyValueStore();
        final container = _container(store);
        await _load(container);
        await container.read(accentControllerProvider.notifier).setMonet(true);
        expect(
          container.read(accentControllerProvider).value,
          const AccentPreference(mode: AccentMode.monet),
        );
        await container.read(accentControllerProvider.notifier).setMonet(false);
        expect(
          container.read(accentControllerProvider).value,
          AccentPreference.defaults,
        );
      },
    );

    test('ignores no-op writes', () async {
      final store = _CountingStore();
      final container = _container(store);
      await _load(container);

      await container
          .read(accentControllerProvider.notifier)
          .selectPreset('default');
      expect(store.writes, 0);

      await container
          .read(accentControllerProvider.notifier)
          .selectPreset('blue');
      await container
          .read(accentControllerProvider.notifier)
          .selectPreset('blue');
      expect(store.writes, 1);
    });

    test('an unknown preset id is ignored', () async {
      final store = _CountingStore();
      final container = _container(store);
      await _load(container);
      await container
          .read(accentControllerProvider.notifier)
          .selectPreset('neon');
      expect(store.writes, 0);
      expect(
        container.read(accentControllerProvider).value,
        AccentPreference.defaults,
      );
    });

    test(
      'surfaces a storage failure and keeps the previous preference',
      () async {
        final container = _container(_FailingWriteStore());
        await _load(container);
        await expectLater(
          container
              .read(accentControllerProvider.notifier)
              .selectPreset('green'),
          throwsA(isA<AccentSettingsException>()),
        );
        expect(
          container.read(accentControllerProvider).value,
          AccentPreference.defaults,
        );
      },
    );

    test('still applies the preference when no store is available', () async {
      final container = _container(null);
      await _load(container);
      await container
          .read(accentControllerProvider.notifier)
          .selectPreset('pink');
      expect(
        container.read(accentControllerProvider).value,
        const AccentPreference(mode: AccentMode.preset, preset: 'pink'),
      );
    });
  });

  group('JSON round-trip', () {
    test('every mode survives encode/decode', () {
      const List<AccentPreference> values = <AccentPreference>[
        AccentPreference.defaults,
        AccentPreference(mode: AccentMode.preset, preset: 'blue'),
        AccentPreference(mode: AccentMode.preset, preset: 'orange'),
        AccentPreference(mode: AccentMode.monet),
        AccentPreference(mode: AccentMode.monet, preset: 'green'),
      ];
      for (final AccentPreference value in values) {
        final String encoded = jsonEncode(value.toJson());
        expect(decodeAccentPreference(encoded), value, reason: encoded);
      }
    });

    test('decode tolerates null and unknown fields', () {
      expect(decodeAccentPreference(null), AccentPreference.defaults);
      expect(
        decodeAccentPreference('{"mode":"monet","preset":"green","extra":1}'),
        const AccentPreference(mode: AccentMode.monet, preset: 'green'),
      );
      // A monet entry whose fallback is the default name normalises to null.
      expect(
        decodeAccentPreference('{"mode":"monet","preset":"default"}'),
        const AccentPreference(mode: AccentMode.monet),
      );
    });
  });

  group('resolveAccentColor', () {
    final ColorScheme dynamicLight = ColorScheme.fromSeed(
      seedColor: const Color(0xFF123456),
      brightness: Brightness.light,
    );

    test('Monet uses the system primary when available', () {
      expect(
        resolveAccentColor(
          const AccentPreference(mode: AccentMode.monet, preset: 'green'),
          dynamicLight,
        ),
        dynamicLight.primary,
      );
    });

    test('Monet falls back to the stored preset when unavailable', () {
      expect(
        resolveAccentColor(
          const AccentPreference(mode: AccentMode.monet, preset: 'green'),
          null,
        ),
        AppAccentPresets.green.color,
      );
    });

    test('Monet with no preset falls back to null (brand default)', () {
      expect(
        resolveAccentColor(
          const AccentPreference(mode: AccentMode.monet),
          null,
        ),
        isNull,
      );
    });

    test('a preset ignores the system scheme', () {
      expect(
        resolveAccentColor(
          const AccentPreference(mode: AccentMode.preset, preset: 'pink'),
          dynamicLight,
        ),
        AppAccentPresets.pink.color,
      );
    });

    test('the default mode resolves to null (brand default)', () {
      expect(
        resolveAccentColor(AccentPreference.defaults, dynamicLight),
        isNull,
      );
      expect(resolveAccentColor(AccentPreference.defaults, null), isNull);
    });
  });
}

class _CountingStore extends InMemoryKeyValueStore {
  int writes = 0;

  @override
  Future<void> write(String key, String value) async {
    writes++;
    await super.write(key, value);
  }
}

class _FailingWriteStore extends InMemoryKeyValueStore {
  @override
  Future<void> write(String key, String value) async {
    throw StateError('disk full');
  }
}

class _UnreadableStore implements KeyValueStore {
  @override
  Future<String?> read(String key) async => throw StateError('unreadable');

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}
