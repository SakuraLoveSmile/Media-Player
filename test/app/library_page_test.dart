import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/app.dart';
import 'package:media_player/app/providers.dart';
import 'package:media_player/app/services.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/emby_exception.dart';
import 'package:media_player/core/network/endpoint_kind.dart';
import 'package:media_player/data/auth/auth_service.dart';
import 'package:media_player/data/models/auth_session.dart';
import 'package:media_player/data/models/library_view.dart';
import 'package:media_player/data/models/media_item.dart';
import 'package:media_player/data/models/server_profile.dart';

import '../support/fake_library_service.dart';
import '../support/fake_playback_engine.dart';
import '../support/fake_playback_reporter.dart';
import '../support/fake_playback_service.dart';

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
  }) =>
      throw UnimplementedError();

  @override
  Future<ServerProfile> adoptAddress({
    required ServerProfile profile,
    required EndpointKind kind,
    required String rawUrl,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> logout() async {}

  @override
  Future<void> handleUnauthorized() async {}
}

void main() {
  Future<void> pumpLibrary(
    WidgetTester tester,
    FakeLibraryService library,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bootstrapProvider.overrideWith(
            (ref) async =>
                AppServices(
                  auth: StaticAuth(),
                  library: library,
                  playback: FakePlaybackService(),
                  createEngine: FakePlaybackEngine.new,
                  createReporter: FakePlaybackReporter.new,
                ),
          ),
        ],
        child: const MediaPlayerApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  FakeLibraryService buildService({int movies = 70, int shows = 3}) {
    return FakeLibraryService(
      viewList: <LibraryView>[fakeMoviesView, fakeShowsView],
      itemsByView: <String, List<MediaItem>>{
        fakeMoviesView.id: List<MediaItem>.generate(
          movies,
          (index) => fakeItem('${index + 1}'),
        ),
        fakeShowsView.id: List<MediaItem>.generate(
          shows,
          (index) => fakeItem('s${index + 1}', name: 'Show ${index + 1}'),
        ),
      },
    );
  }

  testWidgets('renders the view chips and the first page', (tester) async {
    await pumpLibrary(tester, buildService());

    expect(find.text('媒体库'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Movies'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Shows'), findsOneWidget);
    expect(find.text('Item 1'), findsOneWidget);
  });

  testWidgets('switching views replaces the grid', (tester) async {
    final library = buildService();
    await pumpLibrary(tester, library);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Shows'));
    await tester.pumpAndSettle();

    expect(find.text('Show 1'), findsOneWidget);
    expect(find.text('Item 1'), findsNothing);
  });

  testWidgets('scrolling to the end loads the next page', (tester) async {
    final library = buildService();
    await pumpLibrary(tester, library);
    expect(library.itemCalls, 1);

    await tester.drag(find.byType(GridView), const Offset(0, -4000));
    await tester.pumpAndSettle();

    expect(library.itemCalls, greaterThanOrEqualTo(2));
  });

  testWidgets('a failure shows a retry that recovers', (tester) async {
    final library = buildService();
    library.failure = EmbyException(AppErrorCode.networkUnreachable);
    await pumpLibrary(tester, library);

    expect(find.text('无法连接服务器，请检查网络'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    library.failure = null;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('Item 1'), findsOneWidget);
  });

  testWidgets('an expired session returns to the login screen', (tester) async {
    final library = buildService();
    library.unauthorized = true;
    await pumpLibrary(tester, library);

    expect(find.byKey(const Key('login-submit')), findsOneWidget);
  });

  testWidgets('an empty view shows the empty message', (tester) async {
    final library = FakeLibraryService(
      viewList: <LibraryView>[fakeMoviesView],
    );
    await pumpLibrary(tester, library);

    expect(find.text('这个库还没有内容'), findsOneWidget);
  });

  testWidgets('a server without views shows the empty message',
      (tester) async {
    await pumpLibrary(tester, FakeLibraryService());

    expect(find.text('服务器没有可浏览的媒体库'), findsOneWidget);
  });
}
