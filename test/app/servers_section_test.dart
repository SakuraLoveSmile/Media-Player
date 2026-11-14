import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/app.dart';
import 'package:media_player/app/feedback_config.dart';
import 'package:media_player/app/providers.dart';
import 'package:media_player/app/services.dart';
import 'package:media_player/app/router.dart';
import 'package:media_player/app/update_providers.dart';
import 'package:media_player/core/router/app_routes.dart';
import 'package:media_player/data/models/server_entry.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/data/storage/server_directory.dart';
import 'package:media_player/ui/servers_section.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../support/fake_library_service.dart';
import '../support/fake_playback_engine.dart';
import '../support/fake_playback_reporter.dart';
import '../support/fake_playback_service.dart';
import '../support/fake_poster_cache.dart';
import '../support/fake_endpoint_probe.dart';
import '../support/fake_server_auth.dart';

PackageInfo _packageInfo() => PackageInfo(
  appName: 'Media Player',
  packageName: 'dev.mediaplayer.media_player',
  version: '1.2.3',
  buildNumber: '4',
);

void main() {
  late InMemoryKeyValueStore store;
  late ServerDirectory directory;
  late FakeServerAuth auth;
  late FakeEndpointProbe probe;

  setUp(() {
    store = InMemoryKeyValueStore();
    directory = ServerDirectory(store);
    auth = FakeServerAuth();
    probe = FakeEndpointProbe();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    // A tall surface keeps every settings section inside the lazy ListView's
    // build range (S20 added the 服务器 section).
    await tester.binding.setSurfaceSize(const Size(900, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bootstrapProvider.overrideWith(
            (ref) async => AppServices(
              auth: auth,
              library: FakeLibraryService(),
              posters: FakePosterCache(),
              playback: FakePlaybackService(),
              createEngine: FakePlaybackEngine.new,
              createReporter: FakePlaybackReporter.new,
              store: store,
              servers: directory,
              endpointProbe: probe,
            ),
          ),
          appVersionProvider.overrideWith((ref) async => _packageInfo()),
          feedbackServiceConfigProvider.overrideWithValue(null),
        ],
        child: const MediaPlayerApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('login-settings')));
    await tester.pumpAndSettle();
  }

  const home = ServerEntry(
    id: 'a',
    name: 'Home',
    lanUrl: 'http://192.168.1.10:8096',
  );
  const office = ServerEntry(
    id: 'b',
    name: 'Office',
    lanUrl: 'http://10.0.0.5:8096',
  );
  const cabin = ServerEntry(
    id: 'c',
    name: 'Cabin',
    lanUrl: 'http://172.16.0.9:8096',
  );

  testWidgets('settings lists saved servers and highlights the active one', (
    tester,
  ) async {
    await directory.add(home);
    await directory.add(office);
    await directory.setActive('a');
    // No session for the active server: the gate lands on login.
    await pumpApp(tester);
    await openSettings(tester);

    expect(find.text('服务器'), findsOneWidget);
    expect(find.byKey(const Key('server-a')), findsOneWidget);
    expect(find.byKey(const Key('server-b')), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Office'), findsOneWidget);
    // Only the active entry is labelled 当前 (the appearance section also uses
    // that word, so match the server subtitle exactly).
    expect(find.text('http://192.168.1.10:8096 · 当前'), findsOneWidget);
    expect(find.byKey(const Key('settings-server-add')), findsOneWidget);
  });

  testWidgets(
    'the servers page shows the active user and an add button (S55)',
    (tester) async {
      await directory.add(home);
      await directory.setActive('a');
      auth.seedSession('a');
      // The bootstrap override does not run the real auth.useServer wiring.
      auth.useServer('a');
      await pumpApp(tester);

      ProviderScope.containerOf(tester.element(find.byType(MediaPlayerApp)))
          .read(appRouterProvider)
          .go(AppRoutes.servers);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('servers-add-fab')), findsOneWidget);
      expect(find.text('http://192.168.1.10:8096 · 当前 · test'), findsOneWidget);
    },
  );

  testWidgets('the servers page shows an online dot per server (S64)', (
    tester,
  ) async {
    probe = FakeEndpointProbe(online: <String>{'http://192.168.1.10:8096'});
    await directory.add(home);
    await directory.add(office);
    await directory.setActive('a');
    auth.useServer('a');
    await pumpApp(tester);

    ProviderScope.containerOf(tester.element(find.byType(MediaPlayerApp)))
        .read(appRouterProvider)
        .go(AppRoutes.servers);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('server-online-a')), findsOneWidget);
    expect(find.byKey(const Key('server-online-b')), findsOneWidget);
    expect(
      probe.requests,
      containsAll(<String>['http://192.168.1.10:8096', 'http://10.0.0.5:8096']),
    );
  });

  testWidgets(
    'switching to a server with a session restores it and opens home',
    (tester) async {
      await directory.add(home);
      await directory.add(office);
      await directory.setActive('a');
      auth.seedSession('b');
      await pumpApp(tester);
      await openSettings(tester);

      await tester.tap(find.byKey(const Key('server-switch-b')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('home-page')), findsOneWidget);
      expect(auth.activeServerId, 'b');
      expect(auth.restoredServers, contains('b'));
      expect(await directory.activeId(), 'b');
    },
  );

  testWidgets('switching to a server without a session routes to its login', (
    tester,
  ) async {
    await directory.add(home);
    await directory.add(office);
    await directory.add(cabin);
    await directory.setActive('a');
    await pumpApp(tester);
    await openSettings(tester);

    await tester.tap(find.byKey(const Key('server-switch-c')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login-submit')), findsOneWidget);
    expect(find.byKey(const Key('home-page')), findsNothing);
    expect(auth.activeServerId, 'c');
    expect(await directory.activeId(), 'c');
    // The login form is prefilled with the target server's address.
    final lan = tester.widget<TextField>(
      find.byKey(const Key('login-lan-url')),
    );
    expect(lan.controller?.text, cabin.lanUrl);
  });

  testWidgets('adding a server creates a directory entry on login', (
    tester,
  ) async {
    await directory.add(home);
    await directory.setActive('a');
    await pumpApp(tester);
    await openSettings(tester);

    await tester.tap(find.byKey(const Key('settings-server-add')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('login-submit')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('login-lan-url')),
      'http://192.168.50.7:8096',
    );
    await tester.enterText(find.byKey(const Key('login-username')), 'tester');
    await tester.enterText(find.byKey(const Key('login-password')), 'secret');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home-page')), findsOneWidget);
    expect(auth.loginAttempts, 1);
    final entries = await directory.read();
    expect(entries.length, 2);
    expect(entries.map((e) => e.id), contains('a'));
    final added = entries.firstWhere((e) => e.id != 'a');
    expect(added.lanUrl, 'http://192.168.50.7:8096');
    expect(await directory.activeId(), added.id);
    // The new login was stored under the new server id, not the default.
    expect(auth.lastLogin?.serverId, added.id);
  });

  testWidgets('deleting a non-active server removes it and its credentials', (
    tester,
  ) async {
    await directory.add(home);
    await directory.add(office);
    await directory.setActive('a');
    auth.seedSession('b');
    await pumpApp(tester);
    await openSettings(tester);

    await tester.tap(find.byKey(const Key('server-delete-b')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('server-b')), findsNothing);
    expect(find.byKey(const Key('server-a')), findsOneWidget);
    expect((await directory.read()).map((e) => e.id), <String>['a']);
    expect(auth.clearedServers, contains('b'));
    // The active server is unchanged, so the app stays put.
    expect(await directory.activeId(), 'a');
  });

  testWidgets('a still-resolving directory shows a loading row (S79)', (
    tester,
  ) async {
    // Bootstrap never completes, so the server directory (and therefore the
    // controller) stays loading: the section must say so instead of looking
    // like a list with no servers.
    final Completer<AppServices> bootstrap = Completer<AppServices>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bootstrapProvider.overrideWith((Ref ref) => bootstrap.future),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ServerSettingsSection()),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('settings-server-loading')), findsOneWidget);
    expect(find.text('正在加载服务器…'), findsOneWidget);
    expect(find.byKey(const Key('settings-server-empty')), findsNothing);
    // The wait uses the app loader (S66), not a Material spinner.
    expect(find.byKey(const Key('app-loader')), findsOneWidget);
  });
}
