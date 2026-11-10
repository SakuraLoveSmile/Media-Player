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
import 'package:media_player/data/storage/request_store.dart';

import '../support/fake_library_service.dart';
import '../support/fake_moviepilot_service.dart';
import '../support/fake_playback_engine.dart';
import '../support/fake_playback_reporter.dart';
import '../support/fake_playback_service.dart';

/// Auth is never touched by the request feature; the graph only needs a stub.
class _NoAuth implements AuthService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A service graph whose only real part is the in-memory store.
AppServices buildServices(InMemoryKeyValueStore store) {
  return AppServices(
    auth: _NoAuth(),
    library: FakeLibraryService(),
    playback: FakePlaybackService(),
    createEngine: FakePlaybackEngine.new,
    createReporter: FakePlaybackReporter.new,
    store: store,
    moviePilotConfigStore: MoviePilotConfigStore(store),
  );
}

void main() {
  late InMemoryKeyValueStore store;

  setUp(() => store = InMemoryKeyValueStore());

  ProviderContainer container({MoviePilotService? service}) {
    final result = ProviderContainer(
      overrides: [
        bootstrapProvider.overrideWith((Ref ref) async => buildServices(store)),
        if (service != null)
          moviePilotServiceProvider.overrideWith((Ref ref) async => service),
      ],
    );
    addTearDown(result.dispose);
    return result;
  }

  group('providers', () {
    test('the config store comes from the service graph', () async {
      final c = container();

      expect(await c.read(moviePilotConfigStoreProvider.future), isNotNull);
      expect(await c.read(requestStoreProvider.future), isNotNull);
    });

    test('the request store is backed by the app-wide store', () async {
      final c = container();
      final requestStore = await c.read(requestStoreProvider.future);

      await requestStore!.write(const []);

      expect(await store.read(RequestStore.key), isNotNull);
    });

    test('the repository is built once and reused', () async {
      final c = container();

      final first = await c.read(moviePilotServiceProvider.future);
      final second = await c.read(moviePilotServiceProvider.future);

      expect(first, isNotNull);
      expect(identical(first, second), isTrue);
    });

    test('no stored connection reads as null', () async {
      final c = container();

      expect(await c.read(moviePilotConfigProvider.future), isNull);
    });

    test('a stored connection is read back', () async {
      await MoviePilotConfigStore(store).write(
        const MoviePilotConfig(
          baseUrl: 'http://nas:3002',
          username: 'admin',
          accessToken: 't',
        ),
      );
      final c = container();

      final config = await c.read(moviePilotConfigProvider.future);

      expect(config!.baseUrl, 'http://nas:3002');
    });
  });

  group('MoviePilotSettings', () {
    test('login verifies before persisting and updates the state', () async {
      final service = FakeMoviePilotService();
      final c = container(service: service);
      await c.read(moviePilotSettingsProvider.future);

      final saved = await c
          .read(moviePilotSettingsProvider.notifier)
          .login(
            baseUrl: 'http://nas:3002',
            username: 'admin',
            password: 'pw',
          );

      expect(saved.baseUrl, 'http://nas:3002');
      expect(saved.username, 'admin');
      expect(service.logins.single.username, 'admin');
      expect(service.logins.single.password, 'pw');
      expect(service.logins.single.otp, isNull);
      expect(service.connectionTests, hasLength(1));
      expect(service.connectionTests.single.accessToken, 'token-admin');
      expect(await MoviePilotConfigStore(store).read(), isNotNull);
      expect(c.read(moviePilotSettingsProvider).value, isNotNull);
    });

    test('a rejected login is not persisted', () async {
      final service = FakeMoviePilotService()
        ..loginFailure = mpFailure(AppErrorCode.unauthorized);
      final c = container(service: service);
      await c.read(moviePilotSettingsProvider.future);

      await expectLater(
        c
            .read(moviePilotSettingsProvider.notifier)
            .login(
              baseUrl: 'http://nas:3002',
              username: 'admin',
              password: 'wrong',
            ),
        throwsA(anything),
      );

      expect(await MoviePilotConfigStore(store).read(), isNull);
      expect(service.connectionTests, isEmpty);
    });

    test('a token the server rejects after login is not persisted', () async {
      final service = FakeMoviePilotService()
        ..testFailure = mpFailure(AppErrorCode.forbidden);
      final c = container(service: service);
      await c.read(moviePilotSettingsProvider.future);

      await expectLater(
        c
            .read(moviePilotSettingsProvider.notifier)
            .login(
              baseUrl: 'http://nas:3002',
              username: 'admin',
              password: 'pw',
            ),
        throwsA(anything),
      );

      expect(service.connectionTests, hasLength(1));
      expect(await MoviePilotConfigStore(store).read(), isNull);
    });

    test('clear removes the connection but keeps the requests', () async {
      final service = FakeMoviePilotService();
      final c = container(service: service);
      await c.read(moviePilotSettingsProvider.future);
      await c
          .read(moviePilotSettingsProvider.notifier)
          .login(
            baseUrl: 'http://nas:3002',
            username: 'admin',
            password: 'pw',
          );
      final requestStore = await c.read(requestStoreProvider.future);
      await requestStore!.write(const []);

      await c.read(moviePilotSettingsProvider.notifier).clear();

      expect(await MoviePilotConfigStore(store).read(), isNull);
      expect(await store.read(RequestStore.key), isNotNull);
    });
  });
}
