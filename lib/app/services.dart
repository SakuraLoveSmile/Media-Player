import '../data/api/emby_http_client.dart';
import '../data/auth/auth_service.dart';
import '../data/endpoints/endpoint_resolver.dart';
import '../data/library/library_service.dart';
import '../data/playback/playback_engine.dart';
import '../data/playback/playback_service.dart';
import '../data/playback/session_reporter.dart';

/// Everything the app needs once storage, HTTP and auth are wired.
class AppServices {
  const AppServices({
    required this.auth,
    required this.library,
    required this.playback,
    required this.createEngine,
    required this.createReporter,
    this.client,
    this.resolver,
    this.deviceId = '',
  });

  final AuthService auth;
  final LibraryService library;
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
}
