import 'models/moviepilot_config.dart';
import 'models/mp_media_info.dart';
import 'models/mp_season.dart';
import 'models/mp_subscribe.dart';
import 'progress/poll_snapshot.dart';

/// MoviePilot surface consumed by the 求片 page (plan S4).
///
/// Declared separately from [MoviePilotRepository] so the controller can be
/// tested against a fake and never touch HTTP. Everything here throws
/// [MoviePilotException]; "not configured yet" is reported as
/// `AppErrorCode.notConfigured` so the page can offer the settings shortcut.
abstract interface class MoviePilotService {
  /// Verifies the stored connection with the cheapest authenticated call.
  /// Throws `unauthorized` for a wrong token and `notConfigured` when nothing
  /// has been saved.
  Future<MoviePilotConfig> testConnection(MoviePilotConfig config);

  /// `GET /media/search` — movies and series only.
  Future<List<MpMediaInfo>> search(String title);

  /// `GET /media/seasons` for a series result.
  Future<List<MpSeason>> seasons(MpMediaInfo media);

  /// `GET /mediaserver/exists` — the Emby item id when MoviePilot already has
  /// the title in the library, null otherwise.
  ///
  /// [mtype] must be the literal 电影/电视剧 the endpoint expects (v3 names the
  /// parameter `mtype`, not `type`).
  Future<String?> existingItemId({
    required MpMediaRef ref,
    required MpMediaType type,
    int season = 0,
  });

  /// `POST /subscribe/`; returns the created id.
  Future<int> createSubscription(MpSubscribeDraft draft);

  /// `POST /subscribe/search/{id}` — asks MoviePilot to search right now.
  Future<void> searchNow(int subscribeId);

  /// `DELETE /subscribe/{id}`. A subscription that already moved to history is
  /// reported as a no-op rather than an error.
  Future<void> cancelSubscription(int subscribeId);

  /// Collects every endpoint one poll round needs.
  ///
  /// [needsTasks] selects the expensive half (`/download/`, `/transfer/queue`
  /// and `/history/transfer`); an idle round with nothing in flight costs a
  /// single request. [historyTypes] names the media types whose subscription
  /// history should be read this round — the controller only asks for types
  /// that have a request which could have finished.
  Future<PollSnapshot> poll({
    bool needsTasks = true,
    Set<MpMediaType> historyTypes = const <MpMediaType>{},
  });
}
