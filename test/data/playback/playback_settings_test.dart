import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/playback/playback_settings.dart';

void main() {
  group('PlaybackSettings seek steps (S80)', () {
    test('defaults to 10 seconds in both directions', () {
      const settings = PlaybackSettings();
      expect(PlaybackSettings.defaultSeekStepSeconds, 10);
      expect(settings.seekBackSeconds, 10);
      expect(settings.seekForwardSeconds, 10);
    });

    test('offers the 5 / 10 / 15 / 30 / 60 presets', () {
      expect(PlaybackSettings.seekStepPresets, <int>[5, 10, 15, 30, 60]);
    });

    test('custom steps round-trip through JSON', () {
      const settings = PlaybackSettings(
        seekBackSeconds: 5,
        seekForwardSeconds: 30,
      );

      final Map<String, dynamic> json =
          jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>;
      final PlaybackSettings restored = PlaybackSettings.fromJson(json);

      expect(restored.seekBackSeconds, 5);
      expect(restored.seekForwardSeconds, 30);
      // Every other field survives the extra keys untouched.
      expect(restored.hwdecEnabled, settings.hwdecEnabled);
      expect(restored.seekOnDrag, settings.seekOnDrag);
    });

    test('a pre-S80 blob without the keys falls back to 10 s', () {
      // Exactly the shape written before the seek steps existed.
      final Map<String, dynamic> old = <String, dynamic>{
        'hwdecEnabled': false,
        'volumeGainPercent': 120.0,
        'cacheSecs': 45,
        'demuxerMaxBytes': 200 * 1024 * 1024,
        'gpuNext': true,
        'deband': false,
        'yuv420': false,
        'seekOnDrag': true,
        'autoPlayNext': false,
        'forceStereo': false,
        'mpvQualityPreset': 'high',
        'mpvCustomConfig': '',
      };

      final PlaybackSettings restored = PlaybackSettings.fromJson(old);
      expect(restored.seekBackSeconds, 10);
      expect(restored.seekForwardSeconds, 10);
      // The rest of the old blob still loads.
      expect(restored.hwdecEnabled, isFalse);
      expect(restored.cacheSecs, 45);
      expect(restored.seekOnDrag, isTrue);
      expect(restored.autoPlayNext, isFalse);
    });

    test('non-numeric and non-preset stored values fall back to 10 s', () {
      for (final Object? raw in <Object?>[
        '30',
        '',
        true,
        null,
        7,
        9.5,
        0,
        -10,
        3600,
      ]) {
        final PlaybackSettings restored = PlaybackSettings.fromJson(
          <String, dynamic>{
            'seekBackSeconds': raw,
            'seekForwardSeconds': raw,
          },
        );
        expect(restored.seekBackSeconds, 10, reason: '$raw');
        expect(restored.seekForwardSeconds, 10, reason: '$raw');
      }
    });

    test('normalize accepts only the presets', () {
      for (final int preset in PlaybackSettings.seekStepPresets) {
        expect(PlaybackSettings.normalizeSeekStepSeconds(preset), preset);
      }
      expect(PlaybackSettings.normalizeSeekStepSeconds(12), 10);
      expect(PlaybackSettings.normalizeSeekStepSeconds('15'), 10);
      expect(PlaybackSettings.normalizeSeekStepSeconds(null), 10);
    });

    test('copyWith keeps the other direction', () {
      const settings = PlaybackSettings(seekBackSeconds: 15);
      expect(settings.copyWith(seekForwardSeconds: 60).seekBackSeconds, 15);
      expect(
        settings.copyWith(seekForwardSeconds: 60).seekForwardSeconds,
        60,
      );
      expect(
        settings.copyWith(seekBackSeconds: 5).seekForwardSeconds,
        10,
      );
    });
  });
}
