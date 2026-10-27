import 'package:media_player/data/models/playback_plan.dart';
import 'package:media_player/data/playback/session_reporter.dart';

/// One progress report, as seen by the reporter (contract §3.6).
class ProgressReport {
  ProgressReport(this.position, {required this.paused});

  final Duration position;
  final bool paused;
}

/// Reporting double for the F3 tests. It counts raw calls on purpose: the
/// `Stopped`-once guarantee under test belongs to the controller here, while
/// `SessionReporter` keeps its own flag for the real runs.
class FakePlaybackReporter implements PlaybackReporter {
  int startedCalls = 0;
  Duration? startedAt;

  /// The getter the heartbeat would poll; tests call it to prove it reads the
  /// engine and not a cached state field.
  Duration Function()? positionGetter;

  final List<ProgressReport> progressReports = <ProgressReport>[];
  int stoppedCalls = 0;
  Duration? stoppedAt;

  @override
  Future<void> started(
    PlaybackPlan plan,
    Duration initialPosition, {
    required Duration Function() position,
  }) async {
    startedCalls++;
    startedAt = initialPosition;
    positionGetter = position;
  }

  @override
  Future<void> progress(
    PlaybackPlan plan,
    Duration position, {
    required bool paused,
  }) async {
    progressReports.add(ProgressReport(position, paused: paused));
  }

  @override
  Future<void> stopped(PlaybackPlan plan, Duration position) async {
    stoppedCalls++;
    stoppedAt = position;
  }
}
