import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/playback/mpv_config.dart';
import 'package:media_player/data/playback/playback_settings.dart';

void main() {
  test('comments, CRLF and surrounding whitespace keep line numbers', () {
    final result = MpvConfig.parse('# comment\r\n\n scale = lanczos \r\nhue=4');
    expect(result.isValid, true);
    expect(result.properties, {'scale': 'lanczos', 'hue': '4'});
    final invalid = MpvConfig.parse('# comment\n\ninclude=secret.conf');
    expect(invalid.issues.single.line, 3);
  });

  test('scripts, application options, paths and profiles are rejected', () {
    for (final text in <String>[
      'script=/tmp/run.lua',
      'scripts=run.lua',
      'include=other.conf',
      'vo=gpu-next',
      'wid=123',
      'input-ipc-server=/tmp/mpv',
      'http-header-fields=Authorization: secret',
      'sub-file=/tmp/a.srt',
      'profile=high-quality',
      '[unsafe]',
      'scale=/tmp/shader.glsl',
      'scale=lanczos # extra',
      'saturation=0;script=run.lua',
    ]) {
      expect(MpvConfig.parse(text).isValid, false, reason: text);
      expect(
        () => MpvConfig.resolve(MpvQualityPreset.standard, text),
        throwsFormatException,
      );
    }
  });

  test('numeric ranges, invalid literals and duplicate keys are checked', () {
    for (final text in <String>[
      'scale-antiring=1.1',
      'deband-iterations=1.5',
      'deband-range=-1',
      'gamma=NaN',
      'brightness=Infinity',
      'hue=101',
      'saturation=1e999',
      'scale=lanczos\nscale=bilinear',
    ]) {
      expect(MpvConfig.parse(text).isValid, false, reason: text);
    }
    expect(
      MpvConfig.parse(
        'gamma=-100\nhue=100\nscale-antiring=.5\ndeband-iterations=16',
      ).isValid,
      true,
    );
    expect(MpvConfig.parse('a' * (MpvConfig.maxLength + 1)).isValid, false);
  });

  test('every preset emits a full reset map and custom values override it', () {
    for (final preset in MpvQualityPreset.values) {
      final properties = MpvConfig.resolve(preset, 'saturation=8');
      expect(properties.keys.toSet(), MpvConfig.defaults.keys.toSet());
      expect(properties['saturation'], '8');
      expect(
        MpvConfig.parse(
          properties.entries
              .map((entry) => '${entry.key}=${entry.value}')
              .join('\n'),
        ).isValid,
        true,
      );
    }
    final animation = MpvConfig.resolve(MpvQualityPreset.animation, 'hue=8');
    expect(animation['sigmoid-upscaling'], 'yes');
    final reset = MpvConfig.resolve(MpvQualityPreset.standard, '');
    expect(reset['sigmoid-upscaling'], 'no');
    expect(reset['hue'], '0');
    expect(reset, MpvConfig.defaults);
  });

  test(
    'old settings retain defaults and quality configuration round trips',
    () {
      final old = PlaybackSettings.fromJson({'deband': true});
      expect(old.mpvQualityPreset, MpvQualityPreset.standard);
      expect(old.mpvCustomConfig, '');
      expect(old.deband, true);
      final current = old.copyWith(
        mpvQualityPreset: MpvQualityPreset.cinema,
        mpvCustomConfig: 'gamma=3',
      );
      final restored = PlaybackSettings.fromJson(current.toJson());
      expect(restored.mpvQualityPreset, MpvQualityPreset.cinema);
      expect(restored.mpvCustomConfig, 'gamma=3');
      expect(restored.deband, true);
    },
  );
}
