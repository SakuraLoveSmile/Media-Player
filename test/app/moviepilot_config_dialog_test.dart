import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/moviepilot_providers.dart';
import 'package:media_player/app/providers.dart';
import 'package:media_player/app/services.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/data/auth/auth_service.dart';
import 'package:media_player/data/moviepilot/models/moviepilot_config.dart';
import 'package:media_player/data/moviepilot/moviepilot_service.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/data/storage/moviepilot_config_store.dart';
import 'package:media_player/features/settings/moviepilot_config_dialog.dart';

import '../support/fake_library_service.dart';
import '../support/fake_moviepilot_service.dart';
import '../support/fake_playback_engine.dart';
import '../support/fake_playback_reporter.dart';
import '../support/fake_playback_service.dart';

class _NoAuth implements AuthService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late InMemoryKeyValueStore store;
  late FakeMoviePilotService service;

  setUp(() {
    store = InMemoryKeyValueStore();
    service = FakeMoviePilotService();
  });

  Future<void> pumpDialog(
    WidgetTester tester, {
    MoviePilotConfig? initial,
  }) async {
    // The dialog is tall; give the surface room so its actions stay tappable.
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bootstrapProvider.overrideWith(
            (ref) async => AppServices(
              auth: _NoAuth(),
              library: FakeLibraryService(),
              playback: FakePlaybackService(),
              createEngine: FakePlaybackEngine.new,
              createReporter: FakePlaybackReporter.new,
              store: store,
              moviePilotConfigStore: MoviePilotConfigStore(store),
            ),
          ),
          moviePilotServiceProvider.overrideWith(
            (ref) async => service as MoviePilotService,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => Center(
                child: ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => MoviePilotConfigDialog(initial: initial),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> fill(
    WidgetTester tester, {
    required String url,
    required String token,
  }) async {
    await tester.enterText(find.byKey(const Key('moviepilot-url')), url);
    await tester.enterText(find.byKey(const Key('moviepilot-token')), token);
    await tester.pump();
  }

  testWidgets('a valid connection is verified, persisted and closes', (
    tester,
  ) async {
    await pumpDialog(tester);

    await fill(tester, url: 'nas.local:3002', token: 'secret');
    await tester.tap(find.byKey(const Key('moviepilot-save')));
    await tester.pumpAndSettle();

    expect(service.connectionTests, hasLength(1));
    expect(service.connectionTests.single.baseUrl, 'http://nas.local:3002');
    final saved = await MoviePilotConfigStore(store).read();
    expect(saved, isNotNull);
    expect(saved!.apiToken, 'secret');
    // Closing on success is the point of the dialog.
    expect(find.byType(MoviePilotConfigDialog), findsNothing);
  });

  testWidgets('an invalid address is rejected before any request', (
    tester,
  ) async {
    await pumpDialog(tester);

    await fill(tester, url: 'ftp://nas', token: 'secret');
    await tester.tap(find.byKey(const Key('moviepilot-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('moviepilot-error')), findsOneWidget);
    expect(find.textContaining('地址无效'), findsOneWidget);
    expect(service.connectionTests, isEmpty);
    // The dialog stays open so the user can fix the typo.
    expect(find.byType(MoviePilotConfigDialog), findsOneWidget);
  });

  testWidgets('an empty token is rejected', (tester) async {
    await pumpDialog(tester);

    await fill(tester, url: 'nas.local', token: '   ');
    await tester.tap(find.byKey(const Key('moviepilot-save')));
    await tester.pumpAndSettle();

    expect(find.text('API_TOKEN 不能为空'), findsOneWidget);
    expect(service.connectionTests, isEmpty);
  });

  testWidgets('a rejected token shows why and stores nothing', (tester) async {
    service.testFailure = mpFailure(AppErrorCode.unauthorized);
    await pumpDialog(tester);

    await fill(tester, url: 'nas.local', token: 'wrong');
    await tester.tap(find.byKey(const Key('moviepilot-save')));
    await tester.pumpAndSettle();

    expect(find.textContaining('API_TOKEN 无效'), findsOneWidget);
    expect(await MoviePilotConfigStore(store).read(), isNull);
    expect(find.byType(MoviePilotConfigDialog), findsOneWidget);
  });

  testWidgets('an unreachable host shows the network reason', (tester) async {
    service.testFailure = mpFailure(AppErrorCode.networkUnreachable);
    await pumpDialog(tester);

    await fill(tester, url: 'nas.local', token: 'token');
    await tester.tap(find.byKey(const Key('moviepilot-save')));
    await tester.pumpAndSettle();

    expect(find.textContaining('无法连接'), findsOneWidget);
  });

  testWidgets('the token is obscured until the eye is tapped', (tester) async {
    await pumpDialog(tester);

    final field = tester.widget<TextField>(
      find.byKey(const Key('moviepilot-token')),
    );
    expect(field.obscureText, isTrue);

    await tester.tap(find.byKey(const Key('moviepilot-token-visibility')));
    await tester.pump();

    final revealed = tester.widget<TextField>(
      find.byKey(const Key('moviepilot-token')),
    );
    expect(revealed.obscureText, isFalse);
  });

  testWidgets('an existing connection is prefilled and can be cleared', (
    tester,
  ) async {
    await MoviePilotConfigStore(store).write(
      const MoviePilotConfig(baseUrl: 'http://nas:3002', apiToken: 'stored'),
    );
    await pumpDialog(
      tester,
      initial: const MoviePilotConfig(
        baseUrl: 'http://nas:3002',
        apiToken: 'stored',
      ),
    );

    expect(
      tester.widget<TextField>(find.byKey(const Key('moviepilot-url'))).controller!.text,
      'http://nas:3002',
    );

    await tester.tap(find.byKey(const Key('moviepilot-clear')));
    await tester.pumpAndSettle();

    expect(await MoviePilotConfigStore(store).read(), isNull);
    expect(find.byType(MoviePilotConfigDialog), findsNothing);
  });
}
