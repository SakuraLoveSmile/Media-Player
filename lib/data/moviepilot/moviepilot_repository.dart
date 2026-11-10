import '../../../core/errors/app_error.dart';
import '../../../core/errors/moviepilot_exception.dart';
import '../storage/moviepilot_config_store.dart';
import '../models/json_read.dart';
import 'api/moviepilot_http_client.dart';
import 'api/mp_envelope.dart';
import 'models/moviepilot_config.dart';
import 'models/mp_downloader_torrent.dart';
import 'models/mp_media_info.dart';
import 'models/mp_season.dart';
import 'models/mp_subscribe.dart';
import 'models/mp_transfer_history.dart';
import 'models/mp_transfer_job.dart';
import 'moviepilot_service.dart';
import 'progress/poll_snapshot.dart';

/// MoviePilot v3 repository (plan S4).
///
/// Reads the connection from [MoviePilotConfigStore] on every call rather than
/// caching it, so saving new settings in the dialog takes effect on the next
/// poll without rebuilding the service graph. Every request goes to the one
/// configured origin; there is no LAN/WAN resolver for MoviePilot.
class MoviePilotRepository implements MoviePilotService {
  MoviePilotRepository(this._configStore, this._client);

  static const String _basePath = '/api/v1';

  final MoviePilotConfigStore _configStore;
  final MoviePilotHttpClient _client;


  @override
  Future<MoviePilotConfig> testConnection(MoviePilotConfig config) async {
    // The cheapest authenticated endpoint: one subscription page.
    await _client.getJson(
      config.resolve('$_basePath/subscribe/', <String, String>{
        'page': '1',
        'count': '1',
      }),
      apiToken: config.apiToken,
    );
    return config;
  }

  @override
  Future<List<MpMediaInfo>> search(String title) async {
    final config = await _requireConfig();
    final json = await _client.getJson(
      config.resolve('$_basePath/media/search', <String, String>{
        'title': title,
        'type': 'media',
        'page': '1',
        'count': '20',
        // Ask for TMDB first: its id is what the Emby lookup can use later.
        'media_source': MpMediaSource.tmdb.wire,
      }),
      apiToken: config.apiToken,
    );
    return <MpMediaInfo>[
      for (final raw in MpEnvelope.list(json, what: 'search'))
        ?MpMediaInfo.fromJson(raw),
    ];
  }

  @override
  Future<List<MpSeason>> seasons(MpMediaInfo media) async {
    final config = await _requireConfig();
    final json = await _client.getJson(
      config.resolve('$_basePath/media/seasons', <String, String>{
        'media_source': media.ref.source.wire,
        'media_id': media.ref.mediaId,
        if (media.title.isNotEmpty) 'title': media.title,
        if (media.year.isNotEmpty) 'year': media.year,
      }),
      apiToken: config.apiToken,
    );
    return <MpSeason>[
      for (final raw in MpEnvelope.list(json, what: 'seasons'))
        ?MpSeason.fromJson(raw),
    ];
  }

  @override
  Future<String?> existingItemId({
    required MpMediaRef ref,
    required MpMediaType type,
    int season = 0,
  }) async {
    final config = await _requireConfig();
    final json = await _client.getJson(
      config.resolve('$_basePath/mediaserver/exists', <String, String>{
        // v3 names this parameter `mtype`; `type` is silently ignored.
        'mtype': type.wire,
        'media_source': ref.source.wire,
        'media_id': ref.mediaId,
        if (season > 0) 'season': '$season',
      }),
      apiToken: config.apiToken,
    );
    final payload = MpEnvelope.object(json, what: 'exists');
    final item = asMap(payload['item']);
    final id = asString(item['id']);
    return id == null || id.isEmpty ? null : id;
  }

  @override
  Future<int> createSubscription(MpSubscribeDraft draft) async {
    final config = await _requireConfig();
    final json = await _client.postJson(
      config.resolve('$_basePath/subscribe/'),
      apiToken: config.apiToken,
      body: draft.toJson(),
    );
    final payload = MpEnvelope.object(json, what: 'subscribe');
    final id = asIntOrNull(payload['id']);
    if (id == null) {
      // A create without an id cannot be tracked, and silently treating it as
      // success would leave a subscription the page can never cancel.
      throw MoviePilotException(
        AppErrorCode.serverError,
        message: 'subscribe id missing',
      );
    }
    return id;
  }

  @override
  Future<void> searchNow(int subscribeId) async {
    final config = await _requireConfig();
    // v3 made this a POST; the GET form is deprecated.
    await _client.postJson(
      config.resolve('$_basePath/subscribe/search/$subscribeId'),
      apiToken: config.apiToken,
    );
  }

  @override
  Future<void> cancelSubscription(int subscribeId) async {
    final config = await _requireConfig();
    try {
      await _client.deleteJson(
        config.resolve('$_basePath/subscribe/$subscribeId'),
        apiToken: config.apiToken,
      );
    } on MoviePilotException catch (error) {
      // A subscription that already finished moved to history, so deleting it
      // by id 404s. The request itself is gone either way; the controller only
      // needs the local record removed.
      if (error.code == AppErrorCode.notFound) return;
      rethrow;
    }
  }

  @override
  Future<PollSnapshot> poll({
    bool needsTasks = true,
    Set<MpMediaType> historyTypes = const <MpMediaType>{},
  }) async {
    final config = await _requireConfig();
    final token = config.apiToken;

    final subscribes = _subscribes(
      await _client.getJson(
        config.resolve('$_basePath/subscribe/', <String, String>{
          'page': '1',
          'count': '100',
        }),
        apiToken: token,
      ),
      what: 'subscribe',
    );

    // History is only read for media types that could have finished; a movie
    // request never pays for the series history call and vice versa.
    final movieHistory = historyTypes.contains(MpMediaType.movie)
        ? await subscribeHistory(MpMediaType.movie)
        : const <MpSubscribe>[];
    final seriesHistory = historyTypes.contains(MpMediaType.series)
        ? await subscribeHistory(MpMediaType.series)
        : const <MpSubscribe>[];

    if (!needsTasks) {
      return PollSnapshot(
        subscribes: subscribes,
        movieHistory: movieHistory,
        seriesHistory: seriesHistory,
        fetchedAt: DateTime.now(),
      );
    }

    // The three task endpoints are independent; running them concurrently keeps
    // a round short when MoviePilot is slow.
    final results = await Future.wait(<Future<Object?>>[
      _client.getJson(
        config.resolve('$_basePath/download/'),
        apiToken: token,
      ),
      _client.getJson(
        config.resolve('$_basePath/transfer/queue'),
        apiToken: token,
      ),
      _client.getJson(
        config.resolve('$_basePath/history/transfer', <String, String>{
          'page': '1',
          'count': '50',
        }),
        apiToken: token,
      ),
    ]);

    return PollSnapshot(
      subscribes: subscribes,
      movieHistory: movieHistory,
      seriesHistory: seriesHistory,
      downloads: <MpDownloaderTorrent>[
        for (final raw in MpEnvelope.list(results[0], what: 'download'))
          ?MpDownloaderTorrent.fromJson(raw),
      ],
      transferQueue: <MpTransferJob>[
        for (final raw in MpEnvelope.list(results[1], what: 'queue'))
          MpTransferJob.fromJson(raw),
      ],
      transferHistory: <MpTransferHistory>[
        for (final raw in MpEnvelope.list(results[2], what: 'history'))
          ?MpTransferHistory.fromJson(raw),
      ],
      tasksLoaded: true,
      fetchedAt: DateTime.now(),
    );
  }

  /// `GET /subscribe/history/{mtype}` for one media type.
  Future<List<MpSubscribe>> subscribeHistory(MpMediaType type) async {
    final config = await _requireConfig();
    return _subscribes(
      await _client.getJson(
        config.resolve('$_basePath/subscribe/history/${type.wire}'),
        apiToken: config.apiToken,
      ),
      what: 'history',
    );
  }

  List<MpSubscribe> _subscribes(Object? json, {required String what}) {
    return <MpSubscribe>[
      for (final raw in MpEnvelope.list(json, what: what))
        ?MpSubscribe.fromJson(raw),
    ];
  }

  Future<MoviePilotConfig> _requireConfig() async {
    final config = await _configStore.read();
    if (config == null) {
      throw MoviePilotException(AppErrorCode.notConfigured);
    }
    return config;
  }
}
