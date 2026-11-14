import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/errors/app_error.dart';
import '../../core/errors/moviepilot_exception.dart';
import '../../data/library/library_service.dart';
import '../../data/moviepilot/models/media_request.dart';
import '../../data/moviepilot/models/moviepilot_config.dart';
import '../../data/moviepilot/models/mp_media_info.dart';
import '../../data/moviepilot/models/mp_season.dart';
import '../../data/moviepilot/models/mp_subscribe.dart';
import '../../data/moviepilot/moviepilot_service.dart';
import '../../data/moviepilot/progress/poll_snapshot.dart';
import '../../data/moviepilot/progress/request_notification.dart';
import '../../data/moviepilot/progress/request_progress_engine.dart';
import '../../data/storage/moviepilot_config_store.dart';
import '../../data/storage/request_store.dart';
import 'request_state.dart';

// Named constructor parameters read better than positional ones at the call
// site, and this controller has nine of them.
// ignore_for_file: prefer_initializing_formals

/// Drives the 求片 page: search, subscribe, and the foreground poll (plan S8).
///
/// Mirrors [LibraryController]: the page creates it, it exposes one immutable
/// state, and `dispose` stops the heartbeat. Polling is foreground-only — a
/// closed page makes no requests — and every round is serialized so a slow
/// answer can never overwrite a newer one.
class RequestController extends ChangeNotifier {
  RequestController({
    required MoviePilotService service,
    required RequestStore requestStore,
    required MoviePilotConfigStore configStore,
    LibraryService? library,
    Stream<void>? heartbeat,
    Duration pollInterval = const Duration(seconds: 8),
    Future<void> Function(Duration)? delay,
    DateTime Function()? clock,
    String Function()? idGenerator,
    RequestProgressEngine engine = const RequestProgressEngine(),
  }) : _service = service,
       _requestStore = requestStore,
       _configStore = configStore,
       _library = library,
       _engine = engine,
       _externalHeartbeat = heartbeat,
       _pollInterval = pollInterval,
       _delay = delay ?? Future<void>.delayed,
       _clock = clock ?? DateTime.now,
       _newId = idGenerator ?? (() => const Uuid().v4());

  final MoviePilotService _service;
  final RequestStore _requestStore;
  final MoviePilotConfigStore _configStore;
  final LibraryService? _library;
  final RequestProgressEngine _engine;

  /// Test-only heartbeat. Production uses [_pollInterval] with a timer the
  /// controller owns, because a single-subscription `Stream.periodic` cannot be
  /// listened to twice: pausing and resuming a page would throw
  /// `Stream has already been listened to` and silently stop the poll for good.
  final Stream<void>? _externalHeartbeat;
  final Duration _pollInterval;
  final Future<void> Function(Duration) _delay;
  final DateTime Function() _clock;
  final String Function() _newId;

  /// One page of MoviePilot search; enough for a picker, cheap to render.
  static const int _searchPageSize = 20;

  /// Pause between creating a subscription and the first progress round.
  static const Duration _firstRoundDelay = Duration(milliseconds: 400);

  RequestState _state = const RequestState();
  PollSnapshot _snapshot = PollSnapshot.empty;
  StreamSubscription<void>? _ticks;
  Timer? _timer;
  Future<void> _queue = Future<void>.value();
  bool _disposed = false;
  bool _roundInFlight = false;
  bool _started = false;

  /// Sinks for "became playable" events. Kept as plain callbacks so the
  /// controller stays free of plugins and the app wiring owns the presentation.
  final Set<void Function(RequestNotification event)> _notificationListeners =
      <void Function(RequestNotification event)>{};

  RequestState get state => _state;

  /// Last snapshot, exposed for tests and for the "is it in the library?" check.
  PollSnapshot get snapshot => _snapshot;

  /// Restores the stored list, then starts polling (plan S8 `load`).
  ///
  /// A missing connection puts the page in its configuration state instead of
  /// failing: nothing is stored, nothing to retry.
  Future<void> load() async {
    final config = await _configStore.read();
    await _restore();
    if (config == null) {
      _set(
        _state.copyWith(
          configured: false,
          loaded: true,
          polling: false,
          configInvalid: false,
          unauthorizedToken: false,
        ),
      );
      return;
    }

    _set(
      _state.copyWith(
        configured: true,
        loaded: true,
        configInvalid: false,
        unauthorizedToken: false,
      ),
    );
    _start();
    await _enqueue(_pollOnceGuarded);
  }

  /// One round without the "is there anything to watch?" gate.
  Future<void> _pollOnceGuarded() async {
    if (_disposed || _roundInFlight) return;
    _roundInFlight = true;
    try {
      await _pollOnce();
    } finally {
      _roundInFlight = false;
    }
  }

  /// Starts the heartbeat once; safe to call again after [load].
  ///
  /// The default beat is a timer the controller creates and cancels itself, so
  /// it can be stopped and restarted any number of times. An injected
  /// [_externalHeartbeat] is single-use by nature and only exists for tests,
  /// which pass a broadcast stream or an empty one.
  void _start() {
    if (_started || _disposed) return;
    _started = true;
    final external = _externalHeartbeat;
    if (external != null) {
      _ticks = external.listen((_) => _onTick());
      return;
    }
    _timer = Timer.periodic(_pollInterval, (_) => _onTick());
  }

  void _onTick() {
    if (_disposed) return;
    // A tick with nothing to watch costs nothing.
    if (_heartbeatShouldPoll) unawaited(pollRound());
  }

  void _stopBeat() {
    _started = false;
    unawaited(_ticks?.cancel());
    _ticks = null;
    _timer?.cancel();
    _timer = null;
  }

  /// Re-reads the connection and starts polling again (called after the dialog
  /// saved a connection).
  Future<void> reconnect() async {
    _stopBeat();
    await load();
  }

  /// Suspends the heartbeat without forgetting anything.
  ///
  /// Kept for the pages that used to own the poll. Polling is now driven by the
  /// app for as long as it is alive (see [startWatching]), so a page leaving the
  /// screen must not silence notifications; the app-level wiring calls this only
  /// when it really wants the rounds to stop (app paused, user signed out).
  Future<void> pausePolling() async {
    _stopBeat();
  }

  /// Starts the long-lived heartbeat and runs one round.
  ///
  /// Called once by the app-level wiring rather than by a page, because a
  /// 求片 finishing while the user browses the library or watches something is
  /// exactly when a notification is worth showing. Idempotent.
  Future<void> startWatching() async {
    if (_disposed) return;
    _start();
    if (_heartbeatShouldPoll) await pollRound();
  }

  /// Resumes the heartbeat and runs one round, unless it is already running.
  Future<void> resumePolling() async {
    if (_disposed) return;
    _start();
    if (_started && _heartbeatShouldPoll) await pollRound();
  }

  /// Whether the heartbeat should ask MoviePilot for progress.
  ///
  /// A brand-new page has nothing to watch yet, so the first rounds are driven
  /// by [load] and by the actions themselves; once a request exists, every
  /// unfinished one keeps the heartbeat going. When all of them are in the
  /// library or cancelled there is nothing left to learn and the rounds stop;
  /// a new 求片 or a reopened page starts them again.
  bool get needsPolling {
    if (_state.requests.isEmpty) return false;
    return _state.requests.any(
      (request) => !request.isFinished && !request.isCancelled,
    );
  }

  /// Whether a heartbeat tick should run a round.
  ///
  /// The heartbeat is the only source that may be gated: an explicit
  /// [refresh], the round after [load] and the round an action triggers all
  /// have to run even with an empty list, because they are what tell an empty
  /// history apart from an unreachable MoviePilot.
  bool get _heartbeatShouldPoll => needsPolling;

  /// Runs exactly one poll round, skipping when another is still in flight so a
  /// slow MoviePilot cannot pile up requests.
  Future<void> pollRound() {
    if (_disposed || _roundInFlight) return Future<void>.value();
    return _enqueue(() async {
      if (_disposed) return;
      _roundInFlight = true;
      try {
        await _pollOnce();
      } finally {
        _roundInFlight = false;
      }
    });
  }

  Future<void> _pollOnce() async {
    final requests = _state.requests;
    final needsTasks = requests.any(
      (request) =>
          !request.isFinished &&
          !request.isCancelled &&
          request.stage != RequestStage.submitted,
    );
    // Only ask for the history of a media type that has a request which could
    // plausibly have finished; a movie request never pays for the series call.
    final historyTypes = <MpMediaType>{
      for (final request in requests)
        if (!request.isFinished && !request.isCancelled) request.type,
    };

    _set(_state.copyWith(polling: true));

    final PollSnapshot snapshot;
    try {
      snapshot = await _service.poll(
        needsTasks: needsTasks,
        historyTypes: historyTypes,
      );
    } on MoviePilotException catch (error) {
      _handlePollFailure(error);
      return;
    } catch (_) {
      _set(_state.copyWith(polling: false, pollError: '进度同步失败，正在重试'));
      return;
    }

    // Keep the task half from the previous round when this round skipped it, so
    // an idle round cannot erase a known download.
    _snapshot = needsTasks
        ? snapshot
        : snapshot.copyWith(
            downloads: _snapshot.downloads,
            transferQueue: _snapshot.transferQueue,
            transferHistory: _snapshot.transferHistory,
            tasksLoaded: _snapshot.tasksLoaded,
          );

    final now = _clock();
    final derived = <MediaRequest>[];
    for (final request in requests) {
      if (request.isCancelled) {
        derived.add(request);
        continue;
      }
      final progress = _engine.derive(request, _snapshot, now: now);
      var updated = progress.applyTo(request).copyWith(lastUpdatedAt: now);

      // Promote "files are in the library" to "playable now" when Emby agrees.
      // A failing Emby must not block MoviePilot progress, so errors are
      // swallowed here.
      if (updated.stage == RequestStage.organizedPendingLibrary &&
          (updated.embyItemId == null || updated.embyItemId!.isEmpty)) {
        final itemId = await _lookupLibrary(updated);
        if (itemId != null) {
          updated = updated.copyWith(
            embyItemId: itemId,
            stage: RequestStage.inLibrary,
            message: '已入库，可以播放',
            archived: true,
          );
        }
      }
      derived.add(updated);
    }

    // The user may have removed a request while this round was in flight; a
    // derived record for it must not come back (and must not be re-persisted).
    final live = <String>{for (final request in _state.requests) request.id};
    final kept = <MediaRequest>[
      for (final request in derived)
        if (live.contains(request.id)) request,
    ];
    // The pre-round list is the only trustworthy "what the user already knew":
    // _state.requests may have been changed by an action while the round was in
    // flight, and the events must describe the transition, not the race.
    final events = requestNotificationsFor(before: requests, after: kept);
    _set(_state.copyWith(requests: kept, polling: false, pollError: null));
    await _persist(kept);
    for (final event in events) {
      _notify(event);
    }
  }

  /// Hands one event to every subscriber; a listener throwing must not break
  /// the round or the other sinks.
  void _notify(RequestNotification event) {
    for (final listener in _notificationListeners) {
      try {
        listener(event);
      } catch (error) {
        debugPrint('[request] 通知派发失败：$error');
      }
    }
  }

  /// Subscribes to "it became playable" events.
  ///
  /// The controller deliberately does not know how a notification is shown: the
  /// app-level wiring decides whether that is a system notification, an in-app
  /// banner, or both. Returns the unsubscribe callback.
  void Function() addNotificationListener(
    void Function(RequestNotification event) listener,
  ) {
    _notificationListeners.add(listener);
    return () => _notificationListeners.remove(listener);
  }

  /// Looks the request up in Emby; never throws (plan S8).
  Future<String?> _lookupLibrary(MediaRequest request) async {
    final library = _library;
    if (library == null) return null;
    final isSeries = request.isSeries;
    try {
      final tmdbId = request.ref.tmdbId;
      if (tmdbId != null) {
        final byId = await library.findByTmdb(tmdbId, isSeries: isSeries);
        if (byId != null && byId.id.isNotEmpty) return byId.id;
      }
      final year = int.tryParse(request.year);
      final byTitle = await library.searchByTitle(
        request.title,
        year: year,
        isSeries: isSeries,
      );
      if (byTitle != null && byTitle.id.isNotEmpty) return byTitle.id;
    } catch (_) {
      // Emby unreachable or logged out: the request stays pending until the
      // next round, which is exactly what the user should see.
      return null;
    }
    return null;
  }

  void _handlePollFailure(MoviePilotException error) {
    switch (error.code) {
      case AppErrorCode.notConfigured:
        _set(
          _state.copyWith(
            configured: false,
            polling: false,
            configInvalid: true,
            unauthorizedToken: false,
          ),
        );
        unawaited(_ticks?.cancel().then((_) => _ticks = null));
        _started = false;
      case AppErrorCode.unauthorized:
        // The session will never work again without a new login: stop the
        // heartbeat and send the user to the settings dialog.
        _set(
          _state.copyWith(
            polling: false,
            configInvalid: true,
            unauthorizedToken: true,
            pollError: 'MoviePilot 登录已失效，请重新登录',
          ),
        );
        _stopBeat();
      case AppErrorCode.forbidden:
        // The account signed in, but the instance will not hand over the
        // download and transfer data the progress needs. Retrying cannot grant
        // a role, so stop and say what is missing.
        _set(
          _state.copyWith(
            polling: false,
            unauthorizedToken: false,
            pollError: 'MoviePilot 账号权限不足，无法读取下载与整理进度',
          ),
        );
        _stopBeat();
      default:
        // Everything else is transient: keep the last snapshot and retry.
        _set(
          _state.copyWith(
            polling: false,
            pollError: error.code == AppErrorCode.networkUnreachable
                ? '无法连接 MoviePilot，请检查网络'
                : '进度同步失败，正在重试',
          ),
        );
    }
  }

  /// `GET /media/search` for [query] (plan S8 `search`).
  ///
  /// The generation guard drops an answer whose query was replaced while it was
  /// in flight, so the list always belongs to the text in the box.
  Future<void> search(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty || _disposed) return;

    final generation = _state.searchGeneration + 1;
    _set(
      _state.copyWith(
        query: query,
        searching: true,
        searchError: null,
        searchResults: const <MpMediaInfo>[],
        searchGeneration: generation,
      ),
    );

    try {
      final results = await _service.search(query);
      if (_disposed || _state.searchGeneration != generation) return;
      _set(
        _state.copyWith(
          searching: false,
          searchResults: results.take(_searchPageSize).toList(growable: false),
        ),
      );
    } on MoviePilotException catch (error) {
      if (_disposed || _state.searchGeneration != generation) return;
      if (error.code == AppErrorCode.notConfigured ||
          error.code == AppErrorCode.unauthorized) {
        _set(
          _state.copyWith(
            searching: false,
            configured: error.code == AppErrorCode.notConfigured
                ? false
                : _state.configured,
            configInvalid: true,
            unauthorizedToken: error.code == AppErrorCode.unauthorized,
            searchError: requestErrorMessage(error.code),
          ),
        );
        return;
      }
      _set(
        _state.copyWith(
          searching: false,
          searchError: requestErrorMessage(error.code),
        ),
      );
    } catch (_) {
      if (_disposed || _state.searchGeneration != generation) return;
      _set(_state.copyWith(searching: false, searchError: '搜索失败，请稍后重试'));
    }
  }

  /// Loads the season list for a series result (plan S12).
  Future<RequestSeasonChoice> seasons(MpMediaInfo media) async {
    try {
      final result = await _service.seasons(media);
      return RequestSeasonChoice(media: media, seasons: result);
    } on MoviePilotException catch (error) {
      return RequestSeasonChoice(
        media: media,
        seasons: const <MpSeason>[],
        error: requestErrorMessage(error.code),
      );
    } catch (_) {
      return RequestSeasonChoice(
        media: media,
        seasons: const <MpSeason>[],
        error: '读取季信息失败，请稍后重试',
      );
    }
  }

  /// Creates a subscription and its local record (plan S12).
  ///
  /// Checks MoviePilot's library first: a title already in the library is
  /// promoted to "playable" instead of subscribing to it again. Returns the
  /// record, or null when the action failed (see [state.pollError]/message).
  Future<MediaRequest?> subscribe(MpMediaInfo media, {int season = 0}) async {
    if (_disposed || _state.subscribeInFlight) return null;

    // Same media, same season: the user already asked for this, so tapping
    // twice must not create a second subscription.
    final existing = _findExisting(media.ref, media.type, season);
    if (existing != null) return existing;

    _set(_state.copyWith(subscribeInFlight: true, pollError: null));
    try {
      final alreadyThere = await _service.existingItemId(
        ref: media.ref,
        type: media.type!,
        season: season,
      );
      if (_disposed) return null;
      if (alreadyThere != null && alreadyThere.isNotEmpty) {
        final record = _newRequest(
          media,
          season: season,
          embyItemId: alreadyThere,
        );
        final updated = record.copyWith(
          stage: RequestStage.inLibrary,
          message: '媒体库已有该片，可直接播放',
          archived: true,
        );
        await _addRequest(updated);
        return updated;
      }

      final id = await _service.createSubscription(
        MpSubscribeDraft.fromMedia(media, season: season),
      );
      if (_disposed) return null;

      final record = _newRequest(media, season: season, subscribeId: id);
      await _addRequest(record);
      // Ask MoviePilot to search right away instead of waiting for the schedule.
      await _searchNowQuietly(id);
      // MoviePilot lists a new subscription with a short delay, so give it a
      // beat before asking for progress; the heartbeat covers the rest.
      await _delay(_firstRoundDelay);
      unawaited(pollRound());
      return record;
    } on MoviePilotException catch (error) {
      _set(
        _state.copyWith(
          subscribeInFlight: false,
          pollError: requestErrorMessage(error.code),
          configInvalid:
              error.code == AppErrorCode.unauthorized ||
              error.code == AppErrorCode.notConfigured,
        ),
      );
      return null;
    } catch (_) {
      _set(_state.copyWith(subscribeInFlight: false, pollError: '求片失败，请稍后重试'));
      return null;
    } finally {
      if (!_disposed) _set(_state.copyWith(subscribeInFlight: false));
    }
  }

  /// `POST /subscribe/search/{id}` (plan S8 `searchNow`).
  Future<void> searchNow(MediaRequest request) async {
    final id = request.subscribeId;
    if (id == null || _disposed) return;

    _set(
      _state.copyWith(
        busyRequestIds: Set<String>.of(_state.busyRequestIds)..add(request.id),
      ),
    );
    try {
      await _service.searchNow(id);
      if (_disposed) return;
      _set(
        _state.copyWith(
          requests: _replace(request.copyWith(message: '已请求 MoviePilot 立即搜索')),
        ),
      );
      unawaited(pollRound());
    } on MoviePilotException catch (error) {
      _warn(request.id, requestErrorMessage(error.code));
    } catch (_) {
      _warn(request.id, '立即搜索失败，请稍后重试');
    } finally {
      if (!_disposed) {
        _set(
          _state.copyWith(
            busyRequestIds: Set<String>.of(_state.busyRequestIds)
              ..remove(request.id),
          ),
        );
      }
    }
  }

  /// Cancels a request: deletes the MoviePilot subscription when it still has
  /// one, then removes the local record (plan S8 `cancel`).
  Future<void> cancel(MediaRequest request) async {
    if (_disposed) return;
    _set(
      _state.copyWith(
        busyRequestIds: Set<String>.of(_state.busyRequestIds)..add(request.id),
      ),
    );

    try {
      final id = request.subscribeId;
      if (id != null && !request.archived) {
        try {
          await _service.cancelSubscription(id);
        } on MoviePilotException catch (error) {
          // A 404 is already a no-op inside the repository; anything else
          // leaves the local record alone so the user can retry instead of
          // silently believing the subscription is gone.
          if (error.code != AppErrorCode.notFound) {
            _warn(request.id, requestErrorMessage(error.code));
            return;
          }
        } catch (_) {
          _warn(request.id, '取消失败，请稍后重试');
          return;
        }
      }

      if (_disposed) return;
      final remaining = <MediaRequest>[
        for (final item in _state.requests)
          if (item.id != request.id) item,
      ];
      _set(_state.copyWith(requests: remaining));
      await _persist(remaining);
    } finally {
      if (!_disposed) {
        _set(
          _state.copyWith(
            busyRequestIds: Set<String>.of(_state.busyRequestIds)
              ..remove(request.id),
          ),
        );
      }
    }
  }

  /// Re-runs one round on demand (pull to refresh).
  Future<void> refresh() => pollRound();

  /// Persists an already-authenticated connection and restarts polling
  /// (plan S10). Signing in is the settings dialog's job; this only re-verifies
  /// the token before storing it.
  Future<MoviePilotConnectionResult> saveConnection({
    required MoviePilotConfig config,
  }) async {
    try {
      // Verify before persisting: a token the instance rejects would otherwise
      // stop the poll on the next round with the same message, just later.
      final verified = await _service.testConnection(config);
      await _configStore.write(verified);
      _set(
        _state.copyWith(
          configured: true,
          configInvalid: false,
          unauthorizedToken: false,
          pollError: null,
        ),
      );
      await reconnect();
      return MoviePilotConnectionResult.success(verified);
    } on MoviePilotException catch (error) {
      return MoviePilotConnectionResult.failure(
        requestErrorMessage(error.code),
      );
    } catch (_) {
      return const MoviePilotConnectionResult.failure('连接失败，请稍后重试');
    }
  }

  /// Clears the stored connection; the records stay (plan S10).
  Future<void> clearConnection() async {
    await _configStore.delete();
    _stopBeat();
    if (_disposed) return;
    _set(
      _state.copyWith(
        configured: false,
        configInvalid: true,
        unauthorizedToken: false,
        polling: false,
        pollError: null,
      ),
    );
  }

  MediaRequest? _findExisting(MpMediaRef ref, MpMediaType? type, int season) {
    for (final request in _state.requests) {
      if (request.season != season) continue;
      if (type != null && request.type != type) continue;
      final wanted = ref.identityKey;
      final existing = request.ref.identityKey;
      if (wanted != null && existing != null) {
        if (wanted == existing) return request;
        continue;
      }
      if (request.title == ref.title && request.year == ref.year) {
        return request;
      }
    }
    return null;
  }

  MediaRequest _newRequest(
    MpMediaInfo media, {
    required int season,
    int? subscribeId,
    String? embyItemId,
  }) {
    return MediaRequest(
      id: _newId(),
      ref: media.ref,
      type: media.type!,
      title: media.title,
      year: media.year,
      season: season,
      subscribeId: subscribeId,
      poster: media.poster ?? '',
      createdAt: _clock(),
      embyItemId: embyItemId,
    );
  }

  Future<void> _addRequest(MediaRequest request) async {
    final updated = <MediaRequest>[request, ..._state.requests];
    _set(_state.copyWith(requests: updated, subscribeInFlight: false));
    await _persist(updated);
  }

  Future<void> _searchNowQuietly(int subscribeId) async {
    try {
      await _service.searchNow(subscribeId);
    } catch (_) {
      // Best effort: the subscription still searches on its own schedule.
    }
  }

  Future<void> _restore() async {
    try {
      final requests = await _requestStore.read();
      final snapshot = await _requestStore.readSnapshot();
      if (snapshot != null) _snapshot = snapshot;
      if (_disposed) return;
      _set(_state.copyWith(requests: requests, loaded: true));
    } catch (_) {
      // A broken store must not stop the page; an empty list is recoverable.
      if (_disposed) return;
      _set(_state.copyWith(requests: const <MediaRequest>[], loaded: true));
    }
  }

  Future<void> _persist(List<MediaRequest> requests) async {
    if (_disposed) return;
    try {
      await _requestStore.write(requests, snapshot: _snapshot);
    } catch (_) {
      // Persistence is a convenience; failing it must not break the UI.
    }
  }

  List<MediaRequest> _replace(MediaRequest updated) => <MediaRequest>[
    for (final request in _state.requests)
      if (request.id == updated.id) updated else request,
  ];

  void _warn(String requestId, String message) {
    if (_disposed) return;
    _set(
      _state.copyWith(
        requests: <MediaRequest>[
          for (final request in _state.requests)
            if (request.id == requestId)
              request.copyWith(message: message)
            else
              request,
        ],
      ),
    );
  }

  /// Serializes work so a heartbeat tick cannot interleave with an action.
  Future<void> _enqueue(Future<void> Function() task) {
    final next = _queue.then((_) => task());
    _queue = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  void _set(RequestState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopBeat();
    _notificationListeners.clear();
    super.dispose();
  }
}

/// User-facing copy for every MoviePilot error (plan §6: no raw exceptions).
String requestErrorMessage(AppErrorCode code) {
  return switch (code) {
    AppErrorCode.networkUnreachable => '无法连接 MoviePilot，请检查网络',
    AppErrorCode.tlsUntrusted => 'MoviePilot 证书不受信任',
    AppErrorCode.unauthorized => 'MoviePilot 登录已失效，请在设置中重新登录',
    AppErrorCode.forbidden => 'MoviePilot 账号权限不足，请在设置中更换账号',
    AppErrorCode.notFound => 'MoviePilot 中找不到该条目',
    AppErrorCode.notConfigured => '请先在设置中连接 MoviePilot',
    AppErrorCode.serverError => 'MoviePilot 返回异常，请稍后重试',
    _ => '操作失败，请稍后重试',
  };
}
