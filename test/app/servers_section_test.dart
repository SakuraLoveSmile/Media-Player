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
import 'package:media_player/data/models/library_view.dart';
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
  late FakeLibraryService library;

  setUp(() {
    store = InMemoryKeyValueStore();
    directory = ServerDirectory(store);
    auth = FakeServerAuth();
    probe = FakeEndpointProbe();
    library = FakeLibraryService();
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
              library: library,
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

  /// The /servers page hosts the same section and needs no settings scroll.
  void openServersPage(WidgetTester tester) {
    ProviderScope.containerOf(tester.element(find.byType(MediaPlayerApp)))
        .read(appRouterProvider)
        .go(AppRoutes.servers);
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
    // S80: the active card is marked with a check instead of the old "当前"
    // suffix, and its second line falls back to the address.
    expect(find.byKey(const Key('server-active-a')), findsOneWidget);
    expect(find.byKey(const Key('server-active-b')), findsNothing);
    expect(find.text('http://192.168.1.10:8096'), findsOneWidget);
    expect(find.text('http://10.0.0.5:8096'), findsOneWidget);
    expect(find.byKey(const Key('settings-server-add')), findsOneWidget);
  });

  testWidgets('a punycode address is displayed in its Unicode form', (
    tester,
  ) async {
    const ServerEntry chinese = ServerEntry(
      id: 'd',
      name: '',
      wanUrl: 'https://media.xn--fhqths51enha.cn',
    );
    await directory.add(chinese);
    await directory.setActive('d');
    await pumpApp(tester);
    await openSettings(tester);

    // The name is empty, so the address itself becomes the card title and is
    // printed once (S80 dropped the duplicated second line).
    expect(find.text('https://media.上杉九月.cn'), findsOneWidget);
    expect(find.textContaining('xn--'), findsNothing);
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
      // S80: the user name is the card's second line when 显示用户名 is on.
      expect(find.text('test'), findsOneWidget);
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

      // S80: tapping the card itself switches (the old 切换 button is gone).
      await tester.tap(find.byKey(const Key('server-b')));
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

    await tester.tap(find.byKey(const Key('server-c')));
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

    // S80: 删除 moved into the per-server ⋮ menu.
    await tester.tap(find.byKey(const Key('server-menu-b')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('server-action-delete')));
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
        child: const MaterialApp(home: Scaffold(body: ServerSettingsSection())),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('settings-server-loading')), findsOneWidget);
    expect(find.text('正在加载服务器…'), findsOneWidget);
    expect(find.byKey(const Key('settings-server-empty')), findsNothing);
    // The wait uses the app loader (S66), not a Material spinner.
    expect(find.byKey(const Key('app-loader')), findsOneWidget);
  });

  testWidgets('the ⋮ menu renames a server (S80)', (tester) async {
    await directory.add(home);
    await directory.add(office);
    await directory.setActive('a');
    await pumpApp(tester);
    await openSettings(tester);

    await tester.tap(find.byKey(const Key('server-menu-b')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('server-action-rename')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('server-name-field')), '书房');
    await tester.tap(find.byKey(const Key('server-name-save')));
    await tester.pumpAndSettle();

    expect(find.text('书房'), findsOneWidget);
    expect(find.text('Office'), findsNothing);
    expect((await directory.read()).map((e) => e.name), <String>['Home', '书房']);
  });

  testWidgets('the ⋮ toggles the user name and last-played lines (S80)', (
    tester,
  ) async {
    await directory.add(home);
    await directory.setActive('a');
    auth.seedSession('a');
    // The bootstrap override does not run the real auth.useServer wiring.
    auth.useServer('a');
    await pumpApp(tester);
    // A restored session lands on home, so reach the 服务器 page directly.
    openServersPage(tester);
    await tester.pumpAndSettle();
    expect(find.text('test'), findsOneWidget);

    await tester.tap(find.byKey(const Key('server-menu-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('server-action-toggleUserName')));
    await tester.pumpAndSettle();

    expect(find.text('test'), findsNothing);
    expect((await directory.find('a'))!.showUserName, isFalse);

    await tester.tap(find.byKey(const Key('server-menu-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('server-action-toggleLastPlayed')));
    await tester.pumpAndSettle();

    expect((await directory.find('a'))!.showLastPlayed, isTrue);
  });

  testWidgets('a last-played server shows the time on its card (S80)', (
    tester,
  ) async {
    await directory.add(
      home.copyWith(showLastPlayed: true, lastPlayedAt: DateTime.now()),
    );
    await directory.setActive('a');
    await pumpApp(tester);
    await openSettings(tester);

    expect(find.textContaining('今天'), findsOneWidget);
  });

  testWidgets('the ⋮ menu picks a custom icon (S80)', (tester) async {
    await directory.add(home);
    await directory.setActive('a');
    await pumpApp(tester);
    await openSettings(tester);

    await tester.tap(find.byKey(const Key('server-menu-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('server-action-icon')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('server-icon-tv')));
    await tester.pumpAndSettle();

    expect((await directory.find('a'))!.customIcon, 'tv');
  });

  testWidgets('editing a server updates its addresses (S80)', (tester) async {
    await directory.add(home);
    await directory.setActive('a');
    await pumpApp(tester);
    await openSettings(tester);

    await tester.tap(find.byKey(const Key('server-menu-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('server-action-edit')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('server-edit-lan')),
      'http://192.168.1.77:8096',
    );
    await tester.tap(find.byKey(const Key('server-edit-save')));
    await tester.pumpAndSettle();

    final edited = (await directory.find('a'))!;
    expect(edited.lanUrl, 'http://192.168.1.77:8096');
    expect(edited.name, 'Home');
    // S81: the profile used by login/playback must follow the card edit.
    expect(auth.addressUpdates, hasLength(1));
    expect(auth.addressUpdates.single.serverId, 'a');
    expect(auth.addressUpdates.single.lanUrl, 'http://192.168.1.77:8096');
    expect(auth.addressUpdates.single.wanUrl, isNull);
  });

  testWidgets('an unusable address is refused with a message (S80)', (
    tester,
  ) async {
    await directory.add(home);
    await directory.setActive('a');
    await pumpApp(tester);
    await openSettings(tester);

    await tester.tap(find.byKey(const Key('server-menu-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('server-action-edit')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('server-edit-lan')),
      'not a url',
    );
    await tester.tap(find.byKey(const Key('server-edit-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('server-edit-error')), findsOneWidget);
    expect((await directory.find('a'))!.lanUrl, 'http://192.168.1.10:8096');
  });

  testWidgets('添加备选地址 fills the empty slot (S80)', (tester) async {
    await directory.add(home);
    await directory.setActive('a');
    await pumpApp(tester);
    await openSettings(tester);

    await tester.tap(find.byKey(const Key('server-menu-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('server-action-alternateAddress')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('server-edit-wan')),
      'home.example.com',
    );
    await tester.tap(find.byKey(const Key('server-edit-save')));
    await tester.pumpAndSettle();

    final edited = (await directory.find('a'))!;
    expect(edited.wanUrl, 'https://home.example.com');
    expect(edited.lanUrl, 'http://192.168.1.10:8096');
    expect(auth.addressUpdates, hasLength(1));
    expect(auth.addressUpdates.single.serverId, 'a');
    expect(auth.addressUpdates.single.wanUrl, 'https://home.example.com');
  });

  testWidgets('the avatar opens a quick switch list of saved servers (S80)', (
    tester,
  ) async {
    await directory.add(home);
    await directory.add(office);
    await directory.setActive('a');
    auth.seedSession('a');
    auth.useServer('a');
    await pumpApp(tester);
    expect(find.byKey(const Key('home-page')), findsOneWidget);

    await tester.tap(find.byKey(const Key('home-account')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home-server-a')), findsOneWidget);
    expect(find.byKey(const Key('home-server-b')), findsOneWidget);
    expect(find.byKey(const Key('home-server-add')), findsOneWidget);
    // The active server is ticked; inactive ones are not.
    expect(
      find.descendant(
        of: find.byKey(const Key('home-server-a')),
        matching: find.byIcon(Icons.check_circle),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('home-server-b')),
        matching: find.byIcon(Icons.radio_button_unchecked),
      ),
      findsOneWidget,
    );
  });

  testWidgets('picking another server from the avatar list switches (S80)', (
    tester,
  ) async {
    await directory.add(home);
    await directory.add(office);
    await directory.setActive('a');
    auth.seedSession('a');
    auth.seedSession('b');
    auth.useServer('a');
    await pumpApp(tester);

    await tester.tap(find.byKey(const Key('home-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-server-b')));
    await tester.pumpAndSettle();

    expect(auth.activeServerId, 'b');
    expect(auth.restoredServers, contains('b'));
    expect(await directory.activeId(), 'b');
    expect(find.byKey(const Key('home-page')), findsOneWidget);
  });

  testWidgets('添加服务器 in the avatar list opens the add-server login (S80)', (
    tester,
  ) async {
    await directory.add(home);
    await directory.setActive('a');
    auth.seedSession('a');
    auth.useServer('a');
    await pumpApp(tester);

    await tester.tap(find.byKey(const Key('home-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home-server-add')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login-submit')), findsOneWidget);
    expect(find.byKey(const Key('login-lan-url')), findsOneWidget);
  });

  testWidgets(
    'the dashboard reloads for the server picked in the popup (S80)',
    (tester) async {
      // A dashboard with one library: without views load() stops before it asks
      // for the server name, and the reload would be invisible.
      library.viewList = <LibraryView>[fakeMoviesView];
      await directory.add(home);
      await directory.add(office);
      await directory.setActive('a');
      auth.seedSession('a');
      auth.seedSession('b');
      auth.useServer('a');
      await pumpApp(tester);
      final int before = library.serverNameCalls;
      expect(before, greaterThan(0));

      await tester.tap(find.byKey(const Key('home-account')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home-server-b')));
      await tester.pumpAndSettle();

      // The header/rows belong to the newly active server, so the dashboard had
      // to load again instead of keeping the previous server's content.
      expect(library.serverNameCalls, greaterThan(before));
      expect(find.byKey(const Key('home-page')), findsOneWidget);
    },
  );
}
