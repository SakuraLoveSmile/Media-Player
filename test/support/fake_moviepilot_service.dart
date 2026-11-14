import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/moviepilot_exception.dart';
import 'package:media_player/data/moviepilot/models/moviepilot_config.dart';
import 'package:media_player/data/moviepilot/models/mp_media_info.dart';
import 'package:media_player/data/moviepilot/models/mp_season.dart';
import 'package:media_player/data/moviepilot/models/mp_subscribe.dart';
import 'package:media_player/data/moviepilot/moviepilot_service.dart';
import 'package:media_player/data/moviepilot/progress/poll_snapshot.dart';

/// Configurable MoviePilot double for controller and widget tests (plan S8).
///
/// Records what was asked and replays a scripted answer, so a test can assert
/// the request shapes the controller produces without a server.
class FakeMoviePilotService implements MoviePilotService {
  FakeMoviePilotService();

  /// Search results per query; a missing key answers an empty list.
  Map<String, List<MpMediaInfo>> searchResults = <String, List<MpMediaInfo>>{};

  /// Explicit search failure.
  Object? searchFailure;

  /// Seasons per media id.
  Map<String, List<MpSeason>> seasonsByMediaId = <String, List<MpSeason>>{};
  Object? seasonsFailure;

  /// The `item` of `/mediaserver/exists` per identity key; a missing key means
  /// "not in the library".
  Map<String, String> existingItems = <String, String>{};

  /// The snapshot every poll returns; replaced by a test as progress moves.
  PollSnapshot snapshot = PollSnapshot.empty;

  /// Successive snapshots, consumed in order; the last one repeats.
  List<PollSnapshot> snapshotQueue = <PollSnapshot>[];

  Object? pollFailure;
  Object? createFailure;
  Object? testFailure;
  Object? loginFailure;
  Object? searchNowFailure;
  Object? cancelFailure;

  /// Ids handed out by createSubscription, in order.
  List<int> createdIds = <int>[100];

  final List<String> searchQueries = <String>[];
  final List<MpMediaRef> seasonsRequests = <MpMediaRef>[];
  final List<String> existingRequests = <String>[];
  final List<MpSubscribeDraft> createRequests = <MpSubscribeDraft>[];
  final List<int> searchNowRequests = <int>[];
  final List<int> cancelRequests = <int>[];
  final List<MoviePilotConfig> connectionTests = <MoviePilotConfig>[];
  final List<({String baseUrl, String username, String password, String? otp})>
  logins =
      <({String baseUrl, String username, String password, String? otp})>[];
  int pollCalls = 0;
  final List<bool> pollNeedsTasks = <bool>[];
  final List<Set<MpMediaType>> pollHistoryTypes = <Set<MpMediaType>>[];

  /// When set, `poll` waits for it before answering, so a test can prove rounds
  /// are serialized.
  Future<void>? pollHold;

  /// Called on every poll so a test can advance the scripted snapshot.
  void Function(int call)? onPoll;

  @override
  Future<MoviePilotConfig> login({
    required String baseUrl,
    required String username,
    required String password,
    String? otp,
  }) async {
    logins.add((
      baseUrl: baseUrl,
      username: username,
      password: password,
      otp: otp,
    ));
    final failure = loginFailure;
    if (failure != null) throw failure;
    return MoviePilotConfig(
      baseUrl: baseUrl,
      username: username,
      accessToken: 'token-$username',
      expiresAt: DateTime.now().add(const Duration(days: 8)),
    );
  }

  @override
  Future<MoviePilotConfig> testConnection(MoviePilotConfig config) async {
    connectionTests.add(config);
    final failure = testFailure;
    if (failure != null) throw failure;
    return config;
  }

  @override
  Future<List<MpMediaInfo>> search(String title) async {
    searchQueries.add(title);
    final failure = searchFailure;
    if (failure != null) throw failure;
    return searchResults[title] ?? const <MpMediaInfo>[];
  }

  @override
  Future<List<MpSeason>> seasons(MpMediaInfo media) async {
    seasonsRequests.add(media.ref);
    final failure = seasonsFailure;
    if (failure != null) throw failure;
    return seasonsByMediaId[media.ref.mediaId] ?? const <MpSeason>[];
  }

  @override
  Future<String?> existingItemId({
    required MpMediaRef ref,
    required MpMediaType type,
    int season = 0,
  }) async {
    final key = '${ref.identityKey}#s$season';
    existingRequests.add(key);
    return existingItems[key];
  }

  @override
  Future<int> createSubscription(MpSubscribeDraft draft) async {
    createRequests.add(draft);
    final failure = createFailure;
    if (failure != null) throw failure;
    final index = createRequests.length - 1;
    return createdIds[index < createdIds.length
        ? index
        : createdIds.length - 1];
  }

  @override
  Future<void> searchNow(int subscribeId) async {
    searchNowRequests.add(subscribeId);
    final failure = searchNowFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<void> cancelSubscription(int subscribeId) async {
    cancelRequests.add(subscribeId);
    final failure = cancelFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<PollSnapshot> poll({
    bool needsTasks = true,
    Set<MpMediaType> historyTypes = const <MpMediaType>{},
  }) async {
    pollCalls++;
    pollNeedsTasks.add(needsTasks);
    pollHistoryTypes.add(historyTypes);
    onPoll?.call(pollCalls);

    final hold = pollHold;
    if (hold != null) await hold;

    final failure = pollFailure;
    if (failure != null) throw failure;

    if (snapshotQueue.isNotEmpty) {
      final index = pollCalls - 1;
      return snapshotQueue[index < snapshotQueue.length
          ? index
          : snapshotQueue.length - 1];
    }
    return snapshot;
  }
}

/// Convenience: a search hit for a movie or series.
MpMediaInfo fakeMedia({
  String mediaId = '693134',
  int? tmdbId = 693134,
  MpMediaType type = MpMediaType.movie,
  String title = '沙丘2',
  String year = '2024',
  int numberOfSeasons = 0,
}) {
  return MpMediaInfo.fromJson(<String, dynamic>{
    'media_source': 'themoviedb',
    'media_id': mediaId,
    'tmdb_id': ?tmdbId,
    'type': type.wire,
    'title': title,
    'year': year,
    if (numberOfSeasons > 0) 'number_of_seasons': numberOfSeasons,
  })!;
}

/// An active subscription for a media the fake search returned.
MpSubscribe fakeSubscribe({
  int id = 100,
  String mediaId = '693134',
  MpMediaType type = MpMediaType.movie,
  int season = 0,
  String title = '沙丘2',
  String year = '2024',
  String state = 'R',
  int submittedCount = 0,
  String error = '',
  int totalEpisode = 0,
  int completedEpisode = 0,
}) {
  return MpSubscribe(
    id: id,
    ref: MpMediaRef(
      source: MpMediaSource.tmdb,
      mediaId: mediaId,
      tmdbId: int.tryParse(mediaId),
      title: title,
      year: year,
    ),
    type: type,
    name: title,
    year: year,
    season: season,
    state: state,
    totalEpisode: totalEpisode,
    completedEpisode: completedEpisode,
    executionStatus: MpExecutionStatus(
      state: state,
      submittedCount: submittedCount,
      error: error,
    ),
  );
}

/// Raised by tests to check that a failure is surfaced as copy, not raw.
MoviePilotException mpFailure(AppErrorCode code) =>
    MoviePilotException(code, message: code.name);
