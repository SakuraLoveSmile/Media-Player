import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/app.dart';
import 'package:media_player/app/providers.dart';
import 'package:media_player/app/services.dart';
import 'package:media_player/core/network/endpoint_kind.dart';
import 'package:media_player/data/auth/auth_service.dart';
import 'package:media_player/data/models/auth_session.dart';
import 'package:media_player/data/models/server_profile.dart';

import '../support/fake_library_service.dart';
import '../support/fake_playback_engine.dart';
import '../support/fake_playback_reporter.dart';
import '../support/fake_playback_service.dart';

class FakeAuth implements AuthService {
  FakeAuth({this.restoreResult});

  final AuthSession? restoreResult;

  @override
  AuthSession? get current => restoreResult;

  @override
  Stream<AuthSession?> get session => const Stream<AuthSession?>.empty();

  @override
  Future<AuthSession?> restore() async => restoreResult;

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

const session = AuthSession(
  userId: 'u1',
  userName: 'test',
  accessToken: 'token',
  deviceId: 'd1',
);

Future<void> pumpApp(WidgetTester tester, FakeAuth auth) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bootstrapProvider.overrideWith(
          (ref) async =>
              AppServices(
                auth: auth,
                library: FakeLibraryService(),
                playback: FakePlaybackService(),
                createEngine: FakePlaybackEngine.new,
                createReporter: FakePlaybackReporter.new,
              ),
        ),
      ],
      child: const MediaPlayerApp(),
    ),
  );
}

void main() {
  testWidgets('without a session the gate opens the login screen',
      (tester) async {
    await pumpApp(tester, FakeAuth());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login-submit')), findsOneWidget);
    expect(find.text('连接你的 Emby 服务器'), findsOneWidget);
  });

  testWidgets('with a session the gate opens the library', (tester) async {
    await pumpApp(tester, FakeAuth(restoreResult: session));
    await tester.pumpAndSettle();

    expect(find.text('媒体库'), findsOneWidget);
  });

  testWidgets('shows progress until bootstrap completes', (tester) async {
    final completer = Completer<AppServices>();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bootstrapProvider.overrideWith((ref) => completer.future),
        ],
        child: const MediaPlayerApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(
      AppServices(
        auth: FakeAuth(restoreResult: session),
        library: FakeLibraryService(),
        playback: FakePlaybackService(),
        createEngine: FakePlaybackEngine.new,
        createReporter: FakePlaybackReporter.new,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('媒体库'), findsOneWidget);
  });
}
