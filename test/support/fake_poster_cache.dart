import 'dart:convert';
import 'dart:typed_data';

import 'package:media_player/data/library/poster_cache.dart';

/// Counts poster resolutions so widget tests can prove the in-memory image
/// cache dedupes rebuilds. No disk, no transport.
class FakePosterCache implements PosterCache {
  FakePosterCache({Uint8List? bytes}) : bytes = bytes ?? transparentPixel;

  final Uint8List bytes;
  int loadCalls = 0;
  final List<String> loadedItems = <String>[];

  @override
  Future<Uint8List> load(
    String itemId,
    Uri url, {
    String? tag,
    int? maxWidth,
  }) async {
    loadCalls++;
    loadedItems.add(itemId);
    return bytes;
  }
}

/// A decodable 1x1 PNG, so the provider reaches a real codec in widget tests.
final transparentPixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ'
  '/pLvAAAAAElFTkSuQmCC',
);
