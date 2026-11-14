import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' show CancelToken, ProgressCallback;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/app.dart';
import 'package:feedback_widget/feedback_widget.dart';
import 'package:media_player/app/feedback_config.dart';
import 'package:media_player/app/feedback_orb_settings.dart';
import 'package:media_player/app/providers.dart';
import 'package:media_player/app/services.dart';
import 'package:media_player/app/update_providers.dart';
import 'package:media_player/core/network/endpoint_kind.dart';
import 'package:media_player/data/auth/auth_service.dart';
import 'package:media_player/data/models/auth_session.dart';
import 'package:media_player/data/models/server_profile.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/data/update/update_installer.dart';
import 'package:media_player/data/update/update_models.dart';
import 'package:media_player/data/update/update_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../support/fake_library_service.dart';
import '../support/fake_playback_engine.dart';
import '../support/fake_playback_reporter.dart';
import '../support/fake_playback_service.dart';
import '../support/fake_poster_cache.dart';

/// No stored session: the startup gate lands on the login page.
class _SignedOutAuth implements AuthService {
  @override
  AuthSession? get current => null;

  @override
  Stream<AuthSession?> get session => const Stream<AuthSession?>.empty();

  @override
  Future<AuthSession?> restore() async => null;

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

class _FakeUpdateService implements UpdateService {
  _FakeUpdateService({this.release});

  AppRelease? release;

  @override
  String get owner => UpdateService.defaultOwner;

  @override
  String get repo => UpdateService.defaultRepo;

  @override
  Future<AppRelease?> checkForUpdate({
    String? platform,
    UpdateChannel channel = UpdateChannel.stable,
  }) async => release;

  @override
  Future<File> downloadUpdate(
    AppRelease release,
    ReleaseAsset asset, {
    ProgressCallback? onProgress,
    CancelToken? cancelToken,
  }) => throw UnimplementedError();
}

class _FakeUpdateInstaller implements UpdateInstaller {
  @override
  UpdateTarget? get targetOverride => null;

  @override
  String? get executablePathOverride => null;

  @override
  Future<void> installUpdate(File package, AppRelease release) async {}

  @override
  Future<void> openReleasePage(AppRelease release) async {}
}

final AppRelease _release = AppRelease(
  version: '0.2.1',
  tagName: 'v0.2.1',
  notes: '修复若干问题。',
  pageUrl: Uri.parse(
    'https://github.com/SakuraLoveSmile/Media-Player/releases/tag/v0.2.1',
  ),
  assets: <ReleaseAsset>[
    ReleaseAsset(
      name: 'MediaPlayer-macos.zip',
      downloadUrl: Uri.parse('https://example.com/MediaPlayer-macos.zip'),
      sizeBytes: 1024,
      sha256: List<String>.filled(64, 'a').join(),
    ),
  ],
);

PackageInfo _packageInfo() => PackageInfo(
  appName: 'Media Player',
  packageName: 'dev.mediaplayer.media_player',
  version: '0.2.0',
  buildNumber: '2',
  buildSignature: '',
);

Future<_FakeUpdateService> _pumpApp(
  WidgetTester tester, {
  bool feedbackEnabled = false,
  AppRelease? release,
  KeyValueStore? orbStore,
}) async {
  final _FakeUpdateService service = _FakeUpdateService(release: release);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bootstrapProvider.overrideWith(
          (ref) async => AppServices(
            auth: _SignedOutAuth(),
            library: FakeLibraryService(),
            posters: FakePosterCache(),
            playback: FakePlaybackService(),
            createEngine: FakePlaybackEngine.new,
            createReporter: FakePlaybackReporter.new,
          ),
        ),
        appVersionProvider.overrideWith((ref) async => _packageInfo()),
        updateServiceProvider.overrideWithValue(service),
        updateInstallerProvider.overrideWithValue(_FakeUpdateInstaller()),
        updatePlatformProvider.overrideWithValue('macos'),
        feedbackOrbStoreProvider.overrideWith(
          (ref) async => orbStore ?? InMemoryKeyValueStore(),
        ),
        feedbackServiceConfigProvider.overrideWithValue(
          feedbackEnabled
              ? const FeedbackServiceConfig(
                  apiBase: 'http://localhost:8787',
                  appId: 'dev.mediaplayer.media_player.test',
                )
              : null,
        ),
      ],
      child: const MediaPlayerApp(),
    ),
  );
  await tester.pumpAndSettle();
  return service;
}

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('login-settings')));
  await tester.pumpAndSettle();
}

void main() {
  Future<void> scrollToAbout(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.text('检查更新'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('login exposes the settings entry and the about/update rows', (
    WidgetTester tester,
  ) async {
    await _pumpApp(tester);
    expect(find.text('连接你的 Emby 服务器'), findsOneWidget);

    await _openSettings(tester);

    expect(find.text('设置'), findsOneWidget);
    // S73: 关于 sits at the bottom of 设置 now, so scroll the list first.
    await tester.scrollUntilVisible(
      find.text('检查更新'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('版本 0.2.0+2'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
    // Feedback is compiled off in debug/tests by default.
    expect(find.text('问题反馈'), findsNothing);
  });

  testWidgets('manual check reports up-to-date and shows the update dialog', (
    WidgetTester tester,
  ) async {
    final _FakeUpdateService service = await _pumpApp(tester);
    await _openSettings(tester);

    await scrollToAbout(tester);
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    expect(find.text('当前已是最新版本'), findsOneWidget);
    expect(find.text('发现新版本 v0.2.1'), findsNothing);

    // Second check returns a release: the dialog with its notes opens.
    service.release = _release;

    await scrollToAbout(tester);
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();

    expect(find.text('发现新版本 v0.2.1'), findsOneWidget);
    expect(find.text('修复若干问题。'), findsOneWidget);

    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
    expect(find.text('发现新版本 v0.2.1'), findsNothing);
  });

  testWidgets('feedback layer is mounted when the service is configured', (
    WidgetTester tester,
  ) async {
    // The settings list now has seven sections (S20 added 服务器); a short
    // window would keep the feedback rows outside the lazy ListView's build
    // range, so use a tall surface.
    await tester.binding.setSurfaceSize(const Size(900, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpApp(tester, feedbackEnabled: true);

    // The orb lives above the router, so it is present on the login page.
    expect(find.byKey(const Key('feedback-orb')), findsOneWidget);

    await _openSettings(tester);
    expect(find.text('问题反馈'), findsOneWidget);
  });
  testWidgets('in-panel orb settings round-trip through the host store', (
    WidgetTester tester,
  ) async {
    final InMemoryKeyValueStore store = InMemoryKeyValueStore();
    await _pumpApp(tester, feedbackEnabled: true, orbStore: store);

    final FeedbackWidget initial = tester.widget<FeedbackWidget>(
      find.byType(FeedbackWidget),
    );
    expect(initial.orbIdleStyle, FeedbackOrbIdleStyle.handle);
    expect(initial.wakeGestures, isEmpty);

    // The panel calls the host callbacks; the host must persist and feed the
    // new value back into the layer.
    initial.onOrbIdleStyleChanged!(FeedbackOrbIdleStyle.hidden);
    initial.onWakeGesturesChanged!(<FeedbackWakeGesture>{
      FeedbackWakeGesture.twoFingerHold,
    });
    await tester.pumpAndSettle();

    expect(await store.read(feedbackOrbIdleStorageKey), 'hidden');
    expect(
      jsonDecode((await store.read(feedbackWakeGesturesStorageKey))!),
      <String>['two-finger-hold'],
    );
    final FeedbackWidget rebuilt = tester.widget<FeedbackWidget>(
      find.byType(FeedbackWidget),
    );
    expect(rebuilt.orbIdleStyle, FeedbackOrbIdleStyle.hidden);
    expect(rebuilt.wakeGestures, <FeedbackWakeGesture>{
      FeedbackWakeGesture.twoFingerHold,
    });
  });
}
