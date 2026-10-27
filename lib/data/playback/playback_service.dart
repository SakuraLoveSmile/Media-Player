import '../models/playback_plan.dart';

/// Playback negotiation used by the UI (contract §3.1, §3.4).
///
/// Declared separately from [PlaybackRepository] so the playback page can be
/// tested with a fake and never touch HTTP.
abstract interface class PlaybackService {
  /// Negotiates a playable source and returns a plan (contract §3.1, §3.4).
  Future<PlaybackPlan> resolve(
    String itemId, {
    Duration startAt = Duration.zero,
  });

  /// Fills in the server's direct-play verdict (contract §3.5). Never throws.
  Future<PlaybackPlan> confirmDirect(PlaybackPlan plan);
}
