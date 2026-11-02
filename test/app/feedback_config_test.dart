import 'package:feedback_widget/feedback_widget.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/feedback_config.dart';

/// Mirrors the compile-time defines so these tests hold in both the default
/// run and a `--dart-define=...` run.
const String _enabledRaw = String.fromEnvironment('FEEDBACK_ENABLED');
const String _apiBaseRaw = String.fromEnvironment('FEEDBACK_API_BASE');
const String _appIdRaw = String.fromEnvironment('FEEDBACK_APP_ID');
const String _appNameRaw = String.fromEnvironment('FEEDBACK_APP_NAME');

FeedbackServiceConfig _testService() => const FeedbackServiceConfig(
  apiBase: 'http://localhost:8787',
  appId: 'dev.mediaplayer.media_player.test',
);

void main() {
  group('service identity (dart-define, defaults, enablement)', () {
    test('pins the MediaPlayer production identity', () {
      expect(
        FeedbackBuildConfig.defaultApiBase,
        'https://feedback.xn--fhqths51enha.cn',
      );
      expect(FeedbackBuildConfig.defaultAppId, 'dev.mediaplayer.media_player');
      expect(FeedbackBuildConfig.defaultAppName, 'Media Player');
    });

    test('getters use the dart-define override when present', () {
      expect(
        FeedbackBuildConfig.apiBase,
        _apiBaseRaw.isEmpty ? FeedbackBuildConfig.defaultApiBase : _apiBaseRaw,
      );
      expect(
        FeedbackBuildConfig.appId,
        _appIdRaw.isEmpty ? FeedbackBuildConfig.defaultAppId : _appIdRaw,
      );
      expect(
        FeedbackBuildConfig.appName,
        _appNameRaw.isEmpty ? FeedbackBuildConfig.defaultAppName : _appNameRaw,
      );
    });

    test('is enabled by default only outside debug builds', () {
      if (_enabledRaw.isEmpty) {
        // `flutter test` runs in debug mode, so the gate is off by default.
        expect(FeedbackBuildConfig.enabled, !kDebugMode);
        expect(kDebugMode, isTrue);
      } else {
        expect(
          FeedbackBuildConfig.enabled,
          _enabledRaw == 'true' || _enabledRaw == '1',
        );
      }
    });

    test('the service provider is null while feedback is disabled', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final FeedbackServiceConfig? service = container.read(
        feedbackServiceConfigProvider,
      );
      if (FeedbackBuildConfig.enabled) {
        expect(service, isNotNull);
        expect(service!.apiBase, FeedbackBuildConfig.apiBase);
        expect(service.appId, FeedbackBuildConfig.appId);
        expect(service.appName, FeedbackBuildConfig.appName);
      } else {
        expect(service, isNull);
      }
    });

    test('a test can inject an isolated service address', () {
      final ProviderContainer container = ProviderContainer(
        overrides: [
          feedbackServiceConfigProvider.overrideWithValue(_testService()),
        ],
      );
      addTearDown(container.dispose);

      final FeedbackServiceConfig? service = container.read(
        feedbackServiceConfigProvider,
      );
      expect(service?.apiBase, 'http://localhost:8787');
      expect(service?.appId, 'dev.mediaplayer.media_player.test');
      expect(service?.appName, isNull);
    });

    test(
      'the root controller is a single shared instance, disposed with root',
      () {
        final ProviderContainer container = ProviderContainer();
        final FeedbackController a = container.read(feedbackControllerProvider);
        final FeedbackController b = container.read(feedbackControllerProvider);
        expect(identical(a, b), isTrue);

        container.dispose();
        // A second use after root disposal is a programming error, which proves
        // the provider actually owns (and releases) the controller.
        expect(() => a.open(), throwsFlutterError);
      },
    );
  });

  group('page labels never leak route parameters', () {
    test('keeps the allow-listed top-level category', () {
      expect(feedbackPageLabelFromUri(Uri.parse('/login')), 'login');
      expect(feedbackPageLabelFromUri(Uri.parse('/library')), 'library');
      expect(feedbackPageLabelFromUri(Uri.parse('/player')), 'player');
      expect(feedbackPageLabelFromUri(Uri.parse('/settings')), 'settings');
    });

    test('root maps to startup', () {
      expect(feedbackPageLabelFromUri(Uri.parse('/')), 'startup');
      expect(feedbackPageLabelFromUri(Uri.parse('')), 'startup');
    });

    test('drops the item id and sub-paths', () {
      expect(feedbackPageLabelFromUri(Uri.parse('/player/42')), 'player');
      expect(
        feedbackPageLabelFromUri(Uri.parse('/player/abc-9/detail')),
        'player',
      );
    });

    test('unknown top-level segments collapse to other', () {
      expect(feedbackPageLabelFromUri(Uri.parse('/admin/secret')), 'other');
      expect(feedbackPageLabelFromUri(Uri.parse('/unknown')), 'other');
    });

    test('never leaks ids, query parameters or the server address', () {
      final String label = feedbackPageLabelFromUri(
        Uri.parse(
          '/player/private-item?server=https://emby.example.com&token=abc123',
        ),
      );
      expect(label, 'player');
      expect(label.contains('private-id'), isFalse);
      expect(label.contains('example.com'), isFalse);
      expect(label.contains('abc123'), isFalse);
    });
  });

  group('buildFeedbackConfig (orb + viewport + light + right)', () {
    test('fixes the presentation and passes the runtime values through', () {
      final FeedbackConfig config = buildFeedbackConfig(
        service: _testService(),
        pageLabel: 'library',
        appVersion: '0.2.0+2',
      );

      expect(config.apiBase, 'http://localhost:8787');
      expect(config.appId, 'dev.mediaplayer.media_player.test');
      expect(config.appName, isNull);
      expect(config.appVersion, '0.2.0+2');
      expect(config.pageLabel, 'library');

      expect(config.launcherMode, FeedbackLauncherMode.orb);
      expect(config.captureMode, FeedbackCaptureMode.viewport);
      expect(config.theme, FeedbackThemeMode.light);
      expect(config.side, FeedbackSide.right);
      expect(config.launcherBottom, '30%');
      expect(config.showLauncher, isTrue);
    });

    test('reports the app display name when the service provides one', () {
      final FeedbackConfig config = buildFeedbackConfig(
        service: const FeedbackServiceConfig(
          apiBase: 'http://localhost:8787',
          appId: 'dev.mediaplayer.media_player.test',
          appName: 'Media Player',
        ),
        pageLabel: 'startup',
      );
      expect(config.appName, 'Media Player');
      expect(config.appVersion, isNull);
    });

    test('the player page can hide the built-in launcher', () {
      final FeedbackConfig config = buildFeedbackConfig(
        service: _testService(),
        pageLabel: 'player',
        showLauncher: false,
      );
      expect(config.showLauncher, isFalse);
      expect(config.pageLabel, 'player');
    });

    test('normalizes a trailing slash in apiBase', () {
      final FeedbackConfig config = buildFeedbackConfig(
        service: const FeedbackServiceConfig(
          apiBase: 'http://localhost:8787/',
          appId: 'dev.mediaplayer.media_player.test',
        ),
        pageLabel: 'startup',
      );
      expect(config.apiBase, 'http://localhost:8787');
    });
  });
}
