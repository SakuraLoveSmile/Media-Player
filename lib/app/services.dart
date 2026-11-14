import 'dart:io';

import '../core/device/backup_file_picker.dart';
import '../core/device/local_subtitle_picker.dart';
import '../core/device/pip.dart';
import '../data/admin/admin_service.dart';
import '../data/api/emby_http_client.dart';
import '../data/auth/auth_service.dart';
import '../data/cast/dlna_cast_service.dart';
import '../data/danmaku/danmaku_repository.dart';
import '../data/endpoints/endpoint_probe.dart';
import '../data/endpoints/endpoint_resolver.dart';
import '../data/library/library_service.dart';
import '../data/library/poster_cache.dart';
import '../data/livetv/live_tv_service.dart';
import '../data/playback/playback_engine.dart';
import '../data/playback/playback_service.dart';
import '../data/playback/session_reporter.dart';
import '../data/playback/subtitle_repository.dart';
import '../data/storage/key_value_store.dart';
import '../data/storage/moviepilot_config_store.dart';
import '../data/storage/server_directory.dart';

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
    this.subtitles,
    this.localSubtitlePicker,
    this.backupFilePicker,
    this.pip,
    this.servers,
    this.danmaku,
    this.liveTv,
    this.admin,
    this.cast,
    this.screenshotDirectory,
    this.endpointProbe,
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

  /// S64: reachability probe for the servers list (null in test harnesses).
  final EndpointProbe? endpointProbe;
  final EndpointResolver? resolver;
  final String deviceId;

  /// The app-wide key/value store (contract §7). Non-sensitive host
  /// preferences such as the feedback orb style live here.
  final KeyValueStore? store;

  /// MoviePilot connection settings (plan S1). Null only in test harnesses that
  /// never open 求片; the production graph always provides it.
  final MoviePilotConfigStore? moviePilotConfigStore;

  /// External subtitle download/cache (B6). Null only in test harnesses.
  final SubtitleService? subtitles;

  /// Local subtitle file picker (添加本地字幕). Null only in test harnesses
  /// that never pick; widget tests inject a fake instead of the plugin.
  final LocalSubtitlePicker? localSubtitlePicker;

  /// Backup save/open picker (备份/还原, S22). Null only in test harnesses that
  /// never export or import; widget tests inject a fake instead of the plugin.
  final BackupFilePicker? backupFilePicker;

  /// Android picture-in-picture entry (S18). Null only in test harnesses that
  /// never enter PIP; widget tests inject a fake instead of the channel.
  final PipController? pip;

  /// Saved-server directory (S20): non-secret names/addresses plus the active
  /// server id. Null only in test harnesses that never open the 服务器 section;
  /// the production graph always provides it. Credentials stay in [auth].
  final ServerDirectory? servers;

  /// DandanPlay danmaku match + comments (S17). Null only in test harnesses
  /// that never load danmaku; widget tests inject a fake instead of HTTP.
  final DanmakuService? danmaku;

  /// `documents/screenshots` (S42); null in test harnesses, where the player
  /// falls back to the temp directory.
  final Directory? screenshotDirectory;

  /// Live TV channels + EPG (S21). Null only in test harnesses that never open
  /// 直播; widget tests inject a fake instead of HTTP.
  final LiveTvService? liveTv;

  /// Read-only Emby admin queries (S24). Null only in test harnesses that
  /// never open 服务器管理; widget tests inject a fake instead of HTTP.
  final AdminService? admin;

  /// DLNA renderer discovery + cast control (S19). Null only in test harnesses
  /// that never cast; widget tests inject a fake instead of LAN sockets.
  final DlnaCastService? cast;
}
