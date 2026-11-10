import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'poster_cache.dart';

/// Resolves posters through [PosterCache], so scrolling back or relaunching
/// reads disk instead of the network.
///
/// Identity excludes the token-bearing URL on purpose: `api_key` changes on
/// every login, and keying on it would defeat both the disk cache and Flutter's
/// in-memory [ImageCache]. The server host stays in the key so two Emby servers
/// cannot share an entry for the same item id.
@immutable
class PosterImageProvider extends ImageProvider<PosterImageProvider> {
  const PosterImageProvider({
    required this.cache,
    required this.itemId,
    required this.url,
    this.tag,
    this.maxWidth,
  });

  final PosterCache cache;
  final String itemId;
  final Uri url;
  final String? tag;
  final int? maxWidth;

  @override
  Future<PosterImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<PosterImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    PosterImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _load(key, decode),
      scale: 1,
      debugLabel: 'poster(${key.itemId})',
    );
  }

  Future<ui.Codec> _load(
    PosterImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    final bytes = await key.cache.load(
      key.itemId,
      key.url,
      tag: key.tag,
      maxWidth: key.maxWidth,
    );
    if (bytes.isEmpty) {
      throw StateError('poster unavailable');
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is PosterImageProvider &&
      other.cache == cache &&
      other.itemId == itemId &&
      other.tag == tag &&
      other.maxWidth == maxWidth &&
      other.url.host == url.host &&
      other.url.port == url.port;

  @override
  int get hashCode =>
      Object.hash(cache, itemId, tag, maxWidth, url.host, url.port);

  @override
  String toString() => 'PosterImageProvider($itemId, tag: $tag, w: $maxWidth)';
}
