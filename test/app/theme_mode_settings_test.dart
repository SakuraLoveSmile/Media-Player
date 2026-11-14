import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/theme_mode_settings.dart';
import 'package:media_player/data/storage/key_value_store.dart';

ProviderContainer _container(KeyValueStore? store) {
  final ProviderContainer container = ProviderContainer(
    overrides: [themeModeStoreProvider.overrideWith((Ref ref) async => store)],
  );
  addTearDown(container.dispose);
  return container;
}

Future<ThemeMode> _load(ProviderContainer container) =>
    container.read(themeModeControllerProvider.future);

void main() {
  test('defaults to following the system', () async {
    expect(await _load(_container(InMemoryKeyValueStore())), ThemeMode.system);
  });

  test('loads a persisted light selection', () async {
    final store = InMemoryKeyValueStore();
    await store.write(themeModeStorageKey, 'light');
    expect(await _load(_container(store)), ThemeMode.light);
  });

  test('loads a persisted dark selection', () async {
    final store = InMemoryKeyValueStore();
    await store.write(themeModeStorageKey, 'dark');
    expect(await _load(_container(store)), ThemeMode.dark);
  });

  test('corrupt persisted values fall back to system', () async {
    for (final String raw in <String>[
      '',
      '   ',
      'neon',
      'Dark',
      '0',
      'system|1',
    ]) {
      final store = InMemoryKeyValueStore();
      await store.write(themeModeStorageKey, raw);
      expect(
        await _load(_container(store)),
        ThemeMode.system,
        reason: 'raw value "$raw" must not pick a palette',
      );
    }
  });

  test('a surrounding whitespace still decodes', () async {
    final store = InMemoryKeyValueStore();
    await store.write(themeModeStorageKey, ' dark ');
    expect(await _load(_container(store)), ThemeMode.dark);
  });

  test('a missing store follows the system', () async {
    expect(await _load(_container(null)), ThemeMode.system);
  });

  test('a read failure falls back to system', () async {
    expect(await _load(_container(_UnreadableStore())), ThemeMode.system);
  });

  test('persists a mode change and reloads it after a restart', () async {
    final store = InMemoryKeyValueStore();
    final container = _container(store);
    await _load(container);

    await container
        .read(themeModeControllerProvider.notifier)
        .setMode(ThemeMode.dark);
    expect(await store.read(themeModeStorageKey), 'dark');
    expect(container.read(themeModeControllerProvider).value, ThemeMode.dark);

    // A fresh container is the next app launch reading the same store.
    expect(await _load(_container(store)), ThemeMode.dark);

    await container
        .read(themeModeControllerProvider.notifier)
        .setMode(ThemeMode.light);
    expect(await store.read(themeModeStorageKey), 'light');
    expect(await _load(_container(store)), ThemeMode.light);
  });

  test('ignores no-op writes', () async {
    final store = _CountingStore();
    final container = _container(store);
    await _load(container);

    await container
        .read(themeModeControllerProvider.notifier)
        .setMode(ThemeMode.system);
    expect(store.writes, 0);

    await container
        .read(themeModeControllerProvider.notifier)
        .setMode(ThemeMode.dark);
    await container
        .read(themeModeControllerProvider.notifier)
        .setMode(ThemeMode.dark);
    expect(store.writes, 1);
  });

  test('surfaces a storage failure and keeps the previous mode', () async {
    final container = _container(_FailingWriteStore());
    await _load(container);
    await expectLater(
      container
          .read(themeModeControllerProvider.notifier)
          .setMode(ThemeMode.dark),
      throwsA(isA<ThemeModeSettingsException>()),
    );
    expect(container.read(themeModeControllerProvider).value, ThemeMode.system);
  });

  test('still applies the mode when no store is available', () async {
    final container = _container(null);
    await _load(container);
    await container
        .read(themeModeControllerProvider.notifier)
        .setMode(ThemeMode.light);
    expect(container.read(themeModeControllerProvider).value, ThemeMode.light);
  });

  test('decodeThemeMode only accepts the three known names', () {
    expect(decodeThemeMode(null), ThemeMode.system);
    expect(decodeThemeMode('system'), ThemeMode.system);
    expect(decodeThemeMode('light'), ThemeMode.light);
    expect(decodeThemeMode('dark'), ThemeMode.dark);
    expect(decodeThemeMode('auto'), ThemeMode.system);
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
