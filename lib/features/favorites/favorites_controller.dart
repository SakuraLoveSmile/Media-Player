import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../core/errors/app_error.dart';
import '../../core/errors/emby_exception.dart';
import '../../data/library/library_service.dart';
import '../../data/library/poster_cache.dart';
import '../../data/library/poster_image_provider.dart';
import '../../data/models/media_item.dart';

/// Type tabs of the favorites page (S8), mapped to `IncludeItemTypes`.
enum FavoritesFilter { all, movies, series, collections, persons }

/// Grid vs. compact list (S35, Yamby's favorites toolbar).
enum FavoritesViewMode { grid, list }

/// Sort presets (S8): each maps to an Emby `SortBy` + `SortOrder` pair.
enum FavoritesSort {
  // S70: mirror the library list (Yamby's 排序 fields), so both pages offer
  // the same vocabulary.
  dateModified('更新日期', 'DateLastSaved', 'Descending'),
  latest('最新上线', 'DateLastContentAdded', 'Descending'),
  dateAdded('创建日期', 'DateCreated', 'Descending'),
  rating('公众评分', 'CommunityRating', 'Descending'),
  name('标题', 'SortName', 'Ascending'),
  premiereDate('首映日期', 'PremiereDate', 'Descending'),
  officialRating('官方分级', 'OfficialRating', 'Ascending'),
  year('出品年份', 'ProductionYear', 'Descending'),
  criticRating('影评人评分', 'CriticRating', 'Descending'),
  datePlayed('播放日期', 'DatePlayed', 'Descending');

  const FavoritesSort(this.label, this.sortBy, this.sortOrder);

  final String label;
  final String sortBy;
  final String sortOrder;
}

class FavoritesState {
  const FavoritesState({
    this.filter = FavoritesFilter.all,
    this.sort = FavoritesSort.dateAdded,
    this.sortDescending = true,
    this.viewMode = FavoritesViewMode.grid,
    this.genreFilter,
    this.yearFilter,
    this.genres = const <String>[],
    this.facetsLoading = false,
    this.facetsError,
    this.items = const <MediaItem>[],
    this.total = 0,
    this.loading = false,
    this.loadingMore = false,
    this.loaded = false,
    this.error,
    this.unauthorized = false,
  });

  final FavoritesFilter filter;
  final FavoritesSort sort;

  /// Sort direction for [sort] (S35: the toolbar shows the current one).
  final bool sortDescending;
  final FavoritesViewMode viewMode;

  /// 筛选 (S39): null means the facet is not filtered. [genres] is the chip
  /// source, loaded lazily from `GET /Genres`.
  final String? genreFilter;
  final int? yearFilter;
  final List<String> genres;
  final bool facetsLoading;
  final String? facetsError;
  final List<MediaItem> items;
  final int total;
  final bool loading;
  final bool loadingMore;

  /// True once at least one load attempt finished, so the empty state is not
  /// shown while the first page is still in flight.
  final bool loaded;
  final String? error;
  final bool unauthorized;

  bool get hasMore => items.length < total;

  static const Object _unset = Object();

  FavoritesState copyWith({
    FavoritesFilter? filter,
    FavoritesSort? sort,
    bool? sortDescending,
    FavoritesViewMode? viewMode,
    Object? genreFilter = _unset,
    Object? yearFilter = _unset,
    List<String>? genres,
    bool? facetsLoading,
    Object? facetsError = _unset,
    List<MediaItem>? items,
    int? total,
    bool? loading,
    bool? loadingMore,
    bool? loaded,
    Object? error = _unset,
    bool? unauthorized,
  }) {
    return FavoritesState(
      filter: filter ?? this.filter,
      sort: sort ?? this.sort,
      sortDescending: sortDescending ?? this.sortDescending,
      viewMode: viewMode ?? this.viewMode,
      genreFilter: identical(genreFilter, _unset)
          ? this.genreFilter
          : genreFilter as String?,
      yearFilter: identical(yearFilter, _unset)
          ? this.yearFilter
          : yearFilter as int?,
      genres: genres ?? this.genres,
      facetsLoading: facetsLoading ?? this.facetsLoading,
      facetsError: identical(facetsError, _unset)
          ? this.facetsError
          : facetsError as String?,
      items: items ?? this.items,
      total: total ?? this.total,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      loaded: loaded ?? this.loaded,
      error: identical(error, _unset) ? this.error : error as String?,
      unauthorized: unauthorized ?? this.unauthorized,
    );
  }
}

/// Drives the favorites page (S8): type tabs, sort presets, infinite scroll.
///
/// A generation counter discards answers that arrive after the filter or sort
/// changed, so a slow page can never overwrite a newer one.
class FavoritesController extends ChangeNotifier {
  FavoritesController(this._service, this._posters, {Random? random})
    : _random = random ?? Random();

  final Random _random;

  final LibraryService _service;
  final PosterCache _posters;

  FavoritesState _state = const FavoritesState();
  bool _disposed = false;
  int _seq = 0;

  FavoritesState get state => _state;

  /// S71: shuffle action — a random favorite from the loaded page.
  MediaItem? randomItem() {
    final List<MediaItem> candidates = _state.items
        .where((MediaItem item) => item.id.isNotEmpty)
        .toList(growable: false);
    if (candidates.isEmpty) return null;
    return candidates[_random.nextInt(candidates.length)];
  }

  String get _types => switch (_state.filter) {
    FavoritesFilter.all => 'Movie,Series,BoxSet,Person',
    FavoritesFilter.movies => 'Movie',
    FavoritesFilter.series => 'Series',
    FavoritesFilter.collections => 'BoxSet',
    FavoritesFilter.persons => 'Person',
  };

  /// Loads the first page for the current filter and sort.
  Future<void> load() async {
    final int seq = ++_seq;
    _set(
      _state.copyWith(
        loading: true,
        loadingMore: false,
        error: null,
        unauthorized: false,
        items: const <MediaItem>[],
        total: 0,
      ),
    );
    try {
      final page = await _service.favorites(
        types: _types,
        sortBy: _state.sort.sortBy,
        sortOrder: _state.sortDescending ? 'Descending' : 'Ascending',
        genre: _state.genreFilter,
        year: _state.yearFilter,
      );
      if (_disposed || seq != _seq) return;
      _set(
        _state.copyWith(
          items: page.items,
          total: page.totalRecordCount,
          loading: false,
          loaded: true,
        ),
      );
    } on EmbyException catch (error) {
      if (_disposed || seq != _seq) return;
      _fail(error);
    } catch (_) {
      if (_disposed || seq != _seq) return;
      _set(_state.copyWith(loading: false, loaded: true, error: '加载失败，请稍后重试'));
    }
  }

  void setFilter(FavoritesFilter filter) {
    if (filter == _state.filter) return;
    _set(_state.copyWith(filter: filter));
    unawaited(load());
  }

  void setSort(FavoritesSort sort, {bool? descending}) {
    // Choosing a field applies its natural direction; the dialog's 升序/降序
    // buttons pass the explicit direction.
    final bool nextDescending = descending ?? sort.sortOrder == 'Descending';
    if (sort == _state.sort && nextDescending == _state.sortDescending) {
      return;
    }
    _set(_state.copyWith(sort: sort, sortDescending: nextDescending));
    unawaited(load());
  }

  /// 筛选 (S39): genre and year apply to the favorites query; null clears the
  /// facet and re-queries the first page.
  void applyFilters(String? genre, int? year) {
    if (genre == _state.genreFilter && year == _state.yearFilter) return;
    _set(_state.copyWith(genreFilter: genre, yearFilter: year));
    unawaited(load());
  }

  void setGenreFilter(String? genre) => applyFilters(genre, _state.yearFilter);

  void setYearFilter(int? year) => applyFilters(_state.genreFilter, year);

  /// Genre chip source; cached after the first success.
  Future<void> loadGenres({bool refresh = false}) async {
    if (_state.facetsLoading) return;
    if (_state.genres.isNotEmpty && !refresh) return;
    _set(_state.copyWith(facetsLoading: true, facetsError: null));
    try {
      final names = await _service.genres();
      if (_disposed) return;
      _set(_state.copyWith(genres: names, facetsLoading: false));
    } catch (_) {
      if (_disposed) return;
      _set(_state.copyWith(facetsLoading: false, facetsError: '加载失败，请稍后重试'));
    }
  }

  /// Grid ↔ list, a pure presentation switch (S35).
  void toggleViewMode() {
    _set(
      _state.copyWith(
        viewMode: _state.viewMode == FavoritesViewMode.grid
            ? FavoritesViewMode.list
            : FavoritesViewMode.grid,
      ),
    );
  }

  Future<void> loadMore() async {
    if (_state.loading || _state.loadingMore || !_state.hasMore) return;
    final int seq = _seq;
    _set(_state.copyWith(loadingMore: true, error: null));
    try {
      final page = await _service.favorites(
        types: _types,
        startIndex: _state.items.length,
        sortBy: _state.sort.sortBy,
        sortOrder: _state.sortDescending ? 'Descending' : 'Ascending',
        genre: _state.genreFilter,
        year: _state.yearFilter,
      );
      // The user may have changed the filter or sort while the page was in
      // flight; a new generation means this answer is stale.
      if (_disposed || seq != _seq) return;
      _set(
        _state.copyWith(
          items: <MediaItem>[..._state.items, ...page.items],
          total: page.totalRecordCount,
          loadingMore: false,
        ),
      );
    } on EmbyException catch (error) {
      if (_disposed || seq != _seq) return;
      _fail(error, keepItems: true);
    } catch (_) {
      if (_disposed || seq != _seq) return;
      _set(_state.copyWith(loadingMore: false, error: '加载更多失败，请上滑重试'));
    }
  }

  /// Null without a session, which is the card's cue to show its placeholder.
  ImageProvider? posterImage(String itemId, {String? tag, int? maxWidth}) {
    final url = _service.imageUrl(itemId, tag: tag, maxWidth: maxWidth);
    if (url == null) return null;
    return PosterImageProvider(
      cache: _posters,
      itemId: itemId,
      url: url,
      tag: tag,
      maxWidth: maxWidth,
    );
  }

  void _fail(EmbyException error, {bool keepItems = false}) {
    _set(
      _state.copyWith(
        loading: false,
        loadingMore: false,
        loaded: true,
        items: keepItems ? _state.items : const <MediaItem>[],
        error: error.code == AppErrorCode.unauthorized
            ? null
            : favoritesErrorMessage(error.code),
        unauthorized: error.code == AppErrorCode.unauthorized,
      ),
    );
  }

  void _set(FavoritesState state) {
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

/// Maps a data-layer failure to favorites copy (contract §6).
String favoritesErrorMessage(AppErrorCode code) {
  return switch (code) {
    AppErrorCode.unauthorized => '登录已过期，请重新登录',
    AppErrorCode.forbidden => '没有访问收藏的权限',
    AppErrorCode.networkUnreachable => '无法连接服务器，请检查网络',
    AppErrorCode.tlsUntrusted => '服务器证书不受信任',
    AppErrorCode.notFound => '内容不存在或已被移除',
    _ => '加载失败，请稍后重试',
  };
}
