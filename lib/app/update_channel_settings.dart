import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/storage/key_value_store.dart';
import '../data/update/update_models.dart';
import 'providers.dart';

/// Storage key for the user-selected update channel.
const String updateChannelStorageKey = 'update.channel.v1';

/// Raised when the channel preference cannot be persisted.
class UpdateChannelSettingsException implements Exception {
  const UpdateChannelSettingsException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Key/value store backing the update channel preference.
///
/// Reads the store created once by [bootstrapProvider] so the app never opens a
/// second backend. Tests override it with an in-memory store.
final FutureProvider<KeyValueStore?> updateChannelStoreProvider =
    FutureProvider<KeyValueStore?>((Ref ref) async {
  final services = await ref.watch(bootstrapProvider.future);
  return services.store;
});

/// Loads and persists which update channel the user opted into.
///
/// Unreadable or unknown values fall back to [UpdateChannel.stable] so an app
/// upgrade never silently joins the preview channel; write errors surface as
/// [UpdateChannelSettingsException] and keep the previous selection.
class UpdateChannelController extends AsyncNotifier<UpdateChannel> {
  @override
  Future<UpdateChannel> build() async {
    final KeyValueStore? store =
        await ref.watch(updateChannelStoreProvider.future);
    if (store == null) return UpdateChannel.stable;
    try {
      return UpdateChannel.fromId(await store.read(updateChannelStorageKey));
    } catch (_) {
      return UpdateChannel.stable;
    }
  }

  Future<void> setChannel(UpdateChannel channel) async {
    final UpdateChannel current =
        state.value ?? UpdateChannel.stable;
    if (current == channel) return;
    final KeyValueStore? store =
        await ref.read(updateChannelStoreProvider.future);
    if (store != null) {
      try {
        await store.write(updateChannelStorageKey, channel.id);
      } catch (error) {
        throw UpdateChannelSettingsException('更新渠道保存失败：$error');
      }
    }
    state = AsyncData<UpdateChannel>(channel);
  }
}

/// Selected update channel; defaults to the stable channel.
final AsyncNotifierProvider<UpdateChannelController, UpdateChannel>
    updateChannelControllerProvider =
    AsyncNotifierProvider<UpdateChannelController, UpdateChannel>(
  UpdateChannelController.new,
);
