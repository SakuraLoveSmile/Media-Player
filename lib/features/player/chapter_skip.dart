import '../../data/models/media_item.dart';

/// Resolved skip targets for an item's chapters (S12). A field is null when no
/// usable marker was found, so the UI only offers a skip it can actually honour.
class ChapterSkip {
  const ChapterSkip({this.introStart, this.introEnd, this.creditsStart});

  final Duration? introStart;
  final Duration? introEnd;
  final Duration? creditsStart;

  bool get hasIntro =>
      introStart != null && introEnd != null && introEnd! > introStart!;
  bool get hasCredits => creditsStart != null;
}

const _introNames = <String>['intro', 'opening', '片头', '开场', '序幕', '序章'];
const _creditsNames = <String>['credits', 'ending', 'outro', '片尾', '结尾', '终章'];

bool _matches(String name, List<String> keys) {
  final n = name.trim().toLowerCase();
  if (n.isEmpty) return false;
  // Whole-token match so "op" never fires inside "operation" and "ed" never
  // fires inside "edited"; a labelled chapter is exactly the keyword or carries
  // it as a standalone word.
  for (final k in keys) {
    if (n == k) return true;
    if (k.length >= 3 && n.contains(k)) return true;
    if (k.length < 3 && _hasToken(n, k)) return true;
  }
  return false;
}

bool _hasToken(String name, String token) {
  for (final part in name.split(RegExp(r'[\s\-_/.,:;()\[\]]+'))) {
    if (part == token) return true;
  }
  return false;
}

/// Derives intro/credits ranges from chapter markers. Name matches win; for
/// episodes a positional fallback covers unlabelled OP/ED chapters (the first
/// chapter at the very start, the last chapter in the final fifth). Movies keep
/// name-only detection so ordinary scene markers never trigger a false skip.
ChapterSkip resolveChapterSkip(
  List<Chapter> chapters, {
  required bool isEpisode,
  required Duration duration,
}) {
  if (chapters.isEmpty) return const ChapterSkip();

  Duration? introStart;
  Duration? introEnd;
  for (var i = 0; i < chapters.length; i++) {
    if (_matches(chapters[i].name, _introNames)) {
      introStart = chapters[i].start;
      introEnd = i + 1 < chapters.length ? chapters[i + 1].start : null;
      break;
    }
  }
  if (introStart == null &&
      isEpisode &&
      chapters.length >= 2 &&
      chapters.first.start <= const Duration(seconds: 5)) {
    introStart = chapters.first.start;
    introEnd = chapters[1].start;
  }

  Duration? creditsStart;
  for (var i = chapters.length - 1; i >= 0; i--) {
    if (_matches(chapters[i].name, _creditsNames)) {
      creditsStart = chapters[i].start;
      break;
    }
  }
  if (creditsStart == null &&
      isEpisode &&
      chapters.length >= 2 &&
      duration > Duration.zero &&
      chapters.last.start >= duration * 0.8) {
    creditsStart = chapters.last.start;
  }

  // An intro that reaches the runtime is not a skippable intro.
  if (introEnd != null && duration > Duration.zero && introEnd >= duration) {
    introStart = null;
    introEnd = null;
  }

  return ChapterSkip(
    introStart: introStart,
    introEnd: introEnd,
    creditsStart: creditsStart,
  );
}
