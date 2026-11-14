// Public named parameters (`store`, `debounce`) with private fields, the
// same trade-off as PlayerController's constructor.
// ignore_for_file: prefer_initializing_formals
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../core/errors/app_error.dart';
import '../../core/errors/emby_exception.dart';
import '../../data/library/library_service.dart';
import '../../data/library/poster_cache.dart';
import '../../data/library/poster_image_provider.dart';
import '../../data/models/media_item.dart';
import '../../data/storage/key_value_store.dart';

enum SearchFilter { all, movies, series, collections, persons }

class SearchState {
  const SearchState({
    this.query = '',
    this.filters = const <SearchFilter>{SearchFilter.all},
    this.results = const <MediaItem>[],
    this.loading = false,
    this.loaded = false,
    this.error,
    this.unauthorized = false,
    this.history = const <String>[],
  });

  final String query;

  /// S50: Yamby's search types are checkboxes — several can be on at once.
  /// [SearchFilter.all] is the empty/default state and never coexists with
  /// the concrete types.
  final Set<SearchFilter> filters;
  final List<MediaItem> results;
  final bool loading;

  /// A search finished (successfully or not); distinguishes "no results yet"
  /// from "nothing matched".
  final bool loaded;
  final String? error;
  final bool unauthorized;
  final List<String> history;

  static const Object _unset = Object();

  SearchState copyWith({
    String? query,
    Set<SearchFilter>? filters,
    List<MediaItem>? results,
    bool? loading,
    bool? loaded,
    Object? error = _unset,
    bool? unauthorized,
    List<String>? history,
  }) {
    return SearchState(
      query: query ?? this.query,
      filters: filters ?? this.filters,
      results: results ?? this.results,
      loading: loading ?? this.loading,
      loaded: loaded ?? this.loaded,
      error: identical(error, _unset) ? this.error : error as String?,
      unauthorized: unauthorized ?? this.unauthorized,
      history: history ?? this.history,
    );
  }
}

/// Debounced library search (S6): one request per settled query, stale
/// answers discarded, recent terms persisted for the empty-query view.
class LibrarySearchController extends ChangeNotifier {
  LibrarySearchController(
    this._library,
    this._posters, {
    KeyValueStore? store,
    Duration debounce = const Duration(milliseconds: 300),
  }) : _store = store,
       _debounce = debounce;

  static const String historyKey = 'search.history.v1';
  static const int maxHistory = 8;

  final LibraryService _library;
  final PosterCache _posters;
  final KeyValueStore? _store;
  final Duration _debounce;

  SearchState _state = const SearchState();
  Timer? _debounceTimer;
  int _seq = 0;
  bool _disposed = false;

  SearchState get state => _state;

  ImageProvider? posterImage(String itemId, {String? tag, int? maxWidth}) {
    final url = _library.imageUrl(itemId, tag: tag, maxWidth: maxWidth);
    if (url == null) return null;
    return PosterImageProvider(
      cache: _posters,
      itemId: itemId,
      url: url,
      tag: tag,
      maxWidth: maxWidth,
    );
  }

  Future<void> loadHistory() async {
    final store = _store;
    if (store == null) return;
    final raw = await store.read(historyKey);
    if (_disposed || raw == null) return;
    final List<String> terms;
    try {
      terms = (jsonDecode(raw) as List<dynamic>)
          .whereType<String>()
          .take(maxHistory)
          .toList(growable: false);
    } catch (_) {
      return;
    }
    _set(_state.copyWith(history: terms));
  }

  void setQuery(String query) {
    _debounceTimer?.cancel();
    _set(_state.copyWith(query: query));
    if (query.trim().isEmpty) {
      _seq++;
      _set(
        _state.copyWith(
          results: const <MediaItem>[],
          loading: false,
          loaded: false,
          error: null,
        ),
      );
      return;
    }
    _debounceTimer = Timer(_debounce, () => unawaited(_run()));
  }

  /// Enter key / history tap: skip the remaining debounce.
  void submit() {
    _debounceTimer?.cancel();
    if (_state.query.trim().isNotEmpty) unawaited(_run());
  }

  /// Toggles one type. 全部 clears every concrete type; removing the last
  /// concrete type falls back to 全部.
  void toggleFilter(SearchFilter filter) {
    final Set<SearchFilter> next;
    if (filter == SearchFilter.all) {
      next = <SearchFilter>{SearchFilter.all};
    } else {
      final Set<SearchFilter> current = <SearchFilter>{..._state.filters}
        ..remove(SearchFilter.all);
      if (!current.remove(filter)) current.add(filter);
      next = current.isEmpty ? <SearchFilter>{SearchFilter.all} : current;
    }
    if (setEquals(next, _state.filters)) return;
    _set(_state.copyWith(filters: next));
    if (_state.query.trim().isNotEmpty) {
      _debounceTimer?.cancel();
      unawaited(_run());
    }
  }

  Future<void> _run() async {
    final int seq = ++_seq;
    final String query = _state.query.trim();
    _set(_state.copyWith(loading: true, error: null));
    try {
      final Set<SearchFilter> filters = _state.filters;
      const Map<SearchFilter, String> typeNames = <SearchFilter, String>{
        SearchFilter.movies: 'Movie',
        SearchFilter.series: 'Series',
        SearchFilter.collections: 'BoxSet',
        SearchFilter.persons: 'Person',
      };
      final bool all = filters.isEmpty || filters.contains(SearchFilter.all);
      final String types = all
          ? 'Movie,Series,BoxSet,Person'
          : filters
                .map((SearchFilter f) => typeNames[f])
                .whereType<String>()
                .join(',');
      final page = await _library.search(query, types: types);
      if (_disposed || seq != _seq) return;
      _set(_state.copyWith(results: page.items, loading: false, loaded: true));
      unawaited(_remember(query));
    } catch (error) {
      if (_disposed || seq != _seq) return;
      final bool unauthorized =
          error is EmbyException && error.code == AppErrorCode.unauthorized;
      _set(
        _state.copyWith(
          loading: false,
          loaded: true,
          error: unauthorized ? null : searchErrorMessage(error),
          unauthorized: unauthorized,
        ),
      );
    }
  }

  Future<void> _remember(String term) async {
    final List<String> history = <String>[
      term,
      ..._state.history.where((String t) => t != term),
    ].take(maxHistory).toList(growable: false);
    _set(_state.copyWith(history: history));
    final store = _store;
    if (store == null) return;
    await store.write(historyKey, jsonEncode(history));
  }

  /// S52: drop one remembered term (history tile's ×).
  Future<void> removeHistory(String term) async {
    final List<String> history = _state.history
        .where((String t) => t != term)
        .toList(growable: false);
    if (history.length == _state.history.length) return;
    _set(_state.copyWith(history: history));
    final store = _store;
    if (store == null) return;
    await store.write(historyKey, jsonEncode(history));
  }

  /// S52: 清除全部 — empties the remembered list and the stored blob.
  Future<void> clearHistory() async {
    if (_state.history.isEmpty) return;
    _set(_state.copyWith(history: const <String>[]));
    final store = _store;
    if (store == null) return;
    await store.write(historyKey, jsonEncode(const <String>[]));
  }

  void _set(SearchState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    super.dispose();
  }
}

/// Maps a data-layer failure to search copy (contract §6).
String searchErrorMessage(Object error) {
  final code = error is EmbyException ? error.code : null;
  return switch (code) {
    AppErrorCode.unauthorized => '登录已过期，请重新登录',
    AppErrorCode.networkUnreachable => '无法连接服务器，请检查网络',
    AppErrorCode.tlsUntrusted => '服务器证书不受信任',
    _ => '搜索失败，请稍后重试',
  };
}
