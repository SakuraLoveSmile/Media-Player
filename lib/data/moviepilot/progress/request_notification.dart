import '../models/media_request.dart';

/// One thing the user should hear about, derived from a poll round.
///
/// Only the event the user actually waited for is announced: the title became
/// playable. Everything else (searching, downloading, organizing) is visible
/// on 我的求片 and is not worth an interruption.
///
/// Pure data: the controller produces it, the sinks (system notification,
/// in-app banner) render it. [requestId] is the local record id so a tap can
/// open the right card; [embyItemId] is the playable Emby id.
class RequestNotification {
  const RequestNotification({
    required this.requestId,
    required this.title,
    required this.body,
    this.embyItemId,
    this.isSeries = false,
  });

  final String requestId;

  /// The media title, used as the headline.
  final String title;

  /// One sentence the user can act on.
  final String body;

  /// The playable Emby id. A series has no playable source of its own, so
  /// [isSeries] sends the tap to the episode picker instead of the player.
  final String? embyItemId;
  final bool isSeries;

  /// Stable per-request key, so a later event for the same request replaces the
  /// earlier notification instead of stacking a second copy.
  String get dedupeKey => 'request:$requestId:inLibrary';

  @override
  String toString() => 'RequestNotification($dedupeKey, $title)';
}

/// Compares the requests before and after one poll round and returns the
/// "it is playable now" events.
///
/// Pure and order-stable: the same two lists always produce the same events, so
/// the controller can call it every round without a hidden clock. Rules:
///
/// - Only a transition *into* [RequestStage.inLibrary] is announced. A request
///   that was already in the library when the app restored its list is not
///   news, and a request the app created while the title was already there is
///   shown inline by the page.
/// - A cancelled request never announces anything.
/// - A request absent from [before] (just created) is skipped: the user is
///   looking at the page that just created it.
List<RequestNotification> requestNotificationsFor({
  required List<MediaRequest> before,
  required List<MediaRequest> after,
}) {
  final previous = <String, MediaRequest>{
    for (final request in before) request.id: request,
  };

  final events = <RequestNotification>[];
  for (final request in after) {
    final old = previous[request.id];
    if (old == null) continue;
    if (request.isCancelled) continue;
    if (old.stage == RequestStage.inLibrary) continue;
    if (request.stage != RequestStage.inLibrary) continue;

    events.add(
      RequestNotification(
        requestId: request.id,
        title: request.title,
        body: request.seasonLabel.isEmpty
            ? '已入库，可以播放'
            : '${request.seasonLabel} 已入库，可以播放',
        embyItemId: request.embyItemId,
        isSeries: request.isSeries,
      ),
    );
  }
  return List<RequestNotification>.unmodifiable(events);
}
