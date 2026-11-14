import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/moviepilot_providers.dart';
import 'package:media_player/app/providers.dart';
import 'package:media_player/app/services.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/moviepilot_exception.dart';
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
import '../support/fake_poster_cache.dart';

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

  Widget scoped(Widget child) => ProviderScope(
    overrides: [
      bootstrapProvider.overrideWith(
        (ref) async => AppServices(
          auth: _NoAuth(),
          library: FakeLibraryService(),
          posters: FakePosterCache(),
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
    child: child,
  );

  Future<void> pumpDialog(
    WidgetTester tester, {
    MoviePilotConfig? initial,
  }) async {
    // The dialog is tall; give the surface room so its actions stay tappable.
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      scoped(
        MaterialApp(
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
    String username = 'admin',
    String password = 'secret',
  }) async {
    await tester.enterText(find.byKey(const Key('moviepilot-url')), url);
    await tester.enterText(
      find.byKey(const Key('moviepilot-username')),
      username,
    );
    await tester.enterText(
      find.byKey(const Key('moviepilot-password')),
      password,
    );
    await tester.pump();
  }

  testWidgets('a valid login is verified, persisted and closes', (
    tester,
  ) async {
    await pumpDialog(tester);

    await fill(tester, url: 'nas.local:3002');
    await tester.tap(find.byKey(const Key('moviepilot-save')));
    await tester.pumpAndSettle();

    expect(service.logins, hasLength(1));
    expect(service.logins.single.baseUrl, 'http://nas.local:3002');
    expect(service.logins.single.username, 'admin');
    expect(service.logins.single.password, 'secret');
    expect(service.logins.single.otp, isNull);
    expect(service.connectionTests, hasLength(1));
    final saved = await MoviePilotConfigStore(store).read();
    expect(saved, isNotNull);
    expect(saved!.username, 'admin');
    expect(saved.accessToken, 'token-admin');
    // The password is a one-time input, never a stored credential.
    final raw = await store.read(MoviePilotConfigStore.key);
    expect(raw, isNot(contains('secret')));
    expect(raw, isNot(contains('password')));
    // Closing on success is the point of the dialog.
    expect(find.byType(MoviePilotConfigDialog), findsNothing);
  });

  testWidgets('an invalid address is rejected before any request', (
    tester,
  ) async {
    await pumpDialog(tester);

    await fill(tester, url: 'ftp://nas');
    await tester.tap(find.byKey(const Key('moviepilot-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('moviepilot-error')), findsOneWidget);
    expect(find.textContaining('地址无效'), findsOneWidget);
    expect(service.logins, isEmpty);
    expect(service.connectionTests, isEmpty);
    // The dialog stays open so the user can fix the typo.
    expect(find.byType(MoviePilotConfigDialog), findsOneWidget);
  });

  testWidgets('an empty username is rejected', (tester) async {
    await pumpDialog(tester);

    await fill(tester, url: 'nas.local', username: '   ');
    await tester.tap(find.byKey(const Key('moviepilot-save')));
    await tester.pumpAndSettle();

    expect(find.text('用户名不能为空'), findsOneWidget);
    expect(service.logins, isEmpty);
  });

  testWidgets('an empty password is rejected', (tester) async {
    await pumpDialog(tester);

    await fill(tester, url: 'nas.local', password: '');
    await tester.tap(find.byKey(const Key('moviepilot-save')));
    await tester.pumpAndSettle();

    expect(find.text('密码不能为空'), findsOneWidget);
    expect(service.logins, isEmpty);
  });

  testWidgets('wrong credentials show why and store nothing', (tester) async {
    service.loginFailure = mpFailure(AppErrorCode.unauthorized);
    await pumpDialog(tester);

    await fill(tester, url: 'nas.local', password: 'wrong');
    await tester.tap(find.byKey(const Key('moviepilot-save')));
    await tester.pumpAndSettle();

    expect(find.textContaining('用户名或密码错误'), findsOneWidget);
    expect(await MoviePilotConfigStore(store).read(), isNull);
    expect(find.byType(MoviePilotConfigDialog), findsOneWidget);
  });

  testWidgets('MFA asks for the code and retries the login', (tester) async {
    service.loginFailure = MoviePilotException(
      AppErrorCode.unauthorized,
      mfaRequired: true,
    );
    await pumpDialog(tester);

    await fill(tester, url: 'nas.local');
    await tester.tap(find.byKey(const Key('moviepilot-save')));
    await tester.pumpAndSettle();

    // The password was accepted; the dialog now wants the one-time code.
    expect(find.byKey(const Key('moviepilot-otp')), findsOneWidget);
    expect(find.textContaining('二次验证'), findsWidgets);
    expect(await MoviePilotConfigStore(store).read(), isNull);

    service.loginFailure = null;
    await tester.enterText(find.byKey(const Key('moviepilot-otp')), '123456');
    await tester.tap(find.byKey(const Key('moviepilot-save')));
    await tester.pumpAndSettle();

    expect(service.logins, hasLength(2));
    expect(service.logins.last.otp, '123456');
    expect(await MoviePilotConfigStore(store).read(), isNotNull);
    expect(find.byType(MoviePilotConfigDialog), findsNothing);
  });

  testWidgets('the password is obscured until the eye is tapped', (
    tester,
  ) async {
    await pumpDialog(tester);

    final field = tester.widget<TextField>(
      find.byKey(const Key('moviepilot-password')),
    );
    expect(field.obscureText, isTrue);

    await tester.tap(find.byKey(const Key('moviepilot-password-visibility')));
    await tester.pump();

    final revealed = tester.widget<TextField>(
      find.byKey(const Key('moviepilot-password')),
    );
    expect(revealed.obscureText, isFalse);
  });

  testWidgets('an existing connection is prefilled and can be cleared', (
    tester,
  ) async {
    await MoviePilotConfigStore(store).write(
      const MoviePilotConfig(
        baseUrl: 'http://nas:3002',
        username: 'admin',
        accessToken: 'stored',
      ),
    );
    await pumpDialog(
      tester,
      initial: const MoviePilotConfig(
        baseUrl: 'http://nas:3002',
        username: 'admin',
        accessToken: 'stored',
      ),
    );

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('moviepilot-url')))
          .controller!
          .text,
      'http://nas:3002',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('moviepilot-username')))
          .controller!
          .text,
      'admin',
    );
    // The stored token is never put back into a field, and neither is a
    // password.
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('moviepilot-password')))
          .controller!
          .text,
      isEmpty,
    );

    await tester.tap(find.byKey(const Key('moviepilot-clear')));
    await tester.pumpAndSettle();

    expect(await MoviePilotConfigStore(store).read(), isNull);
    expect(find.byType(MoviePilotConfigDialog), findsNothing);
  });

  testWidgets('the settings tile announces an expired login', (tester) async {
    await MoviePilotConfigStore(store).write(
      MoviePilotConfig(
        baseUrl: 'http://nas:3002',
        username: 'admin',
        accessToken: 'stored',
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
      ),
    );

    await tester.pumpWidget(
      scoped(const MaterialApp(home: Scaffold(body: MoviePilotSettingsTile()))),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('登录已过期'), findsOneWidget);
    expect(find.textContaining('admin'), findsOneWidget);
  });
}
