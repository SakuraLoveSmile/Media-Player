import 'json_read.dart';

/// One EPG entry from `GET /LiveTv/Programs` (S21).
///
/// Also used for a channel's `CurrentProgram`, so the live list can draw a
/// progress bar without a second request. Dates are optional: a server without
/// guide data still answers a name, and the UI then omits the progress bar.
class LiveTvProgram {
  const LiveTvProgram({
    required this.id,
    required this.name,
    this.startDate,
    this.endDate,
    this.channelId,
  });

  factory LiveTvProgram.fromJson(Map<String, dynamic> json) {
    return LiveTvProgram(
      id: asStringOr(json['Id'], ''),
      name: asStringOr(json['Name'], ''),
      startDate: parseEmbyDate(json['StartDate']),
      endDate: parseEmbyDate(json['EndDate']),
      channelId: asString(json['ChannelId']),
    );
  }

  final String id;
  final String name;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? channelId;

  /// Scheduled runtime; null when either date is missing or the range is
  /// inverted (a malformed guide entry must never drive a negative bar).
  Duration? get duration {
    final start = startDate;
    final end = endDate;
    if (start == null || end == null) return null;
    final span = end.difference(start);
    return span.isNegative ? null : span;
  }

  /// How far [now] is into the program, 0..1. Null when the dates are missing
  /// or the program has no runtime, which is the UI's cue to hide the bar.
  double? progressAt(DateTime now) {
    final start = startDate;
    final total = duration;
    if (start == null || total == null || total <= Duration.zero) return null;
    final elapsed = now.difference(start);
    if (elapsed.isNegative) return 0;
    return (elapsed.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
  }
}

/// Emby answers ISO-8601 timestamps (`2024-01-01T12:00:00.0000000Z`), but a
/// missing or malformed date must degrade to null rather than throw.
DateTime? parseEmbyDate(Object? value) {
  final raw = asString(value);
  if (raw == null) return null;
  return DateTime.tryParse(raw);
}
