import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/app.dart';
import 'package:media_player/app/providers.dart';
import 'package:media_player/app/router.dart';
import 'package:media_player/app/services.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/emby_exception.dart';
import 'package:media_player/core/network/endpoint_kind.dart';
import 'package:media_player/core/router/app_routes.dart';
import 'package:media_player/data/auth/auth_service.dart';
import 'package:media_player/data/models/auth_session.dart';
import 'package:media_player/data/models/live_tv_channel.dart';
import 'package:media_player/data/models/media_item.dart';
import 'package:media_player/data/models/server_profile.dart';

import '../support/fake_library_service.dart';
import '../support/fake_live_tv_service.dart';
import '../support/fake_playback_engine.dart';
import '../support/fake_playback_reporter.dart';
import '../support/fake_playback_service.dart';
import '../support/fake_poster_cache.dart';

class StaticAuth implements AuthService {
  @override
  AuthSession? get current => const AuthSession(
    userId: 'u1',
    userName: 'test',
    accessToken: 'token',
    deviceId: 'd1',
  );

  @override
  Stream<AuthSession?> get session => const Stream<AuthSession?>.empty();

  @override
  Future<AuthSession?> restore() async => current;

  @override
  Future<ServerProfile?> lastProfile() async => null;

  @override
  Future<AuthSession> login({
    required String username,
    required String password,
    required ServerProfile profile,
  }) => throw UnimplementedError();

  @override
  Future<ServerProfile> adoptAddress({
    required ServerProfile profile,
    required EndpointKind kind,
    required String rawUrl,
  }) => throw UnimplementedError();

  @override
  Future<void> logout() async {}

  @override
  Future<void> handleUnauthorized() async {}
}

void main() {
  late FakeLibraryService library;
  late FakeLiveTvService liveTv;
  late FakePlaybackService playback;
  late FakePlaybackEngine engine;

  setUp(() {
    // The player fetches the channel item before negotiating, so the library
    // double must know the channel id (type TvChannel, not Series).
    library = FakeLibraryService(
      itemsById: <String, MediaItem>{
        'ch-1': const MediaItem(id: 'ch-1', name: 'CCTV-1', type: 'TvChannel'),
      },
    );
    liveTv = FakeLiveTvService(
      channelResults: <LiveTvChannel>[
        fakeChannel('ch-1', name: 'CCTV-1', number: '1.1'),
      ],
    );
    playback = FakePlaybackService();
    engine = FakePlaybackEngine();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bootstrapProvider.overrideWith(
            (ref) async => AppServices(
              auth: StaticAuth(),
              library: library,
              posters: FakePosterCache(),
              playback: playback,
              createEngine: () => engine,
              createReporter: FakePlaybackReporter.new,
              liveTv: liveTv,
            ),
          ),
        ],
        child: const MediaPlayerApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpLiveTv(WidgetTester tester) async {
    await pumpApp(tester);
    ProviderScope.containerOf(tester.element(find.byType(MediaPlayerApp)))
        .read(appRouterProvider)
        .go(AppRoutes.liveTv);
    await tester.pumpAndSettle();
  }

  testWidgets('the settings media entry opens the live page', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const Key('home-settings')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-live-tv')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('settings-live-tv')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('livetv-page')), findsOneWidget);
    expect(liveTv.channelCalls, 1);
  });

  testWidgets('the channel list renders name, number, program and progress', (
    tester,
  ) async {
    await pumpLiveTv(tester);

    expect(find.byKey(const Key('livetv-channel-ch-1')), findsOneWidget);
    expect(find.text('CCTV-1'), findsOneWidget);
    expect(find.text('1.1'), findsOneWidget);
    expect(find.text('Program ch-1'), findsOneWidget);
    // The airing program spans now, so its progress bar is present.
    expect(find.byKey(const Key('livetv-progress-ch-1')), findsOneWidget);
  });

  testWidgets('a channel without guide data omits the progress bar', (
    tester,
  ) async {
    liveTv.channelResults = <LiveTvChannel>[
      fakeChannel('ch-2', name: 'No Guide', withProgram: false),
    ];
    await pumpLiveTv(tester);

    expect(find.text('No Guide'), findsOneWidget);
    expect(find.text('暂无节目信息'), findsOneWidget);
    expect(find.byKey(const Key('livetv-progress-ch-2')), findsNothing);
  });

  testWidgets('tapping a channel opens the player for that channel id', (
    tester,
  ) async {
    await pumpLiveTv(tester);

    await tester.tap(find.byKey(const Key('livetv-channel-ch-1')));
    await tester.pumpAndSettle();
    // Past the §10.9 f verdict probe so no timer outlives the test.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(playback.resolveItemIds, contains('ch-1'));
    expect(find.byKey(const Key('player-play-toggle')), findsOneWidget);
  });

  testWidgets('an empty channel list shows the empty state', (tester) async {
    liveTv.channelResults = const <LiveTvChannel>[];
    await pumpLiveTv(tester);

    expect(find.text('服务器没有可用的直播频道'), findsOneWidget);
  });

  testWidgets('a load failure shows the error state with a retry', (
    tester,
  ) async {
    liveTv.failure = EmbyException(AppErrorCode.serverError);
    await pumpLiveTv(tester);

    expect(find.text('加载失败，请稍后重试'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    // Retry clears the failure and reloads the list.
    liveTv.failure = null;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('livetv-channel-ch-1')), findsOneWidget);
  });

  testWidgets('a 404 (Live TV disabled) maps to dedicated copy', (
    tester,
  ) async {
    liveTv.failure = EmbyException(AppErrorCode.notFound);
    await pumpLiveTv(tester);

    expect(find.text('服务器未开启直播功能'), findsOneWidget);
  });
}
