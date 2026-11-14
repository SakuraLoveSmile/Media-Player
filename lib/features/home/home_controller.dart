import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../core/errors/app_error.dart';
import '../../core/errors/emby_exception.dart';
import '../../data/library/library_service.dart';
import '../../data/library/poster_cache.dart';
import '../../data/library/poster_image_provider.dart';
import '../../data/models/library_view.dart';
import '../../data/models/media_item.dart';

/// One per-library horizontal row on the home dashboard.
class HomeRow {
  const HomeRow({required this.view, required this.items, this.total = 0});

  final LibraryView view;
  final List<MediaItem> items;

  /// `TotalRecordCount` of the view's first page, used for the library strip
  /// badge (S28).
  final int total;
}

class HomeState {
  const HomeState({
    this.serverName = '',
    this.views = const <LibraryView>[],
    this.banner = const <MediaItem>[],
    this.resumable = const <MediaItem>[],
    this.rows = const <HomeRow>[],
    this.loading = false,
    this.loaded = false,
    this.error,
    this.unauthorized = false,
  });

  /// Server display name for the header (`System/Info/Public.ServerName`).
  final String serverName;

  /// The server's libraries, in view order; the 媒体库 strip renders these.
  final List<LibraryView> views;

  /// Recommended carousel: newest additions from the first movie view.
  final List<MediaItem> banner;

  /// Continue-watching row (`Filters=IsResumable`).
  final List<MediaItem> resumable;

  /// Per-library poster rows, in the server's view order.
  final List<HomeRow> rows;

  final bool loading;

  /// True once at least one load attempt finished, so empty states are not
  /// shown while the first load is still in flight.
  final bool loaded;
  final String? error;
  final bool unauthorized;

  bool get isEmpty => banner.isEmpty && resumable.isEmpty && rows.isEmpty;

  static const Object _unset = Object();

  HomeState copyWith({
    String? serverName,
    List<LibraryView>? views,
    List<MediaItem>? banner,
    List<MediaItem>? resumable,
    List<HomeRow>? rows,
    bool? loading,
    bool? loaded,
    Object? error = _unset,
    bool? unauthorized,
  }) {
    return HomeState(
      serverName: serverName ?? this.serverName,
      views: views ?? this.views,
      banner: banner ?? this.banner,
      resumable: resumable ?? this.resumable,
      rows: rows ?? this.rows,
      loading: loading ?? this.loading,
      loaded: loaded ?? this.loaded,
      error: identical(error, _unset) ? this.error : error as String?,
      unauthorized: unauthorized ?? this.unauthorized,
    );
  }
}

/// Drives the home dashboard (P1/S28): the server header, the recommended
/// banner, the library strip, the continue-watching row and one poster row per
/// library view. Mirrors the library controller's session/error handling so an
/// expired token still returns to login.
class HomeController extends ChangeNotifier {
  HomeController(this._service, this._posters, {Set<String>? hiddenViewIds})
    : _hiddenViewIds = hiddenViewIds ?? const <String>{};

  final LibraryService _service;
  final PosterCache _posters;

  /// Libraries hidden in 设置 → 通用 → 媒体库 (S32): their rows are never
  /// fetched, so a hidden library costs no requests on the dashboard.
  final Set<String> _hiddenViewIds;

  HomeState _state = const HomeState();
  bool _disposed = false;

  HomeState get state => _state;

  Future<void> load() async {
    if (_state.loading) return;

    _set(_state.copyWith(loading: true, error: null, unauthorized: false));
    try {
      final List<LibraryView> allViews = await _service.views();
      final List<LibraryView> visible = allViews
          .where((LibraryView view) => !_hiddenViewIds.contains(view.id))
          .toList(growable: false);
      // Hiding every library falls back to the full list: the dashboard must
      // never become an empty page the user cannot leave.
      final views = visible.isEmpty ? allViews : visible;
      if (views.isEmpty) {
        _set(_state.copyWith(loading: false, loaded: true));
        return;
      }

      // The header name is cosmetic: a server that does not answer must not
      // break the dashboard.
      String name = _state.serverName;
      try {
        name = await _service.serverName();
      } catch (_) {
        // Keep the previous name.
      }

      // The banner pulls from the first movie view (falling back to the first
      // view of any kind) so a music/photo library never headlines the page.
      final LibraryView movieView = views.firstWhere(
        (view) => view.collectionType == 'movies',
        orElse: () => views.first,
      );
      final bannerPage = await _service.items(
        movieView.id,
        limit: 5,
        sortBy: 'DateCreated',
        sortOrder: 'Descending',
      );
      final resumablePage = await _service.resumable();
      final rows = await Future.wait(<Future<HomeRow>>[
        for (final view in views)
          _service
              .items(view.id, limit: 12)
              .then(
                (page) => HomeRow(
                  view: view,
                  items: page.items,
                  total: page.totalRecordCount,
                ),
              ),
      ]);

      _set(
        HomeState(
          serverName: name,
          views: views,
          banner: bannerPage.items,
          resumable: resumablePage.items,
          rows: rows,
          loaded: true,
        ),
      );
    } on EmbyException catch (error) {
      _fail(error);
    } catch (_) {
      _set(_state.copyWith(loading: false, loaded: true, error: '加载失败，请稍后重试'));
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

  /// Wide artwork for the banner and the continue-watching cards (S28).
  ///
  /// Episodes carry no backdrop of their own, so the parent series' backdrop
  /// is requested through `ParentBackdropItemId`. Null falls back to the
  /// poster.
  ImageProvider? backdropImage(MediaItem item, {int maxWidth = 720}) {
    final String? parentId = item.parentBackdropItemId;
    final String? parentTag = item.parentBackdropTag;
    final bool useParent =
        (item.backdropTag?.isEmpty ?? true) &&
        parentId != null &&
        parentId.isNotEmpty &&
        parentTag != null &&
        parentTag.isNotEmpty;
    final String id = useParent ? parentId : item.id;
    final String? tag = useParent ? parentTag : item.backdropTag;
    if (tag == null || tag.isEmpty) return null;
    final url = _service.imageUrl(
      id,
      tag: tag,
      maxWidth: maxWidth,
      type: 'Backdrop',
      index: 0,
    );
    if (url == null) return null;
    return PosterImageProvider(
      cache: _posters,
      itemId: id,
      url: url,
      tag: tag,
      maxWidth: maxWidth,
      variant: 'backdrop',
    );
  }

  /// Library primary image for the 媒体库 strip; falls back to the first
  /// row's first poster when the library has no artwork of its own.
  ImageProvider? viewImage(LibraryView view, {int maxWidth = 480}) {
    if (view.imageTag != null && view.imageTag!.isNotEmpty) {
      final url = _service.imageUrl(
        view.id,
        tag: view.imageTag,
        maxWidth: maxWidth,
      );
      if (url != null) {
        return PosterImageProvider(
          cache: _posters,
          itemId: view.id,
          url: url,
          tag: view.imageTag,
          maxWidth: maxWidth,
        );
      }
    }
    for (final row in _state.rows) {
      if (row.view.id != view.id || row.items.isEmpty) continue;
      final MediaItem first = row.items.first;
      return posterImage(first.id, tag: first.imageTag, maxWidth: maxWidth);
    }
    return null;
  }

  void _fail(EmbyException error) {
    _set(
      _state.copyWith(
        loading: false,
        loaded: true,
        error: error.code == AppErrorCode.unauthorized
            ? null
            : _errorMessage(error.code),
        unauthorized: error.code == AppErrorCode.unauthorized,
      ),
    );
  }

  void _set(HomeState state) {
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

String _errorMessage(AppErrorCode code) {
  return switch (code) {
    AppErrorCode.unauthorized => '登录已过期，请重新登录',
    AppErrorCode.forbidden => '没有访问该媒体库的权限',
    AppErrorCode.networkUnreachable => '无法连接服务器，请检查网络',
    AppErrorCode.tlsUntrusted => '服务器证书不受信任',
    AppErrorCode.notFound => '内容不存在或已被移除',
    _ => '加载失败，请稍后重试',
  };
}
