import '../data/api/emby_http_client.dart';
import '../data/auth/auth_service.dart';
import '../data/endpoints/endpoint_resolver.dart';
import '../data/library/library_service.dart';
import '../data/library/poster_cache.dart';
import '../data/playback/playback_engine.dart';
import '../data/playback/playback_service.dart';
import '../data/playback/session_reporter.dart';
import '../data/storage/key_value_store.dart';
import '../data/storage/moviepilot_config_store.dart';

/// Everything the app needs once storage, HTTP and auth are wired.
class AppServices {
  const AppServices({
    required this.auth,
    required this.library,
    required this.posters,
    required this.playback,
    required this.createEngine,
    required this.createReporter,
    this.client,
    this.resolver,
    this.deviceId = '',
    this.store,
    this.moviePilotConfigStore,
  });

  final AuthService auth;
  final LibraryService library;

  /// Library posters. The URL carries `api_key`, so the cache owns the fetch
  /// itself and nothing token-bearing reaches the disk (contract §10.6).
  final PosterCache posters;

  final PlaybackService playback;

  /// One engine per playback: the implementation owns a libmpv instance that
  /// must not be shared between items (contract §5).
  final PlaybackEngine Function() createEngine;

  /// One reporter per playback: it keeps the "already stopped" flag that makes
  /// `Stopped` idempotent (contract §10.9 c).
  final PlaybackReporter Function() createReporter;

  final EmbyHttpClient? client;
  final EndpointResolver? resolver;
  final String deviceId;

  /// The app-wide key/value store (contract §7). Non-sensitive host
  /// preferences such as the feedback orb style live here.
  final KeyValueStore? store;

  /// MoviePilot connection settings (plan S1). Null only in test harnesses that
  /// never open 求片; the production graph always provides it.
  final MoviePilotConfigStore? moviePilotConfigStore;
}
