import 'package:media_player/data/models/media_stream.dart';
import 'package:media_player/data/playback/subtitle_repository.dart';

/// Subtitle download double for controller/page tests; no HTTP, no disk.
class FakeSubtitleService implements SubtitleService {
  FakeSubtitleService({
    this.path = '/cache/item-1_source-1_3.srt',
    this.failure,
  });

  String path;
  Object? failure;
  final List<({String itemId, String mediaSourceId, int index})> requests =
      <({String itemId, String mediaSourceId, int index})>[];

  @override
  Future<String> externalFile({
    required String itemId,
    required String mediaSourceId,
    required MediaStream stream,
  }) async {
    requests.add((
      itemId: itemId,
      mediaSourceId: mediaSourceId,
      index: stream.index,
    ));
    final error = failure;
    if (error != null) throw error;
    return path;
  }
}
