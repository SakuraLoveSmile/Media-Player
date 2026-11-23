import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/providers.dart';
import 'package:media_player/app/services.dart';
import 'package:media_player/data/models/media_item.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/data/watch_together/watch_together_client.dart';
import 'package:media_player/features/watch_together/watch_media_picker.dart';
import 'package:media_player/features/watch_together/watch_together_page.dart';

import '../data/offline/offline_test_session.dart';
import '../support/fake_library_service.dart';
import '../support/fake_playback_engine.dart';
import '../support/fake_playback_reporter.dart';
import '../support/fake_playback_service.dart';
import '../support/fake_poster_cache.dart';
import 'session_gate_test.dart' show FakeAuth;

const _movie = MediaItem(
  id: 'movie',
  name: '待看电影',
  type: 'Movie',
  userData: UserItemData(positionTicks: 120000000),
);

WatchRoom _room({bool owner = true, bool guest = true}) => WatchRoom(
  roomId: 'room',
  code: 'ABC234',
  capacity: 4,
  ownerMemberId: 'owner',
  media: const WatchMedia(
    itemId: 'movie',
    mediaSourceId: 'source-b',
    title: '房间电影',
    type: 'Movie',
    runTimeMs: 60000,
  ),
  playback: const WatchPlayback(
    revision: 1,
    state: 'paused',
    positionMs: 0,
    serverTime: 1,
    waitingMemberIds: [],
  ),
  members: [
    const WatchMember(
      memberId: 'owner',
      name: '房主昵称',
      role: 'owner',
      connected: true,
      status: 'away',
      lagging: false,
    ),
    if (guest)
      const WatchMember(
        memberId: 'guest',
        name: '朋友昵称',
        role: 'member',
        connected: true,
        status: 'away',
        lagging: false,
      ),
  ],
);

/// Keeps REST admission and websocket connection independently controllable.
class _Client extends WatchTogetherClient {
  _Client(InMemoryKeyValueStore store)
    : super(session: OfflineTestSession('http://127.0.0.1:1'), store: store);
  WatchRoom? currentRoom;
  bool socketConnected = false;
  bool owner = true;
  Completer<void>? admission;
  final acceptedStatuses = <String>[];
  final attemptedStatuses = <(String, bool)>[];
  String? createdItem, createdSource, joinedCode, kickedMember;
  int? createdPosition;
  bool ended = false;
  @override
  WatchRoom? get room => currentRoom;
  @override
  String? get memberId => owner ? 'owner' : 'guest';
  @override
  bool get connected => socketConnected;
  @override
  bool get isOwner => owner && currentRoom != null;
  @override
  Future<void> create({
    required String itemId,
    String? mediaSourceId,
    int positionMs = 0,
  }) async {
    createdItem = itemId;
    createdSource = mediaSourceId;
    createdPosition = positionMs;
    currentRoom = _room();
    notifyListeners();
    admission = Completer<void>();
    await admission!.future;
  }

  void connect() {
    socketConnected = true;
    notifyListeners();
    admission?.complete();
    admission = null;
  }

  @override
  Future<void> join(String code) async {
    joinedCode = code;
    owner = false;
    currentRoom = _room(owner: false);
    socketConnected = true;
    notifyListeners();
  }

  @override
  void reportStatus(String status, {int positionMs = 0}) {
    attemptedStatuses.add((status, connected));
    if (connected) acceptedStatuses.add(status);
  }

  @override
  Future<void> kick(String memberId) async {
    kickedMember = memberId;
    currentRoom = _room(guest: false);
    notifyListeners();
  }

  @override
  Future<void> end() async {
    ended = true;
    currentRoom = null;
    socketConnected = false;
    notifyListeners();
  }
}

void main() {
  late InMemoryKeyValueStore store;
  late _Client client;
  setUp(() {
    store = InMemoryKeyValueStore();
    client = _Client(store);
  });
  tearDown(() => client.dispose());

  Future<void> pumpPage(
    WidgetTester tester, {
    String? itemId,
    String? sourceId,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bootstrapProvider.overrideWith(
            (ref) async => AppServices(
              auth: FakeAuth(),
              library: FakeLibraryService(itemsById: {'movie': _movie}),
              posters: FakePosterCache(),
              playback: FakePlaybackService(),
              createEngine: FakePlaybackEngine.new,
              createReporter: FakePlaybackReporter.new,
              watchTogether: client,
            ),
          ),
        ],
        child: MaterialApp(
          home: WatchTogetherPage(
            initialItemId: itemId,
            initialSourceId: sourceId,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'service configuration requires trust confirmation and saves URL',
    (tester) async {
      await pumpPage(tester);
      await tester.enterText(
        find.byKey(const Key('watch-service-url')),
        'http://127.0.0.1:3456',
      );
      await tester.tap(find.text('保存服务地址'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('信任这个一起看服务？'), findsOneWidget);
      expect(await store.read(WatchTogetherClient.serviceKey), isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(client.baseUrl, isNull);
      await tester.tap(find.text('保存服务地址'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('确认'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pumpAndSettle();
      expect(
        await store.read(WatchTogetherClient.serviceKey),
        'http://127.0.0.1:3456/watch/v1',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'create waits for websocket before lobby announces loading once',
    (tester) async {
      await tester.runAsync(
        () => client.configure(Uri.parse('http://127.0.0.1:3456')),
      );
      await pumpPage(tester, itemId: 'movie', sourceId: 'source-b');
      await tester.tap(find.text('从我的观看进度开始'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('watch-create')));
      await tester.pump();
      expect(client.createdItem, 'movie');
      expect(client.createdSource, 'source-b');
      expect(client.createdPosition, 12000);
      expect(client.room, isNotNull);
      expect(client.connected, isFalse);
      expect(client.attemptedStatuses, isEmpty);
      client.connect();
      await tester.pumpAndSettle();
      expect(client.acceptedStatuses, ['loading']);
      client.notifyListeners();
      await tester.pumpAndSettle();
      expect(client.acceptedStatuses, ['loading']);
      expect(find.text('ABC234'), findsOneWidget);
      expect(find.text('房主昵称（我）'), findsOneWidget);
      expect(find.text('朋友昵称'), findsOneWidget);
      expect(find.text('移出'), findsOneWidget);
      await tester.ensureVisible(find.text('解散房间'));
      expect(find.text('解散房间'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('join shows members and hides owner administration', (
    tester,
  ) async {
    await tester.runAsync(
      () => client.configure(Uri.parse('http://127.0.0.1:3456')),
    );
    await pumpPage(tester);
    await tester.ensureVisible(find.byKey(const Key('watch-room-code')));
    await tester.enterText(find.byKey(const Key('watch-room-code')), 'abc234');
    await tester.ensureVisible(find.byKey(const Key('watch-join')));
    await tester.tap(find.byKey(const Key('watch-join')));
    await tester.pumpAndSettle();
    expect(client.joinedCode, 'abc234');
    expect(find.text('朋友昵称（我）'), findsOneWidget);
    expect(find.text('房主昵称'), findsOneWidget);
    expect(find.text('移出'), findsNothing);
    expect(find.text('解散房间'), findsNothing);
    expect(client.acceptedStatuses, ['loading']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('owner kick and end ask confirmation before taking effect', (
    tester,
  ) async {
    client.currentRoom = _room();
    client.socketConnected = true;
    await pumpPage(tester);
    await tester.ensureVisible(find.text('移出'));
    await tester.tap(find.text('移出'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(client.kickedMember, isNull);
    expect(find.text('移出成员？'), findsOneWidget);
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(client.kickedMember, 'guest');
    expect(find.text('朋友昵称'), findsNothing);
    await tester.ensureVisible(find.text('解散房间'));
    await tester.tap(find.text('解散房间'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(client.ended, isFalse);
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(client.ended, isTrue);
    expect(find.byKey(const Key('watch-room-code')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'picker follows series without Season.seriesId and selects source',
    (tester) async {
      const series = MediaItem(id: 'show', name: '测试剧集', type: 'Series');
      const season = MediaItem(id: 'season', name: '第一季', type: 'Season');
      final episode = MediaItem.fromJson({
        'Id': 'episode',
        'Name': '第一集',
        'Type': 'Episode',
        'MediaSources': [
          {'Id': 'source-a', 'Name': '1080P', 'Container': 'mkv'},
          {'Id': 'source-b', 'Name': '4K版本', 'Container': 'mkv'},
        ],
      });
      final library = FakeLibraryService(
        itemsByView: {
          '': [series],
        },
        itemsById: {'episode': episode},
        seasonsBySeries: {
          'show': [season],
        },
        episodesBySeason: {
          'season': [episode],
        },
      );
      WatchMediaSelection? selection;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selection = await Navigator.of(context)
                      .push<WatchMediaSelection>(
                        MaterialPageRoute(
                          builder: (_) => WatchMediaPicker(library: library),
                        ),
                      );
                },
                child: const Text('打开选片'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开选片'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('watch-pick-show')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('watch-pick-season')));
      await tester.pumpAndSettle();
      expect(library.episodeRequests.single, (
        seriesId: 'show',
        seasonId: 'season',
      ));
      await tester.tap(find.byKey(const ValueKey('watch-pick-episode')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('所有成员使用同一版本'), findsOneWidget);
      await tester.tap(find.text('4K版本'));
      await tester.pumpAndSettle();
      expect(selection?.item.id, 'episode');
      expect(selection?.sourceId, 'source-b');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'service address shows the Chinese domain instead of percent escapes',
    (tester) async {
      // Stored addresses are ASCII punycode; the field must show Unicode.
      await tester.runAsync(
        () => client.configure(
          Uri.parse('https://watch.xn--fhqths51enha.cn/watch/v1'),
        ),
      );
      await pumpPage(tester);
      final field = tester.widget<TextField>(
        find.byKey(const Key('watch-service-url')),
      );
      expect(field.controller!.text, 'https://watch.上杉九月.cn/watch/v1');
      expect(field.controller!.text, isNot(contains('%E4')));
      expect(
        await store.read(WatchTogetherClient.serviceKey),
        'https://watch.xn--fhqths51enha.cn/watch/v1',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saving a Chinese domain shows the Unicode address and stores punycode',
    (tester) async {
      await pumpPage(tester);
      await tester.enterText(
        find.byKey(const Key('watch-service-url')),
        'https://watch.上杉九月.cn',
      );
      await tester.tap(find.text('保存服务地址'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('确认'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
        find.byKey(const Key('watch-service-url')),
      );
      expect(field.controller!.text, 'https://watch.上杉九月.cn/watch/v1');
      expect(field.controller!.text, isNot(contains('%')));
      expect(
        await store.read(WatchTogetherClient.serviceKey),
        'https://watch.xn--fhqths51enha.cn/watch/v1',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
