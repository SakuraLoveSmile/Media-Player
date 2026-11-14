import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/data/models/media_item.dart';
import 'package:media_player/features/player/chapter_skip.dart';

Chapter _ch(String name, int seconds) =>
    Chapter(name: name, startTicks: seconds * 10000000);

void main() {
  const runtime = Duration(minutes: 24); // 1440 s

  group('resolveChapterSkip', () {
    test('empty chapters yield no skip', () {
      final r = resolveChapterSkip([], isEpisode: true, duration: runtime);
      expect(r.hasIntro, isFalse);
      expect(r.hasCredits, isFalse);
    });

    test('named intro and credits resolve to ranges', () {
      final r = resolveChapterSkip(
        [_ch('Intro', 0), _ch('正片', 90), _ch('Credits', 1320)],
        isEpisode: true,
        duration: runtime,
      );
      expect(r.introStart, Duration.zero);
      expect(r.introEnd, const Duration(seconds: 90));
      expect(r.creditsStart, const Duration(seconds: 1320));
      expect(r.hasIntro, isTrue);
      expect(r.hasCredits, isTrue);
    });

    test('Chinese 片头/片尾 names match', () {
      final r = resolveChapterSkip(
        [_ch('片头', 0), _ch('正片', 85), _ch('片尾', 1300)],
        isEpisode: true,
        duration: runtime,
      );
      expect(r.introEnd, const Duration(seconds: 85));
      expect(r.creditsStart, const Duration(seconds: 1300));
    });

    test('OP/ED match as whole tokens', () {
      final r = resolveChapterSkip(
        [_ch('OP', 0), _ch('A part', 90), _ch('ED', 1320)],
        isEpisode: true,
        duration: runtime,
      );
      expect(r.hasIntro, isTrue);
      expect(r.creditsStart, const Duration(seconds: 1320));
    });

    test('"operation" never matches the short op token', () {
      final r = resolveChapterSkip(
        [_ch('Operation', 0), _ch('Main', 90)],
        isEpisode: false,
        duration: runtime,
      );
      expect(r.hasIntro, isFalse);
    });

    test('"edited" never matches the short ed token', () {
      final r = resolveChapterSkip(
        [_ch('Main', 0), _ch('Edited', 1320)],
        isEpisode: false,
        duration: runtime,
      );
      expect(r.hasCredits, isFalse);
    });

    test('episode positional fallback covers unlabelled OP/ED', () {
      final r = resolveChapterSkip(
        [_ch('Chapter 1', 0), _ch('Chapter 2', 90), _ch('Chapter 3', 1320)],
        isEpisode: true,
        duration: runtime,
      );
      expect(r.introEnd, const Duration(seconds: 90));
      expect(r.creditsStart, const Duration(seconds: 1320));
    });

    test('movie scene markers never trigger a positional skip', () {
      final r = resolveChapterSkip(
        [_ch('Chapter 1', 0), _ch('Chapter 2', 90), _ch('Chapter 3', 1320)],
        isEpisode: false,
        duration: runtime,
      );
      expect(r.hasIntro, isFalse);
      expect(r.hasCredits, isFalse);
    });

    test('a first chapter away from the start is not an intro fallback', () {
      final r = resolveChapterSkip(
        [_ch('Chapter 1', 30), _ch('Chapter 2', 90)],
        isEpisode: true,
        duration: runtime,
      );
      expect(r.hasIntro, isFalse);
    });

    test('a last chapter before the final fifth is not a credits fallback', () {
      final r = resolveChapterSkip(
        [_ch('Chapter 1', 0), _ch('Chapter 2', 600)],
        isEpisode: true,
        duration: runtime,
      );
      expect(r.hasCredits, isFalse);
    });

    test('a lone intro chapter has no end and is rejected', () {
      final r = resolveChapterSkip(
        [_ch('Intro', 0)],
        isEpisode: true,
        duration: runtime,
      );
      expect(r.hasIntro, isFalse);
    });

    test('an intro whose end reaches the runtime is rejected', () {
      final r = resolveChapterSkip(
        [_ch('Intro', 0), _ch('Content', 1440)],
        isEpisode: true,
        duration: runtime,
      );
      expect(r.hasIntro, isFalse);
    });

    test('named credits win over the positional fallback', () {
      final r = resolveChapterSkip(
        [_ch('Intro', 0), _ch('正片', 90), _ch('片尾', 1200), _ch('Preview', 1380)],
        isEpisode: true,
        duration: runtime,
      );
      expect(r.creditsStart, const Duration(seconds: 1200));
    });
  });
}
