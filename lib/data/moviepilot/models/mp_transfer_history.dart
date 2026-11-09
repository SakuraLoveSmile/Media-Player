import '../../models/json_read.dart';
import 'mp_media_info.dart';

/// One row of `GET /history/transfer` (plan S3b).
///
/// `status` is v3's success flag: `true` means the files were moved into the
/// media library. That row is the app's "整理完成，等待 Emby 扫描" signal.
class MpTransferHistory {
  const MpTransferHistory({
    required this.id,
    required this.ref,
    this.type,
    this.title = '',
    this.year = '',
    this.seasons = '',
    this.episodes = '',
    this.downloadHash = '',
    this.status = false,
    this.origin = '',
    this.date = '',
  });

  static MpTransferHistory? fromJson(Map<String, dynamic> json) {
    final id = asIntOrNull(json['id']);
    if (id == null) return null;
    return MpTransferHistory(
      id: id,
      ref: MpMediaRef.fromJson(json),
      type: MpMediaType.parse(json['type']),
      title: asStringOr(json['title'], ''),
      year: asStringOr(json['year'], ''),
      seasons: asStringOr(json['seasons'], ''),
      episodes: asStringOr(json['episodes'], ''),
      downloadHash: asStringOr(json['download_hash'], ''),
      status: asBoolLoose(json['status']),
      origin: asStringOr(json['origin'], ''),
      date: asStringOr(json['date'], ''),
    );
  }

  final int id;
  final MpMediaRef ref;
  final MpMediaType? type;
  final String title;
  final String year;

  /// Display ranges: `S01` / `S01-S02` and `E01-E12`.
  final String seasons;
  final String episodes;
  final String downloadHash;
  final bool status;

  /// `external` for admin-registered transfers; empty for normal ones.
  final String origin;
  final String date;

  bool get succeeded => status;

  /// Season parsed out of `seasons`, 0 when absent.
  int get season {
    final match = RegExp(r'[Ss](\d{1,2})').firstMatch(seasons);
    if (match == null) return 0;
    return int.tryParse(match.group(1)!) ?? 0;
  }
}
