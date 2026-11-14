import 'json_read.dart';
import 'live_tv_program.dart';

/// One live channel from `GET /LiveTv/Channels` (S21).
///
/// [currentProgram] is parsed from the embedded `CurrentProgram` object when
/// the server includes it (`AddCurrentProgram=true`), so the list can show the
/// airing title and a progress bar without an EPG round-trip per channel.
class LiveTvChannel {
  const LiveTvChannel({
    required this.id,
    required this.name,
    this.number,
    this.imageTag,
    this.currentProgram,
  });

  factory LiveTvChannel.fromJson(Map<String, dynamic> json) {
    final program = asMap(json['CurrentProgram']);
    return LiveTvChannel(
      id: asStringOr(json['Id'], ''),
      name: asStringOr(json['Name'], ''),
      number: _number(json['Number']),
      imageTag: asString(asMap(json['ImageTags'])['Primary']),
      currentProgram: program.isEmpty ? null : LiveTvProgram.fromJson(program),
    );
  }

  final String id;
  final String name;

  /// Channel number (e.g. `1.1`); Emby sends a string, but a numeric guide
  /// value is tolerated so a version difference never drops the label.
  final String? number;
  final String? imageTag;
  final LiveTvProgram? currentProgram;
}

String? _number(Object? value) {
  if (value is String) return value.isEmpty ? null : value;
  if (value is num) return value.toString();
  return null;
}
