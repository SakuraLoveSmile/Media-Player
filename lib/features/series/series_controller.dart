import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors/app_error.dart';
import '../../core/errors/emby_exception.dart';
import '../../data/library/library_service.dart';
import '../../data/library/poster_cache.dart';
import '../../data/models/media_item.dart';
import '../../data/models/person.dart';
import 'series_images.dart';

// Keep the frozen public constructor names while the injected services stay
// private, following PlayerController's constructor convention.
// ignore_for_file: prefer_initializing_formals

/// Everything the series page renders (S78).
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
    this.similar = const <MediaItem>[],
    this.favoriteBusy = false,
    this.playedBusy = false,
    this.writeError,
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

  /// 推荐 row (S78); empty when the server has no suggestions.
  final List<MediaItem> similar;

  /// In-flight favorite/played writes; the toggles stay optimistic but cannot
  /// be double-tapped into racing requests.
  final bool favoriteBusy;
  final bool playedBusy;

  /// Non-fatal write/link copy; the page stays usable.
  final String? writeError;

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
    List<MediaItem>? similar,
    bool? favoriteBusy,
    bool? playedBusy,
    Object? writeError = _unset,
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
      similar: similar ?? this.similar,
      favoriteBusy: favoriteBusy ?? this.favoriteBusy,
      playedBusy: playedBusy ?? this.playedBusy,
      writeError: identical(writeError, _unset)
          ? this.writeError
          : writeError as String?,
    );
  }

  /// Episode count to badge on the season cards (S78), keyed by season id.
  /// Seasons the server reported no count for stay out so their badge hides
  /// instead of showing a made-up 0.
  Map<String, int> get seasonCounts => <String, int>{
    for (final MediaItem season in seasons)
      if (season.childCount > 0) season.id: season.childCount,
  };

  /// The season whose episodes back the play row and the 继续观看 strip.
  MediaItem? get selectedSeason {
    for (final MediaItem season in seasons) {
      if (season.id == selectedSeasonId) return season;
    }
    return null;
  }

  /// Episodes started but not finished (S78).
  List<MediaItem> get resumableEpisodes => episodes
      .where(
        (MediaItem episode) =>
            !episode.userData.played && episode.userData.positionTicks > 0,
      )
      .toList(growable: false);

  /// What the 继续观看 row lists (S78): every in-progress episode in order plus
  /// the next unstarted episode Yamby previews after the last one, capped at
  /// four cards. The extra row entry shows its duration instead of a remaining
  /// time, so the row never looks empty right after finishing an episode.
  List<MediaItem> get continueWatchingEpisodes {
    final List<MediaItem> cards = <MediaItem>[];
    int lastProgress = -1;
    for (int index = 0; index < episodes.length; index++) {
      final MediaItem episode = episodes[index];
      if (episode.userData.played || episode.userData.positionTicks <= 0) {
        continue;
      }
      cards.add(episode);
      lastProgress = index;
    }
    if (cards.isEmpty) return const <MediaItem>[];
    if (lastProgress + 1 < episodes.length) {
      cards.add(episodes[lastProgress + 1]);
    }
    return cards.take(4).toList(growable: false);
  }

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

  /// True once the server marks the whole series watched (S78), which is what
  /// turns the play row into 已播放.
  bool get watched => series?.userData.played ?? false;
}

/// Reads the series detail, its seasons and the selected season's episodes;
/// playback remains a separate per-item session (S78).
class SeriesController extends ChangeNotifier {
  SeriesController({
    required String seriesId,
    required LibraryService library,
    PosterCache? posters,
    Future<bool> Function(Uri url)? urlOpener,
  }) : _seriesId = seriesId,
       _library = library,
       _images = SeriesImages(library: library, posters: posters),
       _urlOpener = urlOpener ?? _launchUrl;

  final String _seriesId;
  final LibraryService _library;
  final SeriesImages _images;
  final Future<bool> Function(Uri url) _urlOpener;
  SeriesState _state = const SeriesState();
  bool _disposed = false;
  int _episodeRequest = 0;

  SeriesState get state => _state;

  /// S49: the series backdrop for the hero (null without a cache or tag).
  ImageProvider? backdropImage(
    MediaItem item, {
    int index = 0,
    int maxWidth = 1100,
  }) => _images.backdrop(item, index: index, maxWidth: maxWidth);

  /// Season/similar posters (S78).
  ImageProvider? posterImage(
    String itemId, {
    String? tag,
    int maxWidth = 260,
  }) => _images.poster(itemId, tag: tag, maxWidth: maxWidth);

  /// Person headshots for the 演员 row (S78).
  ImageProvider? personImage(Person person) => _images.person(person);

  /// S47: episode still — the series-level Thumb when the episode has no
  /// Primary of its own, matching what Emby clients show in an episode list.
  ImageProvider? episodeImage(MediaItem episode) => _images.episode(episode);

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
        writeError: null,
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
      final similar = await _fetchSimilar();
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
          similar: similar,
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

  /// Re-reads the series, its seasons and 推荐 without dropping the visible
  /// page; the selected season stays selected when the server still has it.
  Future<void> refresh() async {
    if (_disposed || _state.loading || _state.unauthorized) return;
    _episodeRequest++;
    _set(_state.copyWith(loading: true, error: null, writeError: null));
    try {
      final series = await _library.item(_seriesId);
      if (_disposed || _state.unauthorized) return;
      if (series.type != 'Series') {
        _set(SeriesState(series: series, error: '这个条目不是剧集，请返回媒体库选择剧集'));
        return;
      }
      final seasons = _byIndex(await _library.seasons(_seriesId));
      if (_disposed || _state.unauthorized) return;
      final similar = await _fetchSimilar();
      if (_disposed || _state.unauthorized) return;
      final current = _state.selectedSeasonId;
      final MediaItem? first =
          seasons
              .where(
                (season) =>
                    season.indexNumber != null && season.indexNumber! > 0,
              )
              .firstOrNull ??
          seasons.firstOrNull;
      final String? seasonId = seasons.any((season) => season.id == current)
          ? current
          : first?.id;
      _set(
        _state.copyWith(
          series: series,
          seasons: seasons,
          selectedSeasonId: seasonId,
          similar: similar,
          loading: false,
          error: null,
        ),
      );
      if (seasonId != null) {
        await _loadEpisodes(seasonId, keepContent: seasonId == current);
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

  /// Optimistic favorite flip (S78): the icon reacts immediately and a failed
  /// write rolls the mark back with a non-fatal notice.
  Future<void> toggleFavorite() async {
    final item = _state.series;
    if (item == null || _state.favoriteBusy) return;
    final next = !item.userData.isFavorite;
    _set(
      _state.copyWith(
        series: item.copyWith(
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
          series: item,
          favoriteBusy: false,
          writeError: '收藏更新失败，请稍后重试',
        ),
      );
    }
  }

  /// Optimistic watched flip (S78), same rollback contract as favorite.
  Future<void> togglePlayed() async {
    final item = _state.series;
    if (item == null || _state.playedBusy) return;
    final next = !item.userData.played;
    _set(
      _state.copyWith(
        series: item.copyWith(userData: item.userData.copyWith(played: next)),
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
          series: item,
          playedBusy: false,
          writeError: '观看状态更新失败，请稍后重试',
        ),
      );
    }
  }

  /// Opens an external (IMDb/TMDb/TVDB) link from the 外部链接 row (S78).
  Future<void> openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      final opened = await _urlOpener(uri);
      if (_disposed) return;
      if (!opened) _set(_state.copyWith(writeError: '无法打开链接'));
    } catch (_) {
      if (_disposed) return;
      _set(_state.copyWith(writeError: '无法打开链接'));
    }
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

  /// 推荐 is decoration: a failing suggestion call must not fail the page and
  /// an expired session still has to reach the login redirect.
  Future<List<MediaItem>> _fetchSimilar() async {
    try {
      return await _library.similar(_seriesId);
    } on EmbyException catch (error) {
      if (error.code == AppErrorCode.unauthorized) rethrow;
      return _state.similar;
    } catch (_) {
      return _state.similar;
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

  static Future<bool> _launchUrl(Uri url) => launchUrl(url);
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
