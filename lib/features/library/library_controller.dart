import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../core/errors/app_error.dart';
import '../../core/errors/emby_exception.dart';
import '../../data/library/library_service.dart';
import '../../data/library/poster_cache.dart';
import '../../data/library/poster_image_provider.dart';
import '../../data/models/items_page.dart';
import '../../data/models/library_view.dart';
import '../../data/models/media_item.dart';

/// Library sub-tabs (P1 + S10): the selected view's grid, continue watching,
/// favorites, BoxSet collections, a Movie/Series type chooser and server tags.
enum LibraryTab { all, resume, favorites, collections, type, tag, upcoming }

/// Secondary chooser of the 类型 tab (S10), mapped to `IncludeItemTypes`.
/// Mirrors the favorites filter presets.
enum LibraryTypeFilter {
  all('全部', 'Movie,Series'),
  movies('电影', 'Movie'),
  series('剧集', 'Series');

  const LibraryTypeFilter(this.label, this.types);

  final String label;
  final String types;
}

/// Sort fields (P1) mapped to Emby `SortBy`. [defaultOrder] is the direction
/// picked when the field is first selected, mirroring the favorites presets.
enum LibrarySort {
  // S70: the full Yamby 排序 list (更新日期/最新上线/创建日期/公众评分/标题/
  // 首映日期/官方分级/出品年份/影评人评分/播放日期), in its own order.
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

  const LibrarySort(this.label, this.sortBy, this.defaultOrder);

  final String label;
  final String sortBy;
  final String defaultOrder;
}

/// Poster grid vs. compact list (P1). Kept in memory for the session.
enum LibraryViewMode { grid, list }

class LibraryState {
  const LibraryState({
    this.views = const <LibraryView>[],
    this.selectedView,
    this.tab = LibraryTab.all,
    // Yamby opens a library on 创建日期 ↓.
    this.sort = LibrarySort.dateAdded,
    this.sortDescending = true,
    this.viewMode = LibraryViewMode.grid,
    this.typeFilter = LibraryTypeFilter.all,
    this.selectedTag,
    this.genreFilter,
    this.yearFilter,
    this.studioFilterId,
    this.studioFilterName,
    this.genres = const <String>[],
    this.tags = const <String>[],
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

  final List<LibraryView> views;
  final LibraryView? selectedView;
  final LibraryTab tab;
  final LibrarySort sort;
  final bool sortDescending;
  final LibraryViewMode viewMode;

  /// 类型 tab chooser (S10); only queried while that tab is selected.
  final LibraryTypeFilter typeFilter;

  /// 标签 tab selection (S10); null lists the view unfiltered.
  final String? selectedTag;

  /// 全部 tab 筛选 (S10); null means the facet is not filtered.
  final String? genreFilter;
  final int? yearFilter;

  /// S60: studio deep link (详情页工作室) — id for the query, name for the chip.
  final String? studioFilterId;
  final String? studioFilterName;

  /// Facet chip sources (S10): genre names for the 筛选 dialog, tag names for
  /// the 标签 tab. Loaded lazily and cached for the session.
  final List<String> genres;
  final List<String> tags;
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

  /// True while the 全部 筛选 narrows the grid (S10).
  bool get hasFilters =>
      genreFilter != null ||
      yearFilter != null ||
      studioFilterId != null ||
      studioFilterName != null;

  static const Object _unset = Object();

  LibraryState copyWith({
    List<LibraryView>? views,
    Object? selectedView = _unset,
    LibraryTab? tab,
    LibrarySort? sort,
    bool? sortDescending,
    LibraryViewMode? viewMode,
    LibraryTypeFilter? typeFilter,
    Object? selectedTag = _unset,
    Object? genreFilter = _unset,
    Object? yearFilter = _unset,
    Object? studioFilterId = _unset,
    Object? studioFilterName = _unset,
    List<String>? genres,
    List<String>? tags,
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
    return LibraryState(
      views: views ?? this.views,
      selectedView: identical(selectedView, _unset)
          ? this.selectedView
          : selectedView as LibraryView?,
      tab: tab ?? this.tab,
      sort: sort ?? this.sort,
      sortDescending: sortDescending ?? this.sortDescending,
      viewMode: viewMode ?? this.viewMode,
      typeFilter: typeFilter ?? this.typeFilter,
      selectedTag: identical(selectedTag, _unset)
          ? this.selectedTag
          : selectedTag as String?,
      genreFilter: identical(genreFilter, _unset)
          ? this.genreFilter
          : genreFilter as String?,
      yearFilter: identical(yearFilter, _unset)
          ? this.yearFilter
          : yearFilter as int?,
      studioFilterId: identical(studioFilterId, _unset)
          ? this.studioFilterId
          : studioFilterId as String?,
      studioFilterName: identical(studioFilterName, _unset)
          ? this.studioFilterName
          : studioFilterName as String?,
      genres: genres ?? this.genres,
      tags: tags ?? this.tags,
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

/// Drives the library page: views, sub-tabs, sort, first page and infinite
/// scroll (contract §2, P1 enhancements).
///
/// A generation counter discards answers that arrive after the view, tab or
/// sort changed, so a slow page can never overwrite a newer one.
class LibraryController extends ChangeNotifier {
  LibraryController(
    this._service,
    this._posters, {
    Random? random,
    this.preferredViewId,
    this.preferredGenre,
    this.preferredStudioId,
    this.preferredStudioName,
    Set<String>? hiddenViewIds,
  }) : _random = random ?? Random(),
       _hiddenViewIds = hiddenViewIds ?? const <String>{},
       _state = LibraryState(
         genreFilter: preferredGenre,
         studioFilterId: preferredStudioId,
         studioFilterName: preferredStudioName,
       );

  final LibraryService _service;

  final PosterCache _posters;

  final Random _random;

  /// Library requested by a home 媒体库 / 更多 card (S28); used for the first
  /// page only, so switching away afterwards is not dragged back.
  final String? preferredViewId;

  /// Genre requested by a detail page chip (S46); seeds the 全部 tab filter
  /// so the page opens already narrowed.
  final String? preferredGenre;

  /// S60: studio id/name from a detail page 工作室 link.
  final String? preferredStudioId;
  final String? preferredStudioName;

  /// Libraries hidden in 设置 → 通用 → 媒体库 (S32). Filtered out of the view
  /// chips; hiding every library leaves the full list so browsing never dead-ends.
  final Set<String> _hiddenViewIds;

  LibraryState _state;

  /// S69: Yamby remembers the sort per library (动画电影 on 创建日期, 儿童动画 on
  /// 更新日期). Keys are view ids; the value keeps field plus direction.
  final Map<String, (LibrarySort, bool)> _sortByView =
      <String, (LibrarySort, bool)>{};
  bool _disposed = false;
  bool _bootstrapLoading = false;
  int _seq = 0;

  LibraryState get state => _state;

  String get _sortOrder => _state.sortDescending ? 'Descending' : 'Ascending';

  /// Loads views and the first page of the current tab.
  Future<void> load({bool refresh = false}) async {
    if (_state.loading) return;

    _bootstrapLoading = true;
    final int seq = ++_seq;
    _set(_state.copyWith(loading: true, error: null, unauthorized: false));
    try {
      final allViews = await _service.views();
      final visibleViews = allViews
          .where((view) => !_hiddenViewIds.contains(view.id))
          .toList(growable: false);
      final views = visibleViews.isEmpty ? allViews : visibleViews;
      if (_disposed || seq != _seq) return;
      if (views.isEmpty) {
        _set(
          _state.copyWith(
            views: const <LibraryView>[],
            selectedView: null,
            items: const <MediaItem>[],
            total: 0,
            loading: false,
            loaded: true,
          ),
        );
        return;
      }

      final String? wantedId = refresh
          ? _state.selectedView?.id
          : (_state.selectedView?.id ?? preferredViewId);
      final selected = views.firstWhere(
        (view) => view.id == wantedId,
        orElse: () => views.first,
      );
      final page = await _firstPage(selected);
      if (_disposed || seq != _seq) return;

      _set(
        _state.copyWith(
          views: views,
          selectedView: selected,
          items: page.items,
          total: _totalFor(page),
          loading: false,
          loaded: true,
        ),
      );
      if (_state.tab == LibraryTab.tag) {
        unawaited(loadTags(refresh: refresh));
      }
    } on EmbyException catch (error) {
      if (_disposed || seq != _seq) return;
      _fail(error);
    } catch (_) {
      if (_disposed || seq != _seq) return;
      _set(_state.copyWith(loading: false, loaded: true, error: '加载失败，请稍后重试'));
    } finally {
      _bootstrapLoading = false;
    }
  }

  /// Remembers the current sort for the selected view (S69).
  void _rememberSort() {
    final String? id = _state.selectedView?.id;
    if (id == null) return;
    _sortByView[id] = (_state.sort, _state.sortDescending);
  }

  /// Restores a view's remembered sort, defaulting to 创建日期 ↓.
  void _restoreSort(String viewId) {
    final (LibrarySort, bool) saved =
        _sortByView[viewId] ?? (LibrarySort.dateAdded, true);
    _set(_state.copyWith(sort: saved.$1, sortDescending: saved.$2));
  }

  Future<void> selectView(LibraryView view) async {
    if (_state.loading) return;
    if (_state.tab == LibraryTab.all && _state.selectedView?.id == view.id) {
      return;
    }

    final int seq = ++_seq;
    // S69: keep the outgoing view's sort, then restore the target's.
    _rememberSort();
    _restoreSort(view.id);
    _set(
      _state.copyWith(
        tab: LibraryTab.all,
        selectedView: view,
        items: const <MediaItem>[],
        total: 0,
        loading: true,
        error: null,
        unauthorized: false,
      ),
    );

    try {
      final page = await _firstPage(view);
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

  /// Switches the 全部 / 继续 / 收藏 / 合集 / 类型 / 标签 sub-tab and reloads
  /// the grid from that tab's source. Interruptible: the generation counter
  /// discards the answer of a tab the user already left.
  void selectTab(LibraryTab tab) {
    if (tab == _state.tab) return;
    _set(_state.copyWith(tab: tab));
    if (tab == LibraryTab.tag) unawaited(loadTags());
    unawaited(_reloadFirstPage());
  }

  /// 类型 tab chooser (S10): re-queries with `IncludeItemTypes` only while
  /// that tab is selected.
  void setTypeFilter(LibraryTypeFilter filter) {
    if (filter == _state.typeFilter) return;
    _set(_state.copyWith(typeFilter: filter));
    if (_state.tab == LibraryTab.type) {
      unawaited(_reloadFirstPage());
    }
  }

  /// 标签 tab selection (S10); null clears the tag and lists the view
  /// unfiltered.
  void selectTag(String? tag) {
    if (tag == _state.selectedTag) return;
    _set(_state.copyWith(selectedTag: tag));
    if (_state.tab == LibraryTab.tag) {
      unawaited(_reloadFirstPage());
    }
  }

  /// 全部 筛选 (S10): applies genre and year in one reload. Null clears the
  /// facet; the filters only re-query while the 全部 tab is selected.
  /// S60: removes the studio deep-link filter (chip's ×).
  void clearStudioFilter() {
    if (_state.studioFilterId == null && _state.studioFilterName == null) {
      return;
    }
    _set(_state.copyWith(studioFilterId: null, studioFilterName: null));
    unawaited(_reloadFirstPage());
  }

  void applyFilters(String? genre, int? year) {
    if (genre == _state.genreFilter && year == _state.yearFilter) return;
    _set(_state.copyWith(genreFilter: genre, yearFilter: year));
    if (_state.tab == LibraryTab.all) {
      unawaited(_reloadFirstPage());
    }
  }

  void setGenreFilter(String? genre) => applyFilters(genre, _state.yearFilter);

  void setYearFilter(int? year) => applyFilters(_state.genreFilter, year);

  /// Genre names for the 筛选 dialog (S10). Cached after the first success;
  /// [refresh] forces a re-query. Facets are global, so they survive view and
  /// tab switches and are only discarded on dispose.
  Future<void> loadGenres({bool refresh = false}) async {
    if (_state.facetsLoading) return;
    if (_state.genres.isNotEmpty && !refresh) return;
    _set(_state.copyWith(facetsLoading: true, facetsError: null));
    try {
      final names = await _service.genres();
      if (_disposed) return;
      _set(_state.copyWith(genres: names, facetsLoading: false));
    } on EmbyException catch (error) {
      if (_disposed) return;
      _failFacets(error);
    } catch (_) {
      if (_disposed) return;
      _set(_state.copyWith(facetsLoading: false, facetsError: '加载失败，请稍后重试'));
    }
  }

  /// Tag names for the 标签 tab (S10); same caching rules as [loadGenres].
  Future<void> loadTags({bool refresh = false}) async {
    if (_state.facetsLoading) return;
    if (_state.tags.isNotEmpty && !refresh) return;
    _set(_state.copyWith(facetsLoading: true, facetsError: null));
    try {
      final names = await _service.tags();
      if (_disposed) return;
      _set(_state.copyWith(tags: names, facetsLoading: false));
    } on EmbyException catch (error) {
      if (_disposed) return;
      _failFacets(error);
    } catch (_) {
      if (_disposed) return;
      _set(_state.copyWith(facetsLoading: false, facetsError: '加载失败，请稍后重试'));
    }
  }

  /// Applies a sort field and direction. Continue-watching keeps the server's
  /// most-recently-played order, so the sort re-queries every other tab.
  void setSort(LibrarySort sort, {bool? descending}) {
    final bool nextDescending =
        descending ??
        (sort == _state.sort
            ? _state.sortDescending
            : sort.defaultOrder == 'Descending');
    if (sort == _state.sort && nextDescending == _state.sortDescending) return;
    _set(_state.copyWith(sort: sort, sortDescending: nextDescending));
    if (_state.tab != LibraryTab.resume) {
      unawaited(_reloadFirstPage());
    }
  }

  /// Grid ↔ list; a pure presentation switch, no request.
  void toggleViewMode() {
    _set(
      _state.copyWith(
        viewMode: _state.viewMode == LibraryViewMode.grid
            ? LibraryViewMode.list
            : LibraryViewMode.grid,
      ),
    );
  }

  /// A random item from the currently loaded page for the shuffle action
  /// (P1); null when nothing usable is loaded. Picking locally keeps the
  /// action instant and works the same on every tab.
  MediaItem? randomItem() {
    final candidates = _state.items
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
    if (candidates.isEmpty) return null;
    return candidates[_random.nextInt(candidates.length)];
  }

  Future<void> loadMore() async {
    final tab = _state.tab;
    final view = _state.selectedView;
    // Continue-watching is a bounded server row without a start-index cursor.
    if (tab == LibraryTab.resume) return;
    if (_needsView && view == null) return;
    if (_state.loading || _state.loadingMore || !_state.hasMore) return;

    final int seq = _seq;
    _set(_state.copyWith(loadingMore: true, error: null));
    try {
      final page = await _firstPage(view, startIndex: _state.items.length);
      // The user may have switched views, tabs or sort while the page was in
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
      _fail(error);
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

  /// The view-scoped tabs (全部 / 类型 / 标签) need a selected library; the
  /// global rows (继续 / 收藏 / 合集) do not.
  bool get _needsView =>
      _state.tab == LibraryTab.all ||
      _state.tab == LibraryTab.type ||
      _state.tab == LibraryTab.tag;

  /// One page of the current tab, carrying its sort and S10 filters.
  /// [view] is only read by the view-scoped tabs.

  /// S45: 即将上映 — items whose `PremiereDate` is in the future. The server
  /// has no future-date filter, so the page is fetched newest-first and
  /// reduced here; the tab's total is the filtered count.
  Future<ItemsPage> _upcomingPage(LibraryView view) async {
    final ItemsPage page = await _service.items(
      view.id,
      sortBy: 'PremiereDate',
      sortOrder: 'Descending',
      includeItemTypes: 'Movie,Series',
      studioId: _state.studioFilterId,
      studio: _state.studioFilterName,
    );
    final DateTime now = DateTime.now();
    final List<MediaItem> future = page.items
        .where((MediaItem item) {
          final DateTime? at = item.premiereAt;
          return at != null && at.isAfter(now);
        })
        .toList(growable: false);
    future.sort(
      (MediaItem a, MediaItem b) => a.premiereAt!.compareTo(b.premiereAt!),
    );
    return ItemsPage(
      items: future,
      totalRecordCount: future.length,
      startIndex: 0,
    );
  }

  Future<ItemsPage> _firstPage(LibraryView? view, {int startIndex = 0}) {
    return switch (_state.tab) {
      LibraryTab.all => _service.items(
        view!.id,
        startIndex: startIndex,
        sortBy: _state.sort.sortBy,
        sortOrder: _sortOrder,
        genre: _state.genreFilter,
        year: _state.yearFilter,
        studioId: _state.studioFilterId,
        studio: _state.studioFilterName,
      ),
      LibraryTab.resume => _service.resumable(limit: 60),
      LibraryTab.favorites => _service.favorites(
        startIndex: startIndex,
        sortBy: _state.sort.sortBy,
        sortOrder: _sortOrder,
      ),
      LibraryTab.collections => _service.collections(
        startIndex: startIndex,
        sortBy: _state.sort.sortBy,
        sortOrder: _sortOrder,
      ),
      LibraryTab.type => _service.items(
        view!.id,
        startIndex: startIndex,
        sortBy: _state.sort.sortBy,
        sortOrder: _sortOrder,
        includeItemTypes: _state.typeFilter.types,
        studioId: _state.studioFilterId,
        studio: _state.studioFilterName,
      ),
      LibraryTab.tag => _service.items(
        view!.id,
        startIndex: startIndex,
        sortBy: _state.sort.sortBy,
        sortOrder: _sortOrder,
        tag: _state.selectedTag,
        studioId: _state.studioFilterId,
        studio: _state.studioFilterName,
      ),
      // S45: newest premieres first, then filtered client side to the future
      // (Emby has no "future premiere" filter), and shown soonest first.
      LibraryTab.upcoming => _upcomingPage(view!),
    };
  }

  /// The resumable row has no paging cursor, so its loaded count is the total.
  int _totalFor(ItemsPage page) => _state.tab == LibraryTab.resume
      ? page.items.length
      : page.totalRecordCount;

  Future<void> _reloadFirstPage() async {
    // The bootstrap load owns the first page; it reads the current tab/sort
    // when it fetches, so an early switch is picked up there instead.
    if (_bootstrapLoading) return;
    final view = _state.selectedView;
    if (_needsView && view == null) return;

    final int seq = ++_seq;
    _set(
      _state.copyWith(
        items: const <MediaItem>[],
        total: 0,
        loading: true,
        error: null,
        unauthorized: false,
      ),
    );
    try {
      final page = await _firstPage(view);
      if (_disposed || seq != _seq) return;
      _set(
        _state.copyWith(
          items: page.items,
          total: _totalFor(page),
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

  /// A facet failure never clears the grid; it only marks the chip source as
  /// failed (S10). An expired session still redirects through [unauthorized].
  void _failFacets(EmbyException error) {
    _set(
      _state.copyWith(
        facetsLoading: false,
        facetsError: error.code == AppErrorCode.unauthorized
            ? null
            : libraryErrorMessage(error.code),
        unauthorized: error.code == AppErrorCode.unauthorized,
      ),
    );
  }

  void _fail(EmbyException error, {bool keepItems = true}) {
    _set(
      _state.copyWith(
        loading: false,
        loadingMore: false,
        loaded: true,
        items: keepItems ? _state.items : const <MediaItem>[],
        error: error.code == AppErrorCode.unauthorized
            ? null
            : libraryErrorMessage(error.code),
        unauthorized: error.code == AppErrorCode.unauthorized,
      ),
    );
  }

  void _set(LibraryState state) {
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

String libraryErrorMessage(AppErrorCode code) {
  return switch (code) {
    AppErrorCode.unauthorized => '登录已过期，请重新登录',
    AppErrorCode.forbidden => '没有访问该媒体库的权限',
    AppErrorCode.networkUnreachable => '无法连接服务器，请检查网络',
    AppErrorCode.tlsUntrusted => '服务器证书不受信任',
    AppErrorCode.notFound => '内容不存在或已被移除',
    _ => '加载失败，请稍后重试',
  };
}
