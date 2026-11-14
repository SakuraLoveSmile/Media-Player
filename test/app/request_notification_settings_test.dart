import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/request_notification_settings.dart';
import 'package:media_player/data/storage/key_value_store.dart';

ProviderContainer _container(KeyValueStore store) {
  final container = ProviderContainer(
    overrides: [
      requestNotificationStoreProvider.overrideWith((ref) async => store),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('RequestNotificationSettings', () {
    test('both channels default to on', () async {
      final container = _container(InMemoryKeyValueStore());
      final settings = await container.read(
        requestNotificationSettingsProvider.future,
      );

      expect(settings, RequestNotificationSettings.defaults);
      expect(settings.inApp, isTrue);
      expect(settings.system, isTrue);
    });

    test('a stored value round-trips', () async {
      final store = InMemoryKeyValueStore();
      await store.write(requestNotificationStorageKey, '0|1');
      final container = _container(store);

      final settings = await container.read(
        requestNotificationSettingsProvider.future,
      );

      expect(settings.inApp, isFalse);
      expect(settings.system, isTrue);
    });

    test('a corrupt value falls back to the defaults', () async {
      final store = InMemoryKeyValueStore();
      await store.write(requestNotificationStorageKey, 'nonsense');
      final container = _container(store);

      final settings = await container.read(
        requestNotificationSettingsProvider.future,
      );

      expect(settings, RequestNotificationSettings.defaults);
    });

    test('an unreadable store falls back to the defaults', () async {
      final store = _ThrowingStore();
      final container = _container(store);

      final settings = await container.read(
        requestNotificationSettingsProvider.future,
      );

      expect(settings, RequestNotificationSettings.defaults);
    });

    test('toggling one channel preserves the other', () async {
      final store = InMemoryKeyValueStore();
      final container = _container(store);
      await container.read(requestNotificationSettingsProvider.future);

      await container
          .read(requestNotificationSettingsProvider.notifier)
          .set(system: false);

      final settings = container
          .read(requestNotificationSettingsProvider)
          .value!;
      expect(settings.system, isFalse);
      expect(settings.inApp, isTrue);
      expect(await store.read(requestNotificationStorageKey), '1|0');
    });

    test('a failed write throws and keeps the previous value', () async {
      final store = _ThrowingStore();
      final container = _container(store);
      await container.read(requestNotificationSettingsProvider.future);

      await expectLater(
        container
            .read(requestNotificationSettingsProvider.notifier)
            .set(inApp: false),
        throwsA(isA<RequestNotificationSettingsException>()),
      );
      expect(
        container.read(requestNotificationSettingsProvider).value,
        RequestNotificationSettings.defaults,
      );
    });

    test('setting the value it already has writes nothing', () async {
      final store = _CountingStore();
      final container = _container(store);
      await container.read(requestNotificationSettingsProvider.future);

      await container
          .read(requestNotificationSettingsProvider.notifier)
          .set(inApp: true);

      expect(store.writes, 0);
    });
  });
}

class _ThrowingStore implements KeyValueStore {
  @override
  Future<String?> read(String key) async => throw StateError('unreadable');

  @override
  Future<void> write(String key, String value) async =>
      throw StateError('read-only');

  @override
  Future<void> delete(String key) async {}
}

class _CountingStore extends InMemoryKeyValueStore {
  int writes = 0;

  @override
  Future<void> write(String key, String value) {
    writes++;
    return super.write(key, value);
  }
}
