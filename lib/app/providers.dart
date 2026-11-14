import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/config/app_config.dart';
import '../core/device/backup_file_picker.dart';
import '../core/device/device_info.dart';
import '../core/device/local_subtitle_picker.dart';
import '../core/device/pip.dart';
import '../core/device/screen_orientation.dart';
import '../data/admin/admin_repository.dart';
import '../data/api/emby_http_client.dart';
import '../data/auth/auth_repository.dart';
import '../data/cast/dlna_cast_service.dart';
import '../data/danmaku/api/dandanplay_client.dart';
import '../data/danmaku/danmaku_repository.dart';
import '../data/endpoints/endpoint_probe.dart';
import '../data/endpoints/endpoint_resolver.dart';
import '../data/library/library_repository.dart';
import '../data/library/poster_cache.dart';
import '../data/livetv/live_tv_repository.dart';
import '../data/playback/media_kit_engine.dart';
import '../data/playback/playback_repository.dart';
import '../data/playback/session_reporter.dart';
import '../data/playback/subtitle_repository.dart';
import '../data/storage/device_id_store.dart';
import '../data/storage/moviepilot_config_store.dart';
import '../data/storage/profile_store.dart';
import '../data/storage/server_directory.dart';
import '../data/storage/session_store.dart';
import '../data/storage/storage_factory.dart';
import '../data/storage/token_store.dart';
import 'preference_keys.dart';
import 'services.dart';

/// Builds the single app-wide service graph. Widget tests override this
/// provider so no plugin or network call happens.
final bootstrapProvider = FutureProvider<AppServices>((ref) async {
  final store = await createKeyValueStore(
    log: (message) => debugPrint('[storage] $message'),
  );
  final deviceId = await DeviceIdStore(store).getOrCreate();

  final dio = Dio();
  // 忽略 SSL 证书错误 (S32): the client is built before Riverpod exists, so the
  // preference is read straight from the store; enabling it applies to the
  // next launch, exactly what the settings row says.
  try {
    if (await store.read(AppPreferenceKeys.ignoreSsl) == 'true') {
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final HttpClient httpClient = HttpClient();
          httpClient.badCertificateCallback = (
            X509Certificate cert,
            String host,
            int port,
          ) => true;
          return httpClient;
        },
      );
    }
  } catch (_) {
    // A broken preference keeps the default certificate checks.
  }
  final client = EmbyHttpClient(dio, deviceId: deviceId);
  final probe = HttpEndpointProbe(client);
  final resolver = EndpointResolver(probe);
  final auth = AuthRepository(
    client: client,
    resolver: resolver,
    tokenStore: TokenStore(store),
    sessionStore: SessionStore(store),
    profileStore: ProfileStore(store),
    store: store,
    deviceId: deviceId,
    clientName: AppConfig.clientName,
    deviceName: defaultDeviceName(),
    appVersion: AppConfig.appVersion,
  );

  // S20: migrate a legacy single-server install to the directory, then point
  // auth at the last active server so restore-first startup recovers it. The
  // `default` id reuses the original credential keys, so no token is moved.
  final servers = ServerDirectory(store);
  await servers.migrateLegacyProfile(await ProfileStore(store).read());
  auth.useServer(await servers.activeId());

  // S17: DandanPlay is a separate public API (no Emby auth), so it gets its
  // own dio instance and client; the repository is the non-fatal boundary.
  final danmakuDio = Dio();
  final library = LibraryRepository(auth);

  ref.onDispose(() {
    auth.dispose();
    dio.close(force: true);
    danmakuDio.close(force: true);
  });

  final support = await getApplicationSupportDirectory();
  // S42: screenshots land in a stable, user-visible-in-app folder. Documents
  // can be unavailable on some platforms; the player then uses its temp dir.
  Directory? screenshotDirectory;
  try {
    final Directory docs = await getApplicationDocumentsDirectory();
    screenshotDirectory = Directory('${docs.path}/screenshots');
  } catch (_) {
    screenshotDirectory = null;
  }
  return AppServices(
    auth: auth,
    library: library,
    // The poster URL carries api_key, so it goes straight to dio and never to
    // disk; no X-Emby-Token header, exactly like the previous Image.network.
    posters: FilePosterCache(
      directory: Directory('${support.path}/posters_v1'),
      fetch: client.getBytes,
    ),
    playback: PlaybackRepository(auth),
    subtitles: SubtitleRepository(
      auth,
      directory: Directory('${support.path}/subtitles_v1'),
      fetch: client.getBytes,
    ),
    localSubtitlePicker: const FilePickerLocalSubtitlePicker(),
    backupFilePicker: const FilePickerBackupFilePicker(),
    // S18: only Android has the MainActivity channel; every other platform
    // gets the no-op so a stray call can never throw.
    pip: !kIsWeb && Platform.isAndroid
        ? const MethodChannelPipController()
        : const NoopPipController(),
    // Factories, not instances: each playback needs its own libmpv instance
    // and its own "already stopped" flag (contract §5, §10.9 c).
    createEngine: MediaKitEngine.new,
    createReporter: () => SessionReporter(auth),
    client: client,
    resolver: resolver,
    deviceId: deviceId,
    store: store,
    endpointProbe: probe,
    screenshotDirectory: screenshotDirectory,
    // Settings only for now; the MoviePilot client is wired in S4/S9 so this
    // slice adds no HTTP surface.
    moviePilotConfigStore: MoviePilotConfigStore(store),
    servers: servers,
    danmaku: DanmakuRepository(
      client: DandanPlayClient(danmakuDio),
      library: library,
      store: store,
    ),
    // S21: Live TV shares the authenticated session, so it derives every URL
    // from the same resolved endpoint as the library and playback repositories.
    liveTv: LiveTvRepository(auth),
    // S24: read-only admin queries share the same authenticated session.
    admin: AdminRepository(auth),
    // S19: DLNA discovery + cast over the LAN, independent of the Emby session.
    cast: DlnaCastServiceImpl(),
  );
});

/// Player screen-orientation pin (S77): the player locks the screen on open and
/// hands it back to the device on exit. Widget tests override this so the
/// player never reaches the `flutter/platform` channel.
final playerOrientationServiceProvider = Provider<ScreenOrientationService>(
  (ref) => const SystemScreenOrientationService(),
);
