import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/update_channel_settings.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/data/update/update_models.dart';

ProviderContainer _container(KeyValueStore store) {
  final ProviderContainer container = ProviderContainer(
    overrides: [
      updateChannelStoreProvider.overrideWith((Ref ref) async => store),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<UpdateChannel> _load(ProviderContainer container) =>
    container.read(updateChannelControllerProvider.future);

void main() {
  test('defaults to the stable channel', () async {
    expect(
      await _load(_container(InMemoryKeyValueStore())),
      UpdateChannel.stable,
    );
  });

  test('loads a persisted preview selection', () async {
    final store = InMemoryKeyValueStore();
    await store.write(updateChannelStorageKey, 'preview');
    expect(await _load(_container(store)), UpdateChannel.preview);
  });

  test('unknown persisted values fall back to stable', () async {
    final store = InMemoryKeyValueStore();
    await store.write(updateChannelStorageKey, 'nightly');
    expect(await _load(_container(store)), UpdateChannel.stable);
  });

  test('persists a channel change and ignores no-op writes', () async {
    final store = InMemoryKeyValueStore();
    final container = _container(store);
    await _load(container);

    await container
        .read(updateChannelControllerProvider.notifier)
        .setChannel(UpdateChannel.preview);
    expect(await store.read(updateChannelStorageKey), 'preview');
    expect(
      container.read(updateChannelControllerProvider).value,
      UpdateChannel.preview,
    );

    await container
        .read(updateChannelControllerProvider.notifier)
        .setChannel(UpdateChannel.preview);
    expect(await store.read(updateChannelStorageKey), 'preview');
  });

  test('surfaces a storage failure and keeps the selection', () async {
    final store = _FailingStore();
    final container = _container(store);
    await _load(container);
    await expectLater(
      container
          .read(updateChannelControllerProvider.notifier)
          .setChannel(UpdateChannel.preview),
      throwsA(isA<UpdateChannelSettingsException>()),
    );
    expect(
      container.read(updateChannelControllerProvider).value,
      UpdateChannel.stable,
    );
  });
}

class _FailingStore extends InMemoryKeyValueStore {
  @override
  Future<void> write(String key, String value) async {
    throw StateError('disk full');
  }
}
