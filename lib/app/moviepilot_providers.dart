import 'package:dio/dio.dart' show Dio;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/library/library_service.dart';
import '../data/moviepilot/api/moviepilot_http_client.dart';
import '../data/moviepilot/moviepilot_repository.dart';
import '../data/moviepilot/moviepilot_service.dart';
import '../data/moviepilot/models/moviepilot_config.dart';
import '../data/storage/moviepilot_config_store.dart';
import '../data/storage/request_store.dart';
import '../features/request/request_controller.dart';
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

/// Signs in, verifies and clears the connection settings.
///
/// A new login verifies against the server before it is persisted: a token that
/// the instance rejects would otherwise stop the poll on its next round with
/// the same message, only later.
class MoviePilotSettings extends AsyncNotifier<MoviePilotConfig?> {
  @override
  Future<MoviePilotConfig?> build() async {
    final store = await ref.watch(moviePilotConfigStoreProvider.future);
    if (store == null) return null;
    return store.read();
  }

  /// Exchanges the account password for a token, verifies it, then persists
  /// the connection.
  ///
  /// Throws [MoviePilotException] so the dialog can show the mapped reason; a
  /// rejected login is never stored, and the password itself is not stored at
  /// all.
  Future<MoviePilotConfig> login({
    required String baseUrl,
    required String username,
    required String password,
    String? otp,
  }) async {
    final store = await ref.read(moviePilotConfigStoreProvider.future);
    final service = await ref.read(moviePilotServiceProvider.future);
    if (store == null || service == null) {
      throw StateError('MoviePilot storage unavailable');
    }
    final pending = await service.login(
      baseUrl: baseUrl,
      username: username,
      password: password,
      otp: otp,
    );
    final verified = await service.testConnection(pending);
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

/// The heartbeat the request pages poll on.
///
/// A provider rather than a constant so a widget test can replace it with an
/// empty stream and drive the rounds itself.
final Provider<Stream<void>?> requestHeartbeatProvider =
    Provider<Stream<void>?>((Ref ref) => null);

/// The one controller both 求片 pages share.
///
/// Declared at the app level rather than per page so pushing from search to
/// 我的求片 does not build a second poller: whichever page is on screen owns
/// the heartbeat, and the other one merely renders. The provider disposes the
/// controller when the app tears down.
final FutureProvider<RequestController?> requestControllerProvider =
    FutureProvider<RequestController?>((Ref ref) async {
      final service = await ref.watch(moviePilotServiceProvider.future);
      final configStore = await ref.watch(moviePilotConfigStoreProvider.future);
      final requestStore = await ref.watch(requestStoreProvider.future);
      final library = await ref.watch(requestLibraryProvider.future);
      if (service == null || configStore == null || requestStore == null) {
        return null;
      }
      final controller = RequestController(
        service: service,
        requestStore: requestStore,
        configStore: configStore,
        library: library,
        heartbeat: ref.watch(requestHeartbeatProvider),
      );
      ref.onDispose(controller.dispose);
      await controller.load();
      return controller;
    });
