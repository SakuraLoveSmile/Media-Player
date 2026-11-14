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

  /// Image kinds requested (`Primary`, `Backdrop`, ...), for S28 tests.
  final List<String> loadedVariants = <String>[];

  /// 图片缓存 settings double (S32).
  int clearCalls = 0;
  int sizeCalls = 0;

  @override
  Future<int> sizeBytes() async {
    sizeCalls++;
    return bytes.length;
  }

  @override
  Future<void> clear() async {
    clearCalls++;
    loadedItems.clear();
    loadedVariants.clear();
  }

  @override
  Future<Uint8List> load(
    String itemId,
    Uri url, {
    String? tag,
    int? maxWidth,
    String variant = '',
  }) async {
    loadCalls++;
    loadedItems.add(itemId);
    if (variant.isNotEmpty) loadedVariants.add(variant);
    return bytes;
  }
}

/// A decodable 1x1 PNG, so the provider reaches a real codec in widget tests.
final transparentPixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ'
  '/pLvAAAAAElFTkSuQmCC',
);
