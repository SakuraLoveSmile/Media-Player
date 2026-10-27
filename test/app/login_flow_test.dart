import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/app.dart';
import 'package:media_player/app/providers.dart';
import 'package:media_player/app/services.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/emby_exception.dart';
import 'package:media_player/core/errors/endpoint_failure.dart';
import 'package:media_player/core/network/endpoint_kind.dart';
import 'package:media_player/data/auth/auth_service.dart';
import 'package:media_player/data/models/auth_session.dart';
import 'package:media_player/data/models/server_profile.dart';

class LoginCall {
  const LoginCall({
    required this.username,
    required this.password,
    required this.profile,
  });

  final String username;
  final String password;
  final ServerProfile profile;
}

class RecordingAuth implements AuthService {
  RecordingAuth({this.lastStoredProfile, this.failure});

  final ServerProfile? lastStoredProfile;
  final EmbyException? failure;

  LoginCall? lastLogin;
  int loginAttempts = 0;

  static const AuthSession sampleSession = AuthSession(
    userId: 'u1',
    userName: 'test',
    accessToken: 'token',
    deviceId: 'd1',
  );

  @override
  AuthSession? get current => null;

  @override
  Stream<AuthSession?> get session => const Stream<AuthSession?>.empty();

  @override
  Future<AuthSession?> restore() async => null;

  @override
  Future<ServerProfile?> lastProfile() async => lastStoredProfile;

  @override
  Future<AuthSession> login({
    required String username,
    required String password,
    required ServerProfile profile,
  }) async {
    loginAttempts++;
    lastLogin = LoginCall(
      username: username,
      password: password,
      profile: profile,
    );
    final error = failure;
    if (error != null) throw error;
    return sampleSession;
  }

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
  Future<void> pumpApp(WidgetTester tester, AuthService auth) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bootstrapProvider.overrideWith((ref) async => AppServices(auth: auth)),
        ],
        child: const MediaPlayerApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fill(
    WidgetTester tester, {
    String lan = '',
    String wan = '',
    String username = 'test',
    String password = 'secret',
  }) async {
    if (lan.isNotEmpty) {
      await tester.enterText(find.byKey(const Key('login-lan-url')), lan);
    }
    if (wan.isNotEmpty) {
      await tester.enterText(find.byKey(const Key('login-wan-url')), wan);
    }
    await tester.enterText(find.byKey(const Key('login-username')), username);
    await tester.enterText(find.byKey(const Key('login-password')), password);
  }

  testWidgets('a valid login forwards normalized data and opens the library',
      (tester) async {
    final auth = RecordingAuth();
    await pumpApp(tester, auth);
    expect(find.byKey(const Key('login-submit')), findsOneWidget);

    await fill(
      tester,
      lan: ' 192.168.1.10:8096/ ',
      wan: 'https://emby.example.com/',
      username: ' test ',
    );
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(auth.loginAttempts, 1);
    expect(auth.lastLogin?.profile.lanUrl, 'http://192.168.1.10:8096');
    expect(auth.lastLogin?.profile.wanUrl, 'https://emby.example.com');
    expect(auth.lastLogin?.username, 'test');
    expect(auth.lastLogin?.password, 'secret');
    expect(find.text('媒体库占位'), findsOneWidget);
  });

  testWidgets('a rejected login keeps the form and shows the reason',
      (tester) async {
    final auth = RecordingAuth(
      failure: EmbyException(AppErrorCode.unauthorized, message: 'HTTP 401'),
    );
    await pumpApp(tester, auth);

    await fill(tester, lan: 'http://192.168.1.10:8096', password: 'wrong');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(find.text('用户名或密码错误'), findsOneWidget);
    expect(find.byKey(const Key('login-submit')), findsOneWidget);
    expect(find.text('媒体库占位'), findsNothing);
  });

  testWidgets('an unreachable server lists the endpoint reasons',
      (tester) async {
    final auth = RecordingAuth(
      failure: EmbyException(
        AppErrorCode.networkUnreachable,
        failures: const <EndpointFailure>[
          EndpointFailure(
            kind: EndpointKind.lan,
            baseUrl: 'http://lan',
            code: AppErrorCode.networkUnreachable,
          ),
        ],
      ),
    );
    await pumpApp(tester, auth);

    await fill(tester, lan: 'http://192.168.1.10:8096');
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(find.text('无法连接服务器，请检查地址与网络'), findsOneWidget);
    expect(find.text('lan: 无法连接'), findsOneWidget);
  });

  testWidgets('an empty form is rejected without calling the backend',
      (tester) async {
    final auth = RecordingAuth();
    await pumpApp(tester, auth);

    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();

    expect(find.text('请至少填写一个服务器地址'), findsOneWidget);
    expect(auth.loginAttempts, 0);
  });

  testWidgets('the last used addresses are prefilled', (tester) async {
    final auth = RecordingAuth(
      lastStoredProfile: const ServerProfile(
        serverId: 'server-1',
        name: 'Home',
        lanUrl: 'http://192.168.1.10:8096',
        wanUrl: 'https://emby.example.com',
      ),
    );
    await pumpApp(tester, auth);
    await tester.pumpAndSettle();

    final lan =
        tester.widget<TextField>(find.byKey(const Key('login-lan-url')));
    final wan =
        tester.widget<TextField>(find.byKey(const Key('login-wan-url')));
    expect(lan.controller?.text, 'http://192.168.1.10:8096');
    expect(wan.controller?.text, 'https://emby.example.com');
  });
}
