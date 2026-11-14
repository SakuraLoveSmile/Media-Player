import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/playback/playback_engine.dart';

void main() {
  group('SubtitleStyle JSON (S4 + margins toggle)', () {
    test('a full style round-trips through JSON', () {
      const style = SubtitleStyle(
        font: 'serif',
        scale: 1.5,
        delay: Duration(milliseconds: -1200),
        borderSize: 2.5,
        shadowOffset: 1.5,
        overrideAss: true,
        useMargins: true,
      );

      final restored = SubtitleStyle.fromJson(
        jsonDecode(jsonEncode(style.toJson())) as Map<String, dynamic>,
      );

      expect(restored.font, 'serif');
      expect(restored.scale, 1.5);
      expect(restored.delay, const Duration(milliseconds: -1200));
      expect(restored.borderSize, 2.5);
      expect(restored.shadowOffset, 1.5);
      expect(restored.overrideAss, isTrue);
      expect(restored.useMargins, isTrue);
    });

    test('old JSON without useMargins stays backward compatible', () {
      // Exactly the shape written before the margins toggle existed.
      final old = <String, dynamic>{
        'font': 'sans-serif',
        'scale': 1.25,
        'delayMs': 500,
        'borderSize': 3.0,
        'shadowOffset': 0.0,
        'overrideAss': true,
      };

      final restored = SubtitleStyle.fromJson(old);

      expect(restored.useMargins, isFalse);
      expect(restored.font, 'sans-serif');
      expect(restored.scale, 1.25);
      expect(restored.delay, const Duration(milliseconds: 500));
      expect(restored.overrideAss, isTrue);
    });

    test('the default style keeps margins off and serializes the flag', () {
      const style = SubtitleStyle();

      expect(style.useMargins, isFalse);
      expect(style.toJson()['useMargins'], isFalse);
      expect(
        SubtitleStyle.fromJson(const <String, dynamic>{}).useMargins,
        isFalse,
      );
    });

    test('copyWith flips only useMargins', () {
      const style = SubtitleStyle(scale: 1.5, overrideAss: true);

      final flipped = style.copyWith(useMargins: true);

      expect(flipped.useMargins, isTrue);
      expect(flipped.scale, 1.5);
      expect(flipped.overrideAss, isTrue);
      expect(style.copyWith().useMargins, isFalse);
    });
  });
}
