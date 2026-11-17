import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/offline/offline_entry.dart';
import 'package:media_player/data/offline/offline_repository.dart';
import 'package:media_player/data/playback/mpv_config.dart';
import 'package:media_player/data/playback/playback_engine.dart';
import 'package:media_player/data/playback/playback_settings.dart';
import 'package:media_player/features/offline/offline_page.dart';

import '../../data/offline/offline_test_session.dart';
import '../../support/fake_playback_engine.dart';

class QualityEngine extends FakePlaybackEngine implements MpvConfigEngine {
  final configs = <Map<String, String>>[];
  bool failQuality = false;
  @override
  Future<void> applyMpvConfig(Map<String, String> properties) async {
    configs.add(properties);
    if (failQuality && configs.length == 1) {
      throw StateError('unsupported option');
    }
  }
}

void main() {
  late Directory directory;
  late OfflineRepository repository;
  late OfflineTestSession session;
  late QualityEngine engine;
  final id = List.filled(64, 'a').join();
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('offline-widget-');
    final entry = OfflineEntry(
      id: id,
      serverId: 'server',
      userId: 'original-user',
      itemId: 'movie',
      sourceId: 'source',
      title: '离线测试片',
      serverName: '原服务器',
      status: OfflineStatus.complete,
      received: 4,
      total: 4,
    );
    await File('${directory.path}/${entry.fileName}')
        .writeAsBytes([1, 2, 3, 4]);
    await File('${directory.path}/index.json')
        .writeAsString(jsonEncode([entry.toJson()]));
    session = OfflineTestSession('http://127.0.0.1')..endpoint = null;
    repository = OfflineRepository(directory: directory, session: session);
    await repository.initialize();
    engine = QualityEngine();
  });
  tearDown(() async {
    repository.dispose();
    await directory.delete(recursive: true);
  });

  testWidgets('local list opens without login, delete requires confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OfflinePage(repository: repository, createEngine: () => engine),
      ),
    );
    expect(find.text('离线测试片'), findsOneWidget);
    expect(find.text('原服务器 · 账号 original-user'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除离线副本？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(repository.entries, hasLength(1));
    expect(session.jsonCalls, 0);
  });

  testWidgets(
    'offline engine plan uses local URI and applies picture preferences',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OfflinePlayerPage(
            title: '离线测试片',
            fileUri: 'file:///local/movie.mkv',
            createEngine: () => engine,
            settings: const PlaybackSettings(
              hwdecEnabled: false,
              forceStereo: false,
              mpvQualityPreset: MpvQualityPreset.cinema,
              mpvCustomConfig: 'brightness=5',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(engine.openedPlans.single.url, 'file:///local/movie.mkv');
      expect(engine.openedPlans.single.headers, isEmpty);
      expect(engine.hwdecToggles, [false]);
      expect(engine.forceStereoToggles, [false]);
      expect(engine.advancedApplyVo, [false]);
      expect(engine.configs.single['brightness'], '5');
      expect(session.jsonCalls, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(engine.disposeCalls, 1);
    },
  );

  testWidgets(
    'invalid picture configuration falls back without stopping playback',
    (tester) async {
      engine.failQuality = true;
      await tester.pumpWidget(
        MaterialApp(
          home: OfflinePlayerPage(
            title: '离线测试片',
            fileUri: 'file:///local/movie.mkv',
            createEngine: () => engine,
            settings: const PlaybackSettings(
              mpvQualityPreset: MpvQualityPreset.animation,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(engine.configs, hasLength(2));
      expect(engine.configs.last, MpvConfig.defaults);
      expect(find.text('画质配置无法应用，已恢复默认；请检查 MPV 设置'), findsOneWidget);
      expect(find.text('本地媒体播放失败'), findsNothing);
    },
  );
}
