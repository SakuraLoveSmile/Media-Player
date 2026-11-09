import 'package:flutter/foundation.dart';

import '../../core/errors/app_error.dart';
import '../../core/errors/emby_exception.dart';
import '../../data/library/library_service.dart';
import '../../data/models/media_item.dart';

// Keep the frozen public constructor names while the injected services stay
// private, following PlayerController's constructor convention.
// ignore_for_file: prefer_initializing_formals

class SeriesState {
  const SeriesState({
    this.series,
    this.seasons = const <MediaItem>[],
    this.selectedSeasonId,
    this.episodes = const <MediaItem>[],
    this.loading = false,
    this.episodesLoading = false,
    this.error,
    this.episodesError,
    this.unauthorized = false,
  });

  final MediaItem? series;
  final List<MediaItem> seasons;
  final String? selectedSeasonId;
  final List<MediaItem> episodes;
  final bool loading;
  final bool episodesLoading;
  final String? error;
  final String? episodesError;
  final bool unauthorized;

  static const Object _unset = Object();

  SeriesState copyWith({
    Object? series = _unset,
    List<MediaItem>? seasons,
    Object? selectedSeasonId = _unset,
    List<MediaItem>? episodes,
    bool? loading,
    bool? episodesLoading,
    Object? error = _unset,
    Object? episodesError = _unset,
    bool? unauthorized,
  }) {
    return SeriesState(
      series: identical(series, _unset) ? this.series : series as MediaItem?,
      seasons: seasons ?? this.seasons,
      selectedSeasonId: identical(selectedSeasonId, _unset)
          ? this.selectedSeasonId
          : selectedSeasonId as String?,
      episodes: episodes ?? this.episodes,
      loading: loading ?? this.loading,
      episodesLoading: episodesLoading ?? this.episodesLoading,
      error: identical(error, _unset) ? this.error : error as String?,
      episodesError: identical(episodesError, _unset)
          ? this.episodesError
          : episodesError as String?,
      unauthorized: unauthorized ?? this.unauthorized,
    );
  }
}

/// Reads seasons and episodes; playback remains a separate per-item session.
class SeriesController extends ChangeNotifier {
  SeriesController({required String seriesId, required LibraryService library})
    : _seriesId = seriesId,
      _library = library;

  final String _seriesId;
  final LibraryService _library;
  SeriesState _state = const SeriesState();
  bool _disposed = false;
  int _episodeRequest = 0;

  SeriesState get state => _state;

  Future<void> load() async {
    if (_disposed || _state.loading || _state.unauthorized) return;
    // Invalidates any earlier refresh as well as a previous season selection.
    _episodeRequest++;
    _set(
      _state.copyWith(
        loading: true,
        episodesLoading: false,
        error: null,
        episodesError: null,
      ),
    );
    try {
      final series = await _library.item(_seriesId);
      if (_disposed || _state.unauthorized) return;
      if (series.type != 'Series') {
        _set(SeriesState(series: series, error: '这个条目不是剧集，请返回媒体库选择剧集'));
        return;
      }
      final seasons = _byIndex(await _library.seasons(_seriesId));
      if (_disposed || _state.unauthorized) return;
      final selected = seasons
          .where(
            (season) => season.indexNumber != null && season.indexNumber! > 0,
          )
          .firstOrNull;
      final seasonId = (selected ?? seasons.firstOrNull)?.id;
      _set(
        SeriesState(
          series: series,
          seasons: seasons,
          selectedSeasonId: seasonId,
        ),
      );
      if (seasonId != null) {
        await _loadEpisodes(seasonId, keepContent: false);
      }
    } catch (error) {
      if (_handleUnauthorized(error) || _disposed || _state.unauthorized) {
        return;
      }
      _set(_state.copyWith(loading: false, error: _errorMessage(error)));
    }
  }

  Future<void> selectSeason(String seasonId) async {
    if (_disposed ||
        _state.loading ||
        _state.unauthorized ||
        !_state.seasons.any((season) => season.id == seasonId)) {
      return;
    }
    if (_state.selectedSeasonId == seasonId &&
        (_state.episodesLoading || _state.episodesError == null)) {
      return;
    }
    await _loadEpisodes(seasonId, keepContent: false);
  }

  /// Retains both selection and visible rows while obtaining server progress.
  Future<void> refreshEpisodes() async {
    final seasonId = _state.selectedSeasonId;
    if (_disposed ||
        _state.loading ||
        _state.unauthorized ||
        seasonId == null) {
      return;
    }
    await _loadEpisodes(seasonId, keepContent: true);
  }

  Future<void> _loadEpisodes(
    String seasonId, {
    required bool keepContent,
  }) async {
    final request = ++_episodeRequest;
    _set(
      _state.copyWith(
        selectedSeasonId: seasonId,
        episodes: keepContent ? _state.episodes : const <MediaItem>[],
        episodesLoading: true,
        episodesError: null,
      ),
    );
    try {
      final episodes = await _library.episodes(
        seriesId: _seriesId,
        seasonId: seasonId,
      );
      if (!_isCurrent(request)) return;
      _set(
        _state.copyWith(episodes: _byIndex(episodes), episodesLoading: false),
      );
    } catch (error) {
      // An obsolete request can still reveal that the repository cleared the
      // session. Ordinary failures, unlike 401, belong only to their request.
      if (_handleUnauthorized(error) || !_isCurrent(request)) return;
      _set(
        _state.copyWith(
          episodesLoading: false,
          episodesError: _errorMessage(error),
        ),
      );
    }
  }

  bool _isCurrent(int request) =>
      !_disposed && !_state.unauthorized && request == _episodeRequest;

  bool _handleUnauthorized(Object error) {
    if (error is! EmbyException || error.code != AppErrorCode.unauthorized) {
      return false;
    }
    if (!_disposed) {
      _episodeRequest++;
      _set(
        _state.copyWith(
          loading: false,
          episodesLoading: false,
          error: null,
          episodesError: null,
          unauthorized: true,
        ),
      );
    }
    return true;
  }

  void _set(SeriesState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _episodeRequest++;
    super.dispose();
  }
}

List<MediaItem> _byIndex(List<MediaItem> items) {
  // Dart's sort is not stable; retain server order explicitly for equal or
  // absent numbers rather than inventing a secondary alphabetical order.
  final indexed = items.indexed.toList();
  indexed.sort((a, b) {
    final left = a.$2.indexNumber;
    final right = b.$2.indexNumber;
    final comparison = left == null
        ? (right == null ? 0 : 1)
        : (right == null ? -1 : left.compareTo(right));
    return comparison == 0 ? a.$1.compareTo(b.$1) : comparison;
  });
  return List<MediaItem>.unmodifiable(indexed.map((entry) => entry.$2));
}

String _errorMessage(Object error) {
  final code = error is EmbyException ? error.code : null;
  return switch (code) {
    AppErrorCode.forbidden => '没有访问该剧集的权限',
    AppErrorCode.networkUnreachable => '无法连接服务器，请检查网络',
    AppErrorCode.tlsUntrusted => '服务器证书不受信任',
    AppErrorCode.notFound => '内容不存在或已被移除',
    _ => '加载失败，请稍后重试',
  };
}
