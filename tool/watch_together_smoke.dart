// Native isolation harness: synthetic local video, memory-only identities/store,
// loopback room service and two real libmpv players. No saved user data is read.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_player/app/providers.dart';
import 'package:media_player/app/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_player/core/network/endpoint_kind.dart';
import 'package:media_player/data/auth/api_session.dart';
import 'package:media_player/data/auth/auth_service.dart';
import 'package:media_player/data/library/library_service.dart';
import 'package:media_player/data/library/poster_cache.dart';
import 'package:media_player/data/models/auth_session.dart';
import 'package:media_player/data/models/items_page.dart';
import 'package:media_player/data/models/media_source.dart';
import 'package:media_player/data/models/media_item.dart';
import 'package:media_player/data/models/playback_plan.dart';
import 'package:media_player/data/models/resolved_endpoint.dart';
import 'package:media_player/data/models/server_profile.dart';
import 'package:media_player/data/playback/media_kit_engine.dart';
import 'package:media_player/data/playback/playback_service.dart';
import 'package:media_player/data/playback/session_reporter.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/data/watch_together/watch_together_client.dart';
import 'package:media_player/features/player/player_controller.dart';
import 'package:media_player/features/player/player_page.dart';
import 'package:media_player/features/watch_together/watch_together_page.dart';
import 'package:media_player/features/player/watch_playback_coordinator.dart';
import 'package:media_player/ui/theme/app_theme.dart';

// The room service deliberately remains a standalone deployable Dart package.
// ignore: avoid_relative_lib_imports
import '../services/watch_together/lib/watch_server.dart' as server;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final fixture = File('/tmp/mp-tt01-fixture.mp4');
  if (!await fixture.exists()) {
    throw StateError('Missing synthetic fixture /tmp/mp-tt01-fixture.mp4');
  }
  final service = server.WatchServer(verifier: _Verifier());
  await service.start();
  final clients = <WatchTogetherClient>[];
  for (final name in ['A', 'B']) {
    final client = WatchTogetherClient(
      session: _Session(name),
      store: InMemoryKeyValueStore(),
    );
    await client.initialize();
    await client.configure(service.baseUri);
    clients.add(client);
  }
  await clients[0].create(itemId: 'fixture', mediaSourceId: 'source');
  await clients[1].join(clients[0].room!.code);
  if (const bool.fromEnvironment('WATCH_ROOM_UI')) {
    runApp(
      _RoomHarness(
        service: service,
        clients: clients,
        video: fixture.uri.toString(),
      ),
    );
    return;
  }
  final peers = [
    for (var i = 0; i < clients.length; i++)
      _Peer(i == 0 ? 'A' : 'B', clients[i], fixture.uri.toString()),
  ];
  runApp(_Harness(service: service, peers: peers));
}

class _Peer {
  _Peer(this.name, this.client, String video) {
    engine = MediaKitEngine();
    controller = PlayerController(
      itemId: 'fixture',
      library: _Library(),
      playback: _Playback(video),
      engine: engine,
      reporter: reporter,
      store: InMemoryKeyValueStore(),
      preferredSourceId: 'source',
    );
    coordinator = WatchPlaybackCoordinator(
      client: client,
      controller: controller,
      roomId: client.room!.roomId,
      itemId: 'fixture',
    );
  }
  final String name;
  final WatchTogetherClient client;
  final _Reporter reporter = _Reporter();
  late final MediaKitEngine engine;
  late final PlayerController controller;
  late final WatchPlaybackCoordinator coordinator;
  bool foreground = true;
}

class _Harness extends StatefulWidget {
  const _Harness({required this.service, required this.peers});
  final server.WatchServer service;
  final List<_Peer> peers;
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final _events = <String>[];
  bool _busy = true;
  bool _loadedPaused = false;
  Timer? _refresh;
  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  Future<void> _load() async {
    try {
      await Future.wait(widget.peers.map((p) => p.controller.load()));
      await Future.wait(widget.peers.map((p) => p.coordinator.start()));
      if (widget.peers.any((p) => p.engine.snapshot.playing)) {
        throw StateError('player started before room play');
      }
      _loadedPaused = true;
      _record('PASS 双端加载保持暂停，等待房间开始');
    } catch (_) {
      _record('初始化失败');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && const bool.fromEnvironment('WATCH_SMOKE_AUTO')) {
      await _run(_automatic);
    }
  }

  void _record(String event) {
    final a = widget.peers[0].controller.state;
    final b = widget.peers[1].controller.state;
    final room = widget.peers[0].client.room;
    final line =
        '$event | A=${a.position.inMilliseconds}/${a.playing} '
        'B=${b.position.inMilliseconds}/${b.playing} '
        'room=${room?.playback.state} rev=${room?.playback.revision}';
    debugPrint('[MP-WT01 native] $line');
    if (mounted) setState(() => _events.insert(0, line));
  }

  Future<void> _until(bool Function() predicate, String description) async {
    final timer = Stopwatch()..start();
    while (!predicate()) {
      if (!mounted || timer.elapsed > const Duration(seconds: 12)) {
        throw StateError(description);
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await work();
    } catch (error) {
      _record('核验失败：${error.runtimeType}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _automatic() async {
    if (!_loadedPaused) throw StateError('initial paused-load check failed');
    final a = widget.peers[0];
    final b = widget.peers[1];
    a.coordinator.setForeground(true);
    b.coordinator.setForeground(true);
    a.foreground = b.foreground = true;
    await _until(
      () => widget.peers.every((p) => p.controller.state.ready),
      'ready',
    );
    await a.client.command('pause', positionMs: 0);
    await _until(
      () => b.client.room?.playback.state == 'paused',
      'initial pause',
    );
    await a.client.command('play');
    await _until(() {
      for (final peer in widget.peers) {
        final playback = peer.client.room?.playback;
        if (playback?.state == 'playing' &&
            peer.client.serverNowMs < playback!.serverTime &&
            peer.engine.snapshot.playing) {
          throw StateError('player started before server anchor');
        }
      }
      return widget.peers.every((p) => p.controller.state.playing);
    }, 'play at anchor');
    await Future<void>.delayed(const Duration(seconds: 2));
    _record('PASS 双端就绪后开始播放');
    await b.controller.togglePlayPause();
    await _until(
      () => widget.peers.every((p) => !p.controller.state.playing),
      'pause',
    );
    _record('PASS B 暂停同步到 A');
    await a.controller.seekTo(const Duration(seconds: 6));
    await _until(
      () => widget.peers.every(
        (p) =>
            (p.controller.state.position.inMilliseconds - 6000).abs() < 1000 &&
            !p.controller.state.playing,
      ),
      'paused seek',
    );
    _record('PASS 暂停拖动同步到双端');
    await a.client.command('play');
    await _until(
      () => widget.peers.every((p) => p.controller.state.playing),
      'resume',
    );
    b.foreground = false;
    b.coordinator.setForeground(false);
    await _until(
      () => !b.controller.state.playing && a.controller.state.playing,
      'away',
    );
    _record('PASS B 后台只暂停本机，A 继续');
    b.foreground = true;
    b.coordinator.setForeground(true);
    await _until(
      () => widget.peers.every((p) => p.controller.state.playing),
      'foreground',
    );
    await Future<void>.delayed(const Duration(milliseconds: 800));
    _record('PASS B 回到前台重新对齐');
    await a.client.command('pause');
    await _until(
      () => widget.peers.every((p) => !p.controller.state.playing),
      'final pause',
    );
    final delta = (a.controller.state.position - b.controller.state.position)
        .inMilliseconds
        .abs();
    if (delta > 1000) throw StateError('final drift $delta');
    _record('PASS 自动核验全部完成，暂停偏差 ${delta}ms');
  }

  @override
  void dispose() {
    _refresh?.cancel();
    for (final peer in widget.peers) {
      peer.coordinator.dispose();
      peer.controller.dispose();
      peer.client.dispose();
    }
    unawaited(widget.service.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: buildAppTheme(Brightness.light),
    home: Scaffold(
      appBar: AppBar(title: const Text('MP-WT01 双端原生隔离验证')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('合成视频 · 两个真实播放器 · 本机房间服务 · 不读取账号或保存数据'),
          ),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                for (final peer in widget.peers)
                  Expanded(child: _surface(peer)),
              ],
            ),
          ),
          Wrap(
            spacing: 12,
            children: [
              FilledButton(
                onPressed: _busy ? null : () => _run(_automatic),
                child: const Text('自动核验'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() => widget.peers[0].client.command('play')),
                child: const Text('A 全员播放'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() => widget.peers[1].client.command('pause')),
                child: const Text('B 全员暂停'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => widget.peers[0].controller.seekTo(
                          const Duration(seconds: 3),
                        ),
                      ),
                child: const Text('A 拖动到 3 秒'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(widget.peers[1].client.restore),
                child: const Text('B 重连房间'),
              ),
            ],
          ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: ListView(
              children: [for (final event in _events) Text(event)],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _surface(_Peer peer) {
    final state = peer.controller.state;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Text(
            '成员 ${peer.name} · ${state.position.inMilliseconds}ms · '
            '${state.playing ? "播放" : "暂停"} · '
            '${peer.client.connected ? "已连接" : "断线"}',
          ),
          Expanded(child: peer.engine.createSurface()),
          Text(state.error ?? peer.coordinator.notice ?? '同步正常'),
          Text(
            '上报 started=${peer.reporter.starts} progress=${peer.reporter.progresses}',
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () {
                    peer.foreground = !peer.foreground;
                    peer.coordinator.setForeground(peer.foreground);
                    setState(() {});
                  },
            child: Text(
              peer.foreground ? '${peer.name} 模拟后台' : '${peer.name} 返回前台',
            ),
          ),
        ],
      ),
    );
  }
}

class _Verifier implements server.WatchAuthVerifier {
  @override
  Future<server.WatchIdentity> verify({
    required String token,
    required String userId,
    required String serverId,
  }) async {
    if (!['A', 'B'].contains(userId) ||
        token != 'synthetic-$userId' ||
        serverId != 'smoke') {
      throw const server.WatchFailure('UNAUTHORIZED', '隔离身份不匹配', 401);
    }
    return server.WatchIdentity(
      userId: userId,
      serverId: serverId,
      token: token,
      name: '本机成员 $userId',
    );
  }

  @override
  Future<server.WatchMedia> media(
    server.WatchIdentity identity,
    String itemId,
    String? mediaSourceId,
  ) async => const server.WatchMedia(
    itemId: 'fixture',
    mediaSourceId: 'source',
    title: '合成测试视频',
    type: 'Movie',
    runTimeMs: 12000,
  );
}

class _Session implements ApiSession {
  _Session(this.name);
  final String name;
  @override
  String get userId => name;
  @override
  String get accessToken => 'synthetic-$name';
  @override
  String get deviceId => 'smoke-$name';
  @override
  ServerProfile? get profile => null;
  @override
  ResolvedEndpoint get endpoint => ResolvedEndpoint(
    baseUrl: 'http://127.0.0.1',
    kind: EndpointKind.lan,
    serverId: 'smoke',
    resolvedAt: DateTime.now(),
  );
  @override
  Future<Map<String, dynamic>> authorizedGet(Uri url) async =>
      <String, dynamic>{};
  @override
  Future<Map<String, dynamic>> authorizedPost(Uri url, {Object? body}) async =>
      <String, dynamic>{};
  @override
  Future<Map<String, dynamic>> authorizedDelete(Uri url) async =>
      <String, dynamic>{};
}

class _Library implements LibraryService {
  static const movie = MediaItem(
    id: 'fixture',
    name: '合成测试视频',
    type: 'Movie',
    runTimeTicks: 120000000,
    mediaSources: [
      MediaSource(
        id: 'source',
        container: 'mp4',
        bitrate: 1000000,
        supportsDirectPlay: true,
        supportsDirectStream: true,
        name: '合成 H.264 / AAC',
      ),
    ],
  );
  ItemsPage get _page =>
      const ItemsPage(items: [movie], totalRecordCount: 1, startIndex: 0);
  @override
  Future<MediaItem> item(String itemId) async => movie;
  @override
  Future<ItemsPage> resumable({int limit = 20}) async => _page;
  @override
  Future<ItemsPage> search(
    String term, {
    String types = 'Movie,Series',
    int limit = 60,
  }) async => _page;
  @override
  Future<ItemsPage> items(
    String viewId, {
    int startIndex = 0,
    int limit = 60,
    String sortBy = 'SortName',
    String sortOrder = 'Ascending',
    String? genreId,
    String? genre,
    int? year,
    String? tag,
    String? includeItemTypes,
    String? filters,
    String? studioId,
    String? studio,
  }) async => _page;
  @override
  Uri? imageUrl(
    String itemId, {
    String? tag,
    int? maxWidth,
    String type = 'Primary',
    int? index,
  }) => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Playback implements PlaybackService {
  _Playback(this.video);
  final String video;
  @override
  Future<PlaybackPlan> resolve(
    String itemId, {
    Duration startAt = Duration.zero,
    String? mediaSourceId,
  }) async => PlaybackPlan(
    itemId: itemId,
    mode: PlaybackMode.direct,
    endpointKind: EndpointKind.lan,
    url: video,
    headers: const {},
    mediaSourceId: 'source',
    playSessionId: 'smoke',
    startAt: startAt,
    videoDirect: true,
  );
  @override
  Future<PlaybackPlan> confirmDirect(PlaybackPlan plan) async => plan;
}

class _Reporter implements PlaybackReporter {
  int starts = 0, progresses = 0;
  @override
  Future<void> started(
    PlaybackPlan plan,
    Duration initialPosition, {
    required Duration Function() position,
  }) async {
    starts++;
  }

  @override
  Future<void> progress(
    PlaybackPlan plan,
    Duration position, {
    required bool paused,
  }) async {
    progresses++;
  }

  @override
  Future<void> stopped(PlaybackPlan plan, Duration position) async {}
}

/// Uses the production room page and player route with a memory-only graph.
class _RoomHarness extends StatefulWidget {
  const _RoomHarness({
    required this.service,
    required this.clients,
    required this.video,
  });
  final server.WatchServer service;
  final List<WatchTogetherClient> clients;
  final String video;
  @override
  State<_RoomHarness> createState() => _RoomHarnessState();
}

class _RoomHarnessState extends State<_RoomHarness> {
  late final AppServices _services;
  late final GoRouter _router;
  @override
  void initState() {
    super.initState();
    _services = AppServices(
      auth: _Auth(),
      library: _Library(),
      posters: _Posters(),
      playback: _Playback(widget.video),
      createEngine: MediaKitEngine.new,
      createReporter: _Reporter.new,
      store: InMemoryKeyValueStore(),
      watchTogether: widget.clients[0],
    );
    _router = GoRouter(
      initialLocation: '/watch-together',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            appBar: AppBar(title: const Text('MP-WT01 房间界面隔离验证')),
            body: Center(
              child: FilledButton(
                onPressed: () => context.push('/watch-together'),
                child: const Text('打开真实一起看页面'),
              ),
            ),
          ),
          routes: [
            GoRoute(
              path: 'watch-together',
              builder: (context, state) => const WatchTogetherPage(),
            ),
            GoRoute(
              path: 'player/:itemId',
              builder: (context, state) => PlayerPage(
                key: ValueKey(state.uri.toString()),
                itemId: state.pathParameters['itemId']!,
                preferredSourceId: state.uri.queryParameters['source'],
                watchRoomId: state.uri.queryParameters['room'],
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    for (final client in widget.clients) {
      client.dispose();
    }
    unawaited(widget.service.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [bootstrapProvider.overrideWith((ref) async => _services)],
    child: MaterialApp.router(
      theme: buildAppTheme(Brightness.light),
      routerConfig: _router,
    ),
  );
}

class _Auth implements AuthService {
  @override
  AuthSession get current => const AuthSession(
    userId: 'A',
    userName: '本机成员 A',
    accessToken: 'synthetic-A',
    deviceId: 'smoke-A',
  );
  @override
  Stream<AuthSession?> get session => const Stream.empty();
  @override
  Future<AuthSession?> restore() async => current;
  @override
  Future<ServerProfile?> lastProfile() async => null;
  @override
  Future<void> logout() async {}
  @override
  Future<void> handleUnauthorized() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Posters implements PosterCache {
  @override
  Future<Uint8List> load(
    String itemId,
    Uri url, {
    String? tag,
    int? maxWidth,
    String variant = '',
  }) async => Uint8List(0);
  @override
  Future<int> sizeBytes() async => 0;
  @override
  Future<void> clear() async {}
}
