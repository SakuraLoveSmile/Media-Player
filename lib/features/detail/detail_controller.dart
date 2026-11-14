import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/errors/app_error.dart';
import '../../core/errors/emby_exception.dart';
import '../../data/library/library_service.dart';
import '../../data/library/poster_cache.dart';
import '../../data/library/poster_image_provider.dart';
import '../../data/models/media_item.dart';
import '../../data/models/person.dart';

// Keep the frozen public constructor names while the injected services stay
// private, following SeriesController's constructor convention.
// ignore_for_file: prefer_initializing_formals

class DetailState {
  const DetailState({
    this.item,
    this.loading = false,
    this.error,
    this.unauthorized = false,
    this.selectedSourceId,
    this.favoriteBusy = false,
    this.playedBusy = false,
    this.writeError,
    this.similar = const <MediaItem>[],
    this.selectedAudioIndex,
    this.selectedSubtitleIndex,
  });

  final MediaItem? item;
  final bool loading;
  final String? error;
  final bool unauthorized;

  /// Version picked for playback (S7); null = the server's default source.
  final String? selectedSourceId;

  /// In-flight favorite/played writes; the toggles stay optimistic but cannot
  /// be double-tapped into racing requests.
  final bool favoriteBusy;
  final bool playedBusy;

  /// Non-fatal write/trailer copy; the detail content stays on screen.
  final String? writeError;

  /// 推荐 row (S28); empty when the server has no suggestions.
  final List<MediaItem> similar;

  /// Tracks picked in the 当前轨道 rows (S37); passed to the player so the
  /// first playback starts with them instead of the automatic language match.
  final int? selectedAudioIndex;
  final int? selectedSubtitleIndex;

  static const Object _unset = Object();

  DetailState copyWith({
    Object? item = _unset,
    bool? loading,
    Object? error = _unset,
    bool? unauthorized,
    Object? selectedSourceId = _unset,
    bool? favoriteBusy,
    bool? playedBusy,
    Object? writeError = _unset,
    List<MediaItem>? similar,
    Object? selectedAudioIndex = _unset,
    Object? selectedSubtitleIndex = _unset,
  }) {
    return DetailState(
      item: identical(item, _unset) ? this.item : item as MediaItem?,
      loading: loading ?? this.loading,
      error: identical(error, _unset) ? this.error : error as String?,
      unauthorized: unauthorized ?? this.unauthorized,
      selectedSourceId: identical(selectedSourceId, _unset)
          ? this.selectedSourceId
          : selectedSourceId as String?,
      favoriteBusy: favoriteBusy ?? this.favoriteBusy,
      playedBusy: playedBusy ?? this.playedBusy,
      writeError: identical(writeError, _unset)
          ? this.writeError
          : writeError as String?,
      similar: similar ?? this.similar,
      selectedAudioIndex: identical(selectedAudioIndex, _unset)
          ? this.selectedAudioIndex
          : selectedAudioIndex as int?,
      selectedSubtitleIndex: identical(selectedSubtitleIndex, _unset)
          ? this.selectedSubtitleIndex
          : selectedSubtitleIndex as int?,
    );
  }
}

/// Drives the movie detail page (S7): one detail fetch, optimistic
/// favorite/played writes (S8 services) and the version pick handed to the
/// player through the route's `source` query parameter.
class DetailController extends ChangeNotifier {
  DetailController({
    required String itemId,
    required LibraryService library,
    PosterCache? posters,
    Future<bool> Function(Uri url)? urlOpener,
  }) : _itemId = itemId,
       _library = library,
       _posters = posters,
       _urlOpener = urlOpener ?? _launchUrl;

  final String _itemId;
  final LibraryService _library;
  final PosterCache? _posters;
  final Future<bool> Function(Uri url) _urlOpener;

  DetailState _state = const DetailState();
  bool _disposed = false;

  DetailState get state => _state;

  Future<void> load() async {
    if (_disposed || _state.loading || _state.unauthorized) return;
    _set(_state.copyWith(loading: true, error: null, writeError: null));
    try {
      final item = await _library.item(_itemId);
      if (_disposed || _state.unauthorized) return;
      // 推荐 is decoration: a failing suggestion call must not fail the page.
      List<MediaItem> similar = _state.similar;
      try {
        similar = await _library.similar(_itemId);
      } catch (_) {
        // Keep the previous row (usually empty on first load).
      }
      if (_disposed || _state.unauthorized) return;
      _set(
        _state.copyWith(
          item: item,
          similar: similar,
          loading: false,
          selectedSourceId: _validSource(item, _state.selectedSourceId),
        ),
      );
    } catch (error) {
      if (_handleUnauthorized(error) || _disposed || _state.unauthorized) {
        return;
      }
      _set(_state.copyWith(loading: false, error: _errorMessage(error)));
    }
  }

  /// Re-reads the item without a loading spinner, e.g. after the player
  /// reports progress back to the server. Failures stay silent: the visible
  /// detail is still valid.
  Future<void> refresh() async {
    if (_disposed || _state.item == null || _state.loading) return;
    try {
      final item = await _library.item(_itemId);
      if (_disposed || _state.unauthorized) return;
      _set(
        _state.copyWith(
          item: item,
          selectedSourceId: _validSource(item, _state.selectedSourceId),
        ),
      );
    } catch (error) {
      if (_disposed) return;
      _handleUnauthorized(error);
    }
  }

  /// Optimistic favorite flip (S8 write): the icon reacts immediately and a
  /// failed write rolls the mark back with a non-fatal notice.
  Future<void> toggleFavorite() async {
    final item = _state.item;
    if (item == null || _state.favoriteBusy) return;
    final next = !item.userData.isFavorite;
    _set(
      _state.copyWith(
        item: item.copyWith(userData: item.userData.copyWith(isFavorite: next)),
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
          item: item,
          favoriteBusy: false,
          writeError: '收藏更新失败，请稍后重试',
        ),
      );
    }
  }

  /// Optimistic watched flip (S8 write), same rollback contract as favorite.
  Future<void> togglePlayed() async {
    final item = _state.item;
    if (item == null || _state.playedBusy) return;
    final next = !item.userData.played;
    _set(
      _state.copyWith(
        item: item.copyWith(userData: item.userData.copyWith(played: next)),
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
          item: item,
          playedBusy: false,
          writeError: '观看状态更新失败，请稍后重试',
        ),
      );
    }
  }

  /// Picks the version to play; null restores the server default. Unknown ids
  /// are ignored so a stale pick can never reach negotiation.
  void selectSource(String? sourceId) {
    final item = _state.item;
    if (item == null || _state.selectedSourceId == sourceId) return;
    if (sourceId != null &&
        !item.mediaSources.any((source) => source.id == sourceId)) {
      return;
    }
    _set(_state.copyWith(selectedSourceId: sourceId));
  }

  /// Opens the server-provided trailer URL (S7). A failed launch only surfaces
  /// a notice; it must never break the detail page.
  Future<void> openTrailer() async {
    final trailer = _state.item?.remoteTrailer;
    if (trailer == null || trailer.isEmpty) return;
    final uri = Uri.tryParse(trailer);
    if (uri == null) return;
    try {
      final opened = await _urlOpener(uri);
      if (_disposed) return;
      if (!opened) _set(_state.copyWith(writeError: '无法打开预告片链接'));
    } catch (_) {
      if (_disposed) return;
      _set(_state.copyWith(writeError: '无法打开预告片链接'));
    }
  }

  /// Picks the audio track for the first playback (S37); null restores the
  /// server/default track. Indices must exist in the detail's stream list.
  void selectAudio(int? index) {
    final MediaItem? item = _state.item;
    if (item == null || item.mediaSources.isEmpty) return;
    if (index != null &&
        !item.mediaSources.first.audios.any((s) => s.index == index)) {
      return;
    }
    if (_state.selectedAudioIndex == index) return;
    _set(_state.copyWith(selectedAudioIndex: index));
  }

  /// Picks the subtitle track for the first playback (S37); null restores the
  /// default match, -1 turns subtitles off.
  void selectSubtitle(int? index) {
    final MediaItem? item = _state.item;
    if (item == null || item.mediaSources.isEmpty) return;
    if (index != null &&
        index >= 0 &&
        !item.mediaSources.first.subtitles.any((s) => s.index == index)) {
      return;
    }
    if (_state.selectedSubtitleIndex == index) return;
    _set(_state.copyWith(selectedSubtitleIndex: index));
  }

  /// Opens an external (IMDb/TMDb/Trakt) or studio link (S28).
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

  /// Null without a session or cache, which is the cue to show placeholders.
  ImageProvider? posterImage(String itemId, {String? tag, int? maxWidth}) {
    final posters = _posters;
    if (posters == null) return null;
    final url = _library.imageUrl(itemId, tag: tag, maxWidth: maxWidth);
    if (url == null) return null;
    return PosterImageProvider(
      cache: posters,
      itemId: itemId,
      url: url,
      tag: tag,
      maxWidth: maxWidth,
    );
  }

  /// Wide artwork for the hero and the 艺术图 row (S28).
  ImageProvider? backdropImage(
    MediaItem item, {
    int index = 0,
    int maxWidth = 900,
  }) {
    final posters = _posters;
    if (posters == null) return null;
    final tags = item.backdropTags;
    if (tags.isEmpty) return null;
    final tag = tags[index.clamp(0, tags.length - 1)];
    final url = _library.imageUrl(
      item.id,
      tag: tag,
      maxWidth: maxWidth,
      type: 'Backdrop',
      index: index.clamp(0, tags.length - 1),
    );
    if (url == null) return null;
    return PosterImageProvider(
      cache: posters,
      itemId: item.id,
      url: url,
      tag: tag,
      maxWidth: maxWidth,
      variant: 'backdrop-$index',
    );
  }

  /// Person headshots use the same primary-image endpoint as posters.
  ImageProvider? personImage(Person person) {
    final id = person.id;
    if (id == null || id.isEmpty) return null;
    return posterImage(id, tag: person.imageTag, maxWidth: 200);
  }

  String? _validSource(MediaItem item, String? selected) {
    if (selected == null) return null;
    return item.mediaSources.any((source) => source.id == selected)
        ? selected
        : null;
  }

  bool _handleUnauthorized(Object error) {
    if (error is! EmbyException || error.code != AppErrorCode.unauthorized) {
      return false;
    }
    if (!_disposed) {
      _set(
        _state.copyWith(
          loading: false,
          favoriteBusy: false,
          playedBusy: false,
          error: null,
          unauthorized: true,
        ),
      );
    }
    return true;
  }

  void _set(DetailState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  static Future<bool> _launchUrl(Uri url) => launchUrl(url);
}

String _errorMessage(Object error) {
  final code = error is EmbyException ? error.code : null;
  return switch (code) {
    AppErrorCode.forbidden => '没有访问该影片的权限',
    AppErrorCode.networkUnreachable => '无法连接服务器，请检查网络',
    AppErrorCode.tlsUntrusted => '服务器证书不受信任',
    AppErrorCode.notFound => '内容不存在或已被移除',
    _ => '加载失败，请稍后重试',
  };
}
