import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/storage/key_value_store.dart';
import 'preference_keys.dart';
import 'providers.dart';

/// Storage key for the libraries the user chose to hide (S32).
const String hiddenLibrariesStorageKey = AppPreferenceKeys.hiddenLibraries;

/// Raised when the hidden-library list cannot be persisted.
class HiddenLibrariesException implements Exception {
  const HiddenLibrariesException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Key/value store backing the hidden-library list; reads the store created
/// once by [bootstrapProvider].
final FutureProvider<KeyValueStore?> hiddenLibrariesStoreProvider =
    FutureProvider<KeyValueStore?>((Ref ref) async {
      final services = await ref.watch(bootstrapProvider.future);
      return services.store;
    });

/// Loads and persists the hidden media libraries, identified by Emby view id.
///
/// Hiding is a browsing preference: the home strip, the library's view chips
/// and the settings page all read the same set, so a hidden library disappears
/// from every entry point without touching the server. Unknown or corrupt
/// stored values fall back to an empty set.
class HiddenLibrariesController extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() async {
    final KeyValueStore? store = await ref.watch(
      hiddenLibrariesStoreProvider.future,
    );
    if (store == null) return <String>{};
    try {
      return decodeHiddenLibraries(await store.read(hiddenLibrariesStorageKey));
    } catch (_) {
      return <String>{};
    }
  }

  /// Hides ([hidden] true) or shows a library. A failed write keeps the
  /// previous set so the UI never claims a preference it did not save.
  Future<void> setHidden(String viewId, bool hidden) async {
    if (viewId.isEmpty) return;
    final Set<String> current = state.value ?? <String>{};
    final Set<String> next = <String>{...current};
    if (hidden) {
      next.add(viewId);
    } else {
      next.remove(viewId);
    }
    if (next.length == current.length && !(hidden ^ current.contains(viewId))) {
      return;
    }
    final KeyValueStore? store = await ref.read(
      hiddenLibrariesStoreProvider.future,
    );
    if (store != null) {
      try {
        await store.write(
          hiddenLibrariesStorageKey,
          jsonEncode(next.toList(growable: false)),
        );
      } catch (error) {
        throw HiddenLibrariesException('媒体库偏好保存失败：$error');
      }
    }
    if (!ref.mounted) return;
    state = AsyncData<Set<String>>(next);
  }

  /// Convenience flip for a switch row.
  Future<void> toggle(String viewId) async {
    final Set<String> current = state.value ?? <String>{};
    await setHidden(viewId, !current.contains(viewId));
  }
}

/// Tolerant decode: a JSON array of view ids; anything else means none hidden.
Set<String> decodeHiddenLibraries(String? raw) {
  final String? text = raw?.trim();
  if (text == null || text.isEmpty) return <String>{};
  try {
    final Object? decoded = jsonDecode(text);
    if (decoded is! List) return <String>{};
    return decoded.whereType<String>().where((id) => id.isNotEmpty).toSet();
  } catch (_) {
    return <String>{};
  }
}

final AsyncNotifierProvider<HiddenLibrariesController, Set<String>>
hiddenLibrariesControllerProvider =
    AsyncNotifierProvider<HiddenLibrariesController, Set<String>>(
      HiddenLibrariesController.new,
    );
