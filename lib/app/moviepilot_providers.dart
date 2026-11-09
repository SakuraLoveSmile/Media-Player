import 'package:dio/dio.dart' show Dio;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/library/library_service.dart';
import '../data/moviepilot/api/moviepilot_http_client.dart';
import '../data/moviepilot/moviepilot_repository.dart';
import '../data/moviepilot/moviepilot_service.dart';
import '../data/moviepilot/models/moviepilot_config.dart';
import '../data/storage/moviepilot_config_store.dart';
import '../data/storage/request_store.dart';
import 'providers.dart';

/// MoviePilot wiring for 求片 (plan S9).
///
/// Each piece is its own provider so a widget test can override exactly the one
/// it needs (a fake service, an in-memory store) without rebuilding the whole
/// service graph, and so the page never touches Dio or storage directly.

/// The store backing the connection settings.
final FutureProvider<MoviePilotConfigStore?> moviePilotConfigStoreProvider =
    FutureProvider<MoviePilotConfigStore?>((Ref ref) async {
      final services = await ref.watch(bootstrapProvider.future);
      return services.moviePilotConfigStore;
    });

/// The store backing the local 求片 list and the last poll snapshot.
final FutureProvider<RequestStore?> requestStoreProvider =
    FutureProvider<RequestStore?>((Ref ref) async {
      final services = await ref.watch(bootstrapProvider.future);
      final store = services.store;
      return store == null ? null : RequestStore(store);
    });

/// The MoviePilot API client.
///
/// Its own Dio instance: an Emby timeout or cancellation must never interfere
/// with MoviePilot, and the two repositories talk to different hosts.
final Provider<MoviePilotHttpClient> moviePilotClientProvider =
    Provider<MoviePilotHttpClient>((Ref ref) {
      final dio = Dio();
      ref.onDispose(dio.close);
      return MoviePilotHttpClient(dio);
    });

/// The repository, or null while storage is unavailable.
final FutureProvider<MoviePilotService?> moviePilotServiceProvider =
    FutureProvider<MoviePilotService?>((Ref ref) async {
      final store = await ref.watch(moviePilotConfigStoreProvider.future);
      if (store == null) return null;
      return MoviePilotRepository(store, ref.watch(moviePilotClientProvider));
    });

/// Library access for the "is it in Emby yet?" promotion (plan S7/S8).
final FutureProvider<LibraryService?> requestLibraryProvider =
    FutureProvider<LibraryService?>((Ref ref) async {
      final services = await ref.watch(bootstrapProvider.future);
      return services.library;
    });

/// The stored connection, or null when the user never configured one.
///
/// The settings page watches this for its subtitle; saving or clearing goes
/// through [moviePilotSettingsProvider], which updates this state in place.
final FutureProvider<MoviePilotConfig?> moviePilotConfigProvider =
    FutureProvider<MoviePilotConfig?>((Ref ref) async {
      final settings = await ref.watch(moviePilotSettingsProvider.future);
      return settings;
    });

/// Reads, verifies and clears the connection settings.
///
/// Saving verifies against the server first: a wrong token would otherwise stop
/// the poll on its next round with the same message, only later.
class MoviePilotSettings extends AsyncNotifier<MoviePilotConfig?> {
  @override
  Future<MoviePilotConfig?> build() async {
    final store = await ref.watch(moviePilotConfigStoreProvider.future);
    if (store == null) return null;
    return store.read();
  }

  /// Verifies [config] against the server, then persists it.
  ///
  /// Throws [MoviePilotException] so the dialog can show the mapped reason; a
  /// rejected token is never stored.
  Future<MoviePilotConfig> save(MoviePilotConfig config) async {
    final store = await ref.read(moviePilotConfigStoreProvider.future);
    final service = await ref.read(moviePilotServiceProvider.future);
    if (store == null || service == null) {
      throw StateError('MoviePilot storage unavailable');
    }
    final verified = await service.testConnection(config);
    await store.write(verified);
    state = AsyncData(verified);
    return verified;
  }

  /// Removes the stored connection; the local 求片 list is left alone.
  Future<void> clear() async {
    final store = await ref.read(moviePilotConfigStoreProvider.future);
    await store?.delete();
    state = const AsyncData(null);
  }
}

final AsyncNotifierProvider<MoviePilotSettings, MoviePilotConfig?>
moviePilotSettingsProvider =
    AsyncNotifierProvider<MoviePilotSettings, MoviePilotConfig?>(
      MoviePilotSettings.new,
    );
