// Isolated native smoke surface: local synthetic video, in-memory settings,
// and a temporary download directory. No saved accounts or production API.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_player/app/playback_settings.dart';
import 'package:media_player/app/subtitle_style_settings.dart';
import 'package:media_player/core/network/endpoint_kind.dart';
import 'package:media_player/data/auth/api_session.dart';
import 'package:media_player/data/models/media_item.dart';
import 'package:media_player/data/models/resolved_endpoint.dart';
import 'package:media_player/data/models/server_profile.dart';
import 'package:media_player/data/offline/offline_repository.dart';
import 'package:media_player/data/playback/media_kit_engine.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/ui/offline_download_button.dart';
import 'package:media_player/features/offline/offline_page.dart';
import 'package:media_player/features/settings/mpv_settings_page.dart';
import 'package:media_player/ui/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final file = File('/tmp/mp-tt01-fixture.mp4');
  final bytes = await file.readAsBytes();
  final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  http.listen((request) async {
    request.response.headers.set('ETag', '"fixture-v1"');
    var start = 0;
    final range = request.headers.value('range');
    if (range != null) {
      start = int.parse(range.substring(6).split('-').first);
      request.response.statusCode = 206;
      request.response.headers.set(
        'Content-Range',
        'bytes $start-${bytes.length - 1}/${bytes.length}',
      );
    }
    request.response.contentLength = bytes.length - start;
    request.response.add(bytes.sublist(start));
    await request.response.close();
  });
  final session = _Session(http.port, bytes.length);
  final directory = await Directory.systemTemp.createTemp('mp-tt01-smoke-');
  final repository = OfflineRepository(directory: directory, session: session);
  await repository.initialize();
  final store = InMemoryKeyValueStore();
  const item = MediaItem(id: 'fixture', name: '离线播放验证 · 合成测试视频', type: 'Movie');
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          appBar: AppBar(title: const Text('MP-TT01 隔离验证')),
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text('仅本机合成夹具，不读取账号或真实媒体。'),
              OfflineDownloadButton(repository: repository, item: item),
              ListTile(
                title: const Text('下载与离线媒体'),
                onTap: () => context.push('/offline'),
              ),
              ListTile(
                title: const Text('MPV 播放器'),
                onTap: () => context.push('/mpv'),
              ),
              TextButton(
                onPressed: () async {
                  await http.close(force: true);
                },
                child: const Text('关闭测试服务器（模拟断网）'),
              ),
            ],
          ),
        ),
      ),
      GoRoute(
        path: '/offline',
        builder: (context, state) => OfflinePage(
          repository: repository,
          createEngine: MediaKitEngine.new,
        ),
      ),
      GoRoute(
        path: '/mpv',
        builder: (context, state) => const MpvSettingsPage(),
      ),
    ],
  );
  runApp(
    ProviderScope(
      overrides: [
        playbackSettingsStoreProvider.overrideWith((ref) async => store),
        subtitleStyleStoreProvider.overrideWith((ref) async => store),
      ],
      child: MaterialApp.router(
        theme: buildAppTheme(Brightness.light),
        routerConfig: router,
      ),
    ),
  );
}

class _Session implements ApiSession {
  _Session(this.port, this.length);
  final int port;
  final int length;
  @override
  ResolvedEndpoint get endpoint => ResolvedEndpoint(
    baseUrl: 'http://127.0.0.1:$port',
    kind: EndpointKind.lan,
    serverId: 'fixture',
    resolvedAt: DateTime.now(),
  );
  @override
  String get userId => 'fixture';
  @override
  String get accessToken => 'synthetic-not-a-secret';
  @override
  String get deviceId => 'fixture';
  @override
  ServerProfile? get profile => null;
  @override
  Future<Map<String, dynamic>> authorizedGet(Uri url) async =>
      url.path.contains('/Items/')
      ? {
          'Id': 'fixture',
          'Type': 'Movie',
          'CanDownload': true,
          'MediaSources': [
            {
              'Id': 'source',
              'Container': 'mp4',
              'Protocol': 'File',
              'Size': length,
            },
          ],
        }
      : {
          'Policy': {'EnableContentDownloading': true},
        };
  @override
  Future<Map<String, dynamic>> authorizedPost(Uri url, {Object? body}) =>
      throw UnimplementedError();
  @override
  Future<Map<String, dynamic>> authorizedDelete(Uri url) =>
      throw UnimplementedError();
}
