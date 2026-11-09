import '../../data/moviepilot/models/media_request.dart';
import '../../data/moviepilot/models/moviepilot_config.dart';
import '../../data/moviepilot/models/mp_media_info.dart';
import '../../data/moviepilot/models/mp_season.dart';

/// Immutable page state for 求片 (plan S8).
class RequestState {
  const RequestState({
    this.configured = false,
    this.loaded = false,
    this.query = '',
    this.searching = false,
    this.searchResults = const <MpMediaInfo>[],
    this.searchError,
    this.searchGeneration = 0,
    this.requests = const <MediaRequest>[],
    this.polling = false,
    this.pollError,
    this.configInvalid = false,
    this.unauthorizedToken = false,
    this.subscribeInFlight = false,
    this.busyRequestIds = const <String>{},
  });

  /// False until the stored connection is read once, so the page does not flash
  /// the "not configured" empty state during the first frame.
  final bool configured;

  /// True once the first restore finished.
  final bool loaded;

  /// The text the current [searchResults] belong to.
  final String query;
  final bool searching;
  final List<MpMediaInfo> searchResults;

  /// User-facing search failure; kept apart from the poll error so a failed
  /// search does not hide the request list.
  final String? searchError;

  /// Bumped on every search; a late answer whose generation is stale is dropped.
  final int searchGeneration;

  final List<MediaRequest> requests;

  /// True while a poll round is in flight.
  final bool polling;

  /// Last round failure; the list keeps its previous values.
  final String? pollError;

  /// The stored connection no longer works (401) or was cleared.
  final bool configInvalid;

  /// The API key was rejected specifically.
  final bool unauthorizedToken;

  final bool subscribeInFlight;

  /// Request ids with an action (cancel / search now) in flight.
  final Set<String> busyRequestIds;

  bool get hasRequests => requests.isNotEmpty;

  bool get hasSearchResults => searchResults.isNotEmpty;

  /// Whether the page should show the "configure MoviePilot" empty state.
  bool get needsConfiguration => loaded && !configured;

  static const Object _unset = Object();

  RequestState copyWith({
    bool? configured,
    bool? loaded,
    String? query,
    bool? searching,
    List<MpMediaInfo>? searchResults,
    Object? searchError = _unset,
    int? searchGeneration,
    List<MediaRequest>? requests,
    bool? polling,
    Object? pollError = _unset,
    bool? configInvalid,
    bool? unauthorizedToken,
    bool? subscribeInFlight,
    Set<String>? busyRequestIds,
  }) {
    return RequestState(
      configured: configured ?? this.configured,
      loaded: loaded ?? this.loaded,
      query: query ?? this.query,
      searching: searching ?? this.searching,
      searchResults: searchResults ?? this.searchResults,
      searchError:
          identical(searchError, _unset) ? this.searchError : searchError as String?,
      searchGeneration: searchGeneration ?? this.searchGeneration,
      requests: requests ?? this.requests,
      polling: polling ?? this.polling,
      pollError: identical(pollError, _unset) ? this.pollError : pollError as String?,
      configInvalid: configInvalid ?? this.configInvalid,
      unauthorizedToken: unauthorizedToken ?? this.unauthorizedToken,
      subscribeInFlight: subscribeInFlight ?? this.subscribeInFlight,
      busyRequestIds: busyRequestIds ?? this.busyRequestIds,
    );
  }
}

/// A search result prepared for the UI, with the action it offers.
class RequestSearchResult {
  const RequestSearchResult({required this.media, this.alreadyInLibrary});

  final MpMediaInfo media;

  /// The Emby item id when the title is already playable, so the card offers
  /// "去播放" instead of "求片".
  final String? alreadyInLibrary;
}

/// Seasonal data for the picker dialog (plan S12).
class RequestSeasonChoice {
  const RequestSeasonChoice({
    required this.media,
    required this.seasons,
    this.error,
    this.loading = false,
  });

  final MpMediaInfo media;
  final List<MpSeason> seasons;
  final String? error;
  final bool loading;
}

/// Result of a "connect and verify" attempt from the settings dialog.
class MoviePilotConnectionResult {
  const MoviePilotConnectionResult.success(this.config) : error = null;

  const MoviePilotConnectionResult.failure(this.error) : config = null;

  final MoviePilotConfig? config;
  final String? error;

  bool get ok => config != null;
}
