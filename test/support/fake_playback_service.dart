import 'package:media_player/core/network/endpoint_kind.dart';
import 'package:media_player/data/models/playback_plan.dart';
import 'package:media_player/data/playback/playback_service.dart';

/// Negotiation double for the F3 controller/page tests; no HTTP, no token.
class FakePlaybackService implements PlaybackService {
  FakePlaybackService({PlaybackPlan? plan, this.confirmedPlan, this.failure})
      : plan = plan ?? fakePlan();

  /// Returned by [resolve] (with `startAt` applied).
  PlaybackPlan plan;

  /// Returned by [confirmDirect]; defaults to [plan] untouched, i.e. the
  /// verdict stays null (contract §10.9 f).
  PlaybackPlan? confirmedPlan;

  /// Thrown by [resolve] when set.
  Object? failure;

  final List<Duration> resolveStartAts = <Duration>[];
  int confirmCalls = 0;

  int get resolveCalls => resolveStartAts.length;

  @override
  Future<PlaybackPlan> resolve(
    String itemId, {
    Duration startAt = Duration.zero,
  }) async {
    resolveStartAts.add(startAt);
    final error = failure;
    if (error != null) throw error;
    return plan.copyWith(itemId: itemId, startAt: startAt);
  }

  @override
  Future<PlaybackPlan> confirmDirect(PlaybackPlan plan) async {
    confirmCalls++;
    return confirmedPlan ?? plan;
  }
}

PlaybackPlan fakePlan({
  String itemId = 'item-1',
  PlaybackMode mode = PlaybackMode.direct,
  bool? videoDirect,
  bool audioTranscoded = false,
}) {
  return PlaybackPlan(
    itemId: itemId,
    mode: mode,
    endpointKind: EndpointKind.lan,
    url: 'http://lan.example/videos/$itemId/stream',
    headers: const <String, String>{},
    mediaSourceId: 'source-1',
    playSessionId: 'session-1',
    videoDirect: videoDirect,
    audioTranscoded: audioTranscoded,
  );
}
