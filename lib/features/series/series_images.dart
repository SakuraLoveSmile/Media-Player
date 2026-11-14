import 'package:flutter/painting.dart';

import '../../data/library/library_service.dart';
import '../../data/library/poster_cache.dart';
import '../../data/library/poster_image_provider.dart';
import '../../data/models/media_item.dart';
import '../../data/models/person.dart';

// The injected services stay private, following the controllers' convention.
// ignore_for_file: prefer_initializing_formals

/// Image providers shared by the series and season pages (S78).
///
/// Both pages draw the same hero, stills, season posters and cast portraits, so
/// the URL and cache-variant mapping lives here instead of being duplicated in
/// two controllers. A null result means "no session or no image tag" and the
/// widget draws its placeholder.
class SeriesImages {
  SeriesImages({required LibraryService library, PosterCache? posters})
    : _library = library,
      _posters = posters;

  final LibraryService _library;

  /// Null in harnesses that never render images (S47).
  final PosterCache? _posters;

  /// Poster (or any primary image) of an item at [maxWidth].
  ImageProvider? poster(String itemId, {String? tag, int maxWidth = 260}) {
    final PosterCache? posters = _posters;
    if (posters == null) return null;
    final Uri? url = _library.imageUrl(itemId, tag: tag, maxWidth: maxWidth);
    if (url == null) return null;
    return PosterImageProvider(
      cache: posters,
      itemId: itemId,
      url: url,
      tag: tag,
      maxWidth: maxWidth,
    );
  }

  /// Wide artwork for the hero and the 艺术图 row; [index] picks a backdrop.
  ImageProvider? backdrop(
    MediaItem item, {
    int index = 0,
    int maxWidth = 1100,
  }) {
    final PosterCache? posters = _posters;
    if (posters == null) return null;
    final List<String> tags = item.backdropTags;
    if (tags.isEmpty) return null;
    final int safe = index.clamp(0, tags.length - 1);
    final String tag = tags[safe];
    final Uri? url = _library.imageUrl(
      item.id,
      tag: tag,
      maxWidth: maxWidth,
      type: 'Backdrop',
      index: safe,
    );
    if (url == null) return null;
    return PosterImageProvider(
      cache: posters,
      itemId: item.id,
      url: url,
      tag: tag,
      maxWidth: maxWidth,
      variant: 'backdrop-$safe',
    );
  }

  /// Episode still (S47): the series-level Thumb when the episode has no
  /// Primary of its own, matching what the episode cards show.
  ImageProvider? episode(MediaItem episode, {int maxWidth = 480}) {
    final PosterCache? posters = _posters;
    if (posters == null) return null;
    final String? thumbId = episode.parentThumbItemId;
    final String? thumbTag = episode.parentThumbTag;
    final bool hasThumb =
        thumbId != null &&
        thumbId.isNotEmpty &&
        thumbTag != null &&
        thumbTag.isNotEmpty;
    final Uri? url = hasThumb
        ? _library.imageUrl(
            thumbId,
            tag: thumbTag,
            maxWidth: maxWidth,
            type: 'Thumb',
          )
        : _library.imageUrl(
            episode.id,
            tag: episode.imageTag,
            maxWidth: maxWidth,
          );
    if (url == null) return null;
    return PosterImageProvider(
      cache: posters,
      itemId: hasThumb ? thumbId : episode.id,
      url: url,
      tag: hasThumb ? thumbTag : episode.imageTag,
      maxWidth: maxWidth,
      variant: hasThumb ? 'episode-thumb' : '',
    );
  }

  /// Person headshots use the same primary-image endpoint as posters.
  ImageProvider? person(Person person) {
    final String? id = person.id;
    if (id == null || id.isEmpty) return null;
    return poster(id, tag: person.imageTag, maxWidth: 200);
  }
}
