import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../core/errors/app_error.dart';
import '../../core/errors/emby_exception.dart';
import '../../data/library/poster_cache.dart';
import '../../data/library/poster_image_provider.dart';
import '../../data/livetv/live_tv_service.dart';
import '../../data/models/live_tv_channel.dart';

/// Live TV list state (S21): the channel list plus its load/error surface.
class LiveTvState {
  const LiveTvState({
    this.channels = const <LiveTvChannel>[],
    this.loading = false,
    this.loaded = false,
    this.error,
    this.unauthorized = false,
  });

  final List<LiveTvChannel> channels;
  final bool loading;

  /// True once a load attempt finished, so the empty state is not shown while
  /// the first request is still in flight.
  final bool loaded;
  final String? error;
  final bool unauthorized;

  bool get isEmpty => channels.isEmpty;

  static const Object _unset = Object();

  LiveTvState copyWith({
    List<LiveTvChannel>? channels,
    bool? loading,
    bool? loaded,
    Object? error = _unset,
    bool? unauthorized,
  }) {
    return LiveTvState(
      channels: channels ?? this.channels,
      loading: loading ?? this.loading,
      loaded: loaded ?? this.loaded,
      error: identical(error, _unset) ? this.error : error as String?,
      unauthorized: unauthorized ?? this.unauthorized,
    );
  }
}

/// Drives the live page (S21): one channel list request, stale answers
/// discarded, failures mapped to copy. Mirrors `LibraryController`'s shape so
/// the page never touches HTTP.
class LiveTvController extends ChangeNotifier {
  LiveTvController(this._service, this._posters);

  final LiveTvService _service;
  final PosterCache _posters;

  LiveTvState _state = const LiveTvState();
  bool _disposed = false;
  int _seq = 0;

  LiveTvState get state => _state;

  Future<void> load() async {
    if (_state.loading) return;
    final int seq = ++_seq;
    _set(_state.copyWith(loading: true, error: null, unauthorized: false));
    try {
      final channels = await _service.channels();
      if (_disposed || seq != _seq) return;
      _set(_state.copyWith(channels: channels, loading: false, loaded: true));
    } on EmbyException catch (error) {
      if (_disposed || seq != _seq) return;
      _fail(error);
    } catch (_) {
      if (_disposed || seq != _seq) return;
      _set(_state.copyWith(loading: false, loaded: true, error: '加载失败，请稍后重试'));
    }
  }

  /// Null without a session, which is the tile's cue to show its placeholder.
  ImageProvider? posterImage(String channelId, {String? tag, int? maxWidth}) {
    final url = _service.channelImageUrl(
      channelId,
      tag: tag,
      maxWidth: maxWidth,
    );
    if (url == null) return null;
    return PosterImageProvider(
      cache: _posters,
      itemId: channelId,
      url: url,
      tag: tag,
      maxWidth: maxWidth,
    );
  }

  /// A failed load clears the list and surfaces copy (empty + error surface);
  /// an expired session still redirects through [LiveTvState.unauthorized].
  void _fail(EmbyException error) {
    _set(
      _state.copyWith(
        loading: false,
        loaded: true,
        channels: const <LiveTvChannel>[],
        error: error.code == AppErrorCode.unauthorized
            ? null
            : liveTvErrorMessage(error.code),
        unauthorized: error.code == AppErrorCode.unauthorized,
      ),
    );
  }

  void _set(LiveTvState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Maps a data-layer failure to live TV copy (contract §6).
String liveTvErrorMessage(AppErrorCode code) {
  return switch (code) {
    AppErrorCode.unauthorized => '登录已过期，请重新登录',
    AppErrorCode.forbidden => '没有访问直播的权限',
    AppErrorCode.networkUnreachable => '无法连接服务器，请检查网络',
    AppErrorCode.tlsUntrusted => '服务器证书不受信任',
    AppErrorCode.notFound => '服务器未开启直播功能',
    _ => '加载失败，请稍后重试',
  };
}
