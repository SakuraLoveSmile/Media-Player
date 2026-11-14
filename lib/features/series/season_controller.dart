import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../core/errors/app_error.dart';
import '../../core/errors/emby_exception.dart';
import '../../data/library/library_service.dart';
import '../../data/library/poster_cache.dart';
import '../../data/models/media_item.dart';
import 'series_images.dart';

// Keep the frozen public constructor names while the injected services stay
// private, following SeriesController's constructor convention.
// ignore_for_file: prefer_initializing_formals

/// Everything the season page renders (S78).
class SeasonState {
  const SeasonState({
    this.series,
    this.season,
    this.episodes = const <MediaItem>[],
    this.loading = false,
    this.episodesLoading = false,
    this.error,
    this.episodesError,
    this.unauthorized = false,
    this.favoriteBusy = false,
    this.playedBusy = false,
    this.writeError,
  });

  final MediaItem? series;
  final MediaItem? season;
  final List<MediaItem> episodes;
  final bool loading;
  final bool episodesLoading;
  final String? error;
  final String? episodesError;
  final bool unauthorized;

  /// In-flight favorite/played writes; the toggles stay optimistic but cannot
  /// be double-tapped into racing requests.
  final bool favoriteBusy;
  final bool playedBusy;

  /// Non-fatal write copy; the page stays usable.
  final String? writeError;

  static const Object _unset = Object();

  SeasonState copyWith({
    Object? series = _unset,
    Object? season = _unset,
    List<MediaItem>? episodes,
    bool? loading,
    bool? episodesLoading,
    Object? error = _unset,
    Object? episodesError = _unset,
    bool? unauthorized,
    bool? favoriteBusy,
    bool? playedBusy,
    Object? writeError = _unset,
  }) {
    return SeasonState(
      series: identical(series, _unset) ? this.series : series as MediaItem?,
      season: identical(season, _unset) ? this.season : season as MediaItem?,
      episodes: episodes ?? this.episodes,
      loading: loading ?? this.loading,
      episodesLoading: episodesLoading ?? this.episodesLoading,
      error: identical(error, _unset) ? this.error : error as String?,
      episodesError: identical(episodesError, _unset)
          ? this.episodesError
          : episodesError as String?,
      unauthorized: unauthorized ?? this.unauthorized,
      favoriteBusy: favoriteBusy ?? this.favoriteBusy,
      playedBusy: playedBusy ?? this.playedBusy,
      writeError: identical(writeError, _unset)
          ? this.writeError
          : writeError as String?,
    );
  }

  /// Season number used to label rows: S1E2 on the series page, 第 1 季 here.
  int? get seasonNumber => season?.indexNumber;

  /// True once the server marks the whole season watched (S78).
  bool get watched => season?.userData.played ?? false;

  /// The episode the big play button starts (S78): the in-progress one, else
  /// the first unwatched one, else the first episode.
  MediaItem? get playTarget {
    for (final MediaItem episode in episodes) {
      if (!episode.userData.played && episode.userData.positionTicks > 0) {
        return episode;
      }
    }
    for (final MediaItem episode in episodes) {
      if (!episode.userData.played) return episode;
    }
    return episodes.isEmpty ? null : episodes.first;
  }
}

/// Drives one season's episode list (S78). The series detail only supplies the
/// hero and title, so a season page can be opened straight from the 季 row.
class SeasonController extends ChangeNotifier {
  SeasonController({
    required String seriesId,
    required String seasonId,
    required LibraryService library,
    PosterCache? posters,
  }) : _seriesId = seriesId,
       _seasonId = seasonId,
       _library = library,
       _images = SeriesImages(library: library, posters: posters);

  final String _seriesId;
  final String _seasonId;
  final LibraryService _library;
  final SeriesImages _images;
  SeasonState _state = const SeasonState();
  bool _disposed = false;
  int _episodeRequest = 0;

  SeasonState get state => _state;

  /// The series backdrop for the hero (null without a cache or tag).
  ImageProvider? backdropImage(
    MediaItem item, {
    int index = 0,
    int maxWidth = 1200,
  }) => _images.backdrop(item, index: index, maxWidth: maxWidth);

  /// Poster fallback for the hero and the episode stills.
  ImageProvider? posterImage(
    String itemId, {
    String? tag,
    int maxWidth = 260,
  }) => _images.poster(itemId, tag: tag, maxWidth: maxWidth);

  /// Episode still (S47): the series-level Thumb when the episode has no
  /// Primary of its own.
  ImageProvider? episodeImage(MediaItem episode) => _images.episode(episode);

  Future<void> load() async {
    if (_disposed || _state.loading || _state.unauthorized) return;
    _episodeRequest++;
    _set(
      _state.copyWith(
        loading: true,
        episodesLoading: false,
        error: null,
        episodesError: null,
        writeError: null,
      ),
    );
    try {
      final series = await _library.item(_seriesId);
      if (_disposed || _state.unauthorized) return;
      final season = await _library.item(_seasonId);
      if (_disposed || _state.unauthorized) return;
      final episodes = await _library.episodes(
        seriesId: _seriesId,
        seasonId: _seasonId,
      );
      if (_disposed || _state.unauthorized) return;
      _set(
        SeasonState(
          series: series,
          season: season,
          episodes: _byIndex(episodes),
        ),
      );
    } catch (error) {
      if (_handleUnauthorized(error) || _disposed || _state.unauthorized) {
        return;
      }
      _set(_state.copyWith(loading: false, error: _errorMessage(error)));
    }
  }

  /// Retains the visible rows while obtaining updated server progress, e.g.
  /// after the player reported back.
  Future<void> refreshEpisodes() async {
    if (_disposed ||
        _state.loading ||
        _state.unauthorized ||
        _state.season == null) {
      return;
    }
    final request = ++_episodeRequest;
    _set(_state.copyWith(episodesLoading: true, episodesError: null));
    try {
      final episodes = await _library.episodes(
        seriesId: _seriesId,
        seasonId: _seasonId,
      );
      if (!_isCurrent(request)) return;
      _set(
        _state.copyWith(episodes: _byIndex(episodes), episodesLoading: false),
      );
    } catch (error) {
      if (_handleUnauthorized(error) || !_isCurrent(request)) return;
      _set(
        _state.copyWith(
          episodesLoading: false,
          episodesError: _errorMessage(error),
        ),
      );
    }
  }

  /// Re-reads the season and its episodes without dropping the page (S78).
  Future<void> refresh() async {
    if (_disposed || _state.loading || _state.unauthorized) return;
    if (_state.season == null) {
      await load();
      return;
    }
    final request = ++_episodeRequest;
    _set(_state.copyWith(loading: true, error: null, writeError: null));
    try {
      final series = await _library.item(_seriesId);
      if (!_isCurrent(request)) return;
      final season = await _library.item(_seasonId);
      if (!_isCurrent(request)) return;
      final episodes = await _library.episodes(
        seriesId: _seriesId,
        seasonId: _seasonId,
      );
      if (!_isCurrent(request)) return;
      _set(
        _state.copyWith(
          series: series,
          season: season,
          episodes: _byIndex(episodes),
          loading: false,
          episodesLoading: false,
          error: null,
        ),
      );
    } catch (error) {
      if (_handleUnauthorized(error) || !_isCurrent(request)) return;
      _set(_state.copyWith(loading: false, error: _errorMessage(error)));
    }
  }

  /// Optimistic favorite flip on the season item (S78), with rollback.
  Future<void> toggleFavorite() async {
    final item = _state.season;
    if (item == null || _state.favoriteBusy) return;
    final next = !item.userData.isFavorite;
    _set(
      _state.copyWith(
        season: item.copyWith(
          userData: item.userData.copyWith(isFavorite: next),
        ),
        favoriteBusy: true,
        writeError: null,
      ),
    );
    try {
      await _library.setFavorite(item.id, next);
      if (_disposed) return;
      _set(_state.copyWith(favoriteBusy: false));
    } catch (error) {
      if (_disposed || _handleUnauthorized(error)) return;
      _set(
        _state.copyWith(
          season: item,
          favoriteBusy: false,
          writeError: '收藏更新失败，请稍后重试',
        ),
      );
    }
  }

  /// Optimistic watched flip on the season item (S78), same rollback contract.
  Future<void> togglePlayed() async {
    final item = _state.season;
    if (item == null || _state.playedBusy) return;
    final next = !item.userData.played;
    _set(
      _state.copyWith(
        season: item.copyWith(userData: item.userData.copyWith(played: next)),
        playedBusy: true,
        writeError: null,
      ),
    );
    try {
      await _library.setPlayed(item.id, next);
      if (_disposed) return;
      _set(_state.copyWith(playedBusy: false));
    } catch (error) {
      if (_disposed || _handleUnauthorized(error)) return;
      _set(
        _state.copyWith(
          season: item,
          playedBusy: false,
          writeError: '观看状态更新失败，请稍后重试',
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

  void _set(SeasonState state) {
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
