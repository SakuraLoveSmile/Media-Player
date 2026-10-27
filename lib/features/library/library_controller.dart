import 'package:flutter/foundation.dart';

import '../../core/errors/app_error.dart';
import '../../core/errors/emby_exception.dart';
import '../../data/library/library_service.dart';
import '../../data/models/library_view.dart';
import '../../data/models/media_item.dart';

class LibraryState {
  const LibraryState({
    this.views = const <LibraryView>[],
    this.selectedView,
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

  LibraryState copyWith({
    List<LibraryView>? views,
    Object? selectedView = _unset,
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

/// Drives the library page: views, first page, infinite scroll (contract §2).
class LibraryController extends ChangeNotifier {
  LibraryController(this._service);

  final LibraryService _service;

  LibraryState _state = const LibraryState();
  bool _disposed = false;

  LibraryState get state => _state;

  /// Loads views and the first page of the selected (or first) view.
  Future<void> load({bool refresh = false}) async {
    if (_state.loading) return;

    _set(_state.copyWith(loading: true, error: null, unauthorized: false));
    try {
      final views = await _service.views();
      if (views.isEmpty) {
        _set(const LibraryState(loaded: true));
        return;
      }

      final previousId = refresh ? _state.selectedView?.id : null;
      final selected = views.firstWhere(
        (view) => view.id == previousId,
        orElse: () => views.first,
      );
      final page = await _service.items(selected.id);

      _set(LibraryState(
        views: views,
        selectedView: selected,
        items: page.items,
        total: page.totalRecordCount,
        loaded: true,
      ));
    } on EmbyException catch (error) {
      _fail(error);
    } catch (_) {
      _set(_state.copyWith(
        loading: false,
        loaded: true,
        error: '加载失败，请稍后重试',
      ));
    }
  }

  Future<void> selectView(LibraryView view) async {
    if (_state.selectedView?.id == view.id || _state.loading) return;

    _set(_state.copyWith(
      selectedView: view,
      items: const <MediaItem>[],
      total: 0,
      loading: true,
      error: null,
      unauthorized: false,
    ));

    try {
      final page = await _service.items(view.id);
      if (_state.selectedView?.id != view.id) return;
      _set(_state.copyWith(
        items: page.items,
        total: page.totalRecordCount,
        loading: false,
        loaded: true,
      ));
    } on EmbyException catch (error) {
      _fail(error);
    } catch (_) {
      _set(_state.copyWith(
        loading: false,
        loaded: true,
        error: '加载失败，请稍后重试',
      ));
    }
  }

  Future<void> loadMore() async {
    final view = _state.selectedView;
    if (view == null ||
        _state.loading ||
        _state.loadingMore ||
        !_state.hasMore) {
      return;
    }

    _set(_state.copyWith(loadingMore: true, error: null));
    try {
      final page = await _service.items(view.id, startIndex: _state.items.length);
      // The user may have switched views while the page was in flight.
      if (_state.selectedView?.id != view.id) return;

      _set(_state.copyWith(
        items: <MediaItem>[..._state.items, ...page.items],
        total: page.totalRecordCount,
        loadingMore: false,
      ));
    } on EmbyException catch (error) {
      _fail(error);
    } catch (_) {
      _set(_state.copyWith(
        loadingMore: false,
        error: '加载更多失败，请上滑重试',
      ));
    }
  }

  Uri? imageUrl(String itemId, {String? tag, int? maxWidth}) =>
      _service.imageUrl(itemId, tag: tag, maxWidth: maxWidth);

  void _fail(EmbyException error, {bool keepItems = true}) {
    _set(_state.copyWith(
      loading: false,
      loadingMore: false,
      loaded: true,
      items: keepItems ? _state.items : const <MediaItem>[],
      error: error.code == AppErrorCode.unauthorized
          ? null
          : libraryErrorMessage(error.code),
      unauthorized: error.code == AppErrorCode.unauthorized,
    ));
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
