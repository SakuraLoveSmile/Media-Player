import '../../models/json_read.dart';

/// One bullet comment (S17 弹幕) from DandanPlay's `comment/{episodeId}` reply.
///
/// The wire shape is `{cid, p, m, s}` where `p` is `"time,mode,color,size"`:
/// time in seconds (fractional), mode 1/2/3 = right-to-left scroll, 4 = pinned
/// bottom, 5 = pinned top, color as decimal RGB (16777215 = white). The size
/// field is intentionally not kept: the overlay renders one legible font size
/// for every comment (Yamby parity).
class DanmakuComment {
  const DanmakuComment({
    required this.time,
    required this.mode,
    required this.color,
    required this.text,
    this.id = 0,
  });

  /// Parses one wire entry; null when it is unusable (empty text, missing or
  /// malformed `p`). A single bad comment must never drop the whole batch.
  static DanmakuComment? fromJson(Map<String, dynamic> json) {
    final String text = asStringOr(json['m'], '');
    if (text.isEmpty) return null;
    final List<String> parts = asStringOr(json['p'], '').split(',');
    if (parts.length < 3) return null;
    final double? seconds = double.tryParse(parts[0].trim());
    final int? mode = int.tryParse(parts[1].trim());
    final int? color = int.tryParse(parts[2].trim());
    if (seconds == null || mode == null || color == null || seconds < 0) {
      return null;
    }
    return DanmakuComment(
      id: asInt(json['cid']),
      time: Duration(milliseconds: (seconds * 1000).round()),
      mode: mode,
      color: color,
      text: text,
    );
  }

  /// Server comment id (`cid`); 0 when absent. Used for widget keys only.
  final int id;

  /// Playback position the comment belongs to.
  final Duration time;

  /// DandanPlay mode: 1/2/3 scroll, 4 pinned bottom, 5 pinned top.
  final int mode;

  /// Decimal RGB; the overlay forces full alpha when rendering.
  final int color;

  final String text;

  /// True for the pinned modes (4 bottom / 5 top).
  bool get isPinned => mode == 4 || mode == 5;
}
