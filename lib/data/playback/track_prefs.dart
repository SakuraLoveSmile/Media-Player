/// Preferred track languages (S5), persisted app-wide the same way as
/// `SubtitleStyle`. An empty code means "auto": the engine keeps its own
/// default track and nothing is forced on load.
class TrackPrefs {
  const TrackPrefs({this.audioLanguage = '', this.subtitleLanguage = ''});

  /// KeyValueStore key shared by the player controller and the settings page.
  static const String storageKey = 'player.trackPrefs.v1';

  factory TrackPrefs.fromJson(Map<String, dynamic> json) {
    return TrackPrefs(
      audioLanguage: json['audioLanguage'] as String? ?? '',
      subtitleLanguage: json['subtitleLanguage'] as String? ?? '',
    );
  }

  /// Empty means auto (engine default).
  final String audioLanguage;
  final String subtitleLanguage;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'audioLanguage': audioLanguage,
    'subtitleLanguage': subtitleLanguage,
  };

  TrackPrefs copyWith({String? audioLanguage, String? subtitleLanguage}) {
    return TrackPrefs(
      audioLanguage: audioLanguage ?? this.audioLanguage,
      subtitleLanguage: subtitleLanguage ?? this.subtitleLanguage,
    );
  }
}

/// Common ISO 639-1 / 639-2/B / 639-2/T spellings folded onto one code, so a
/// 'chi' preference also matches a server that reports 'zho' or 'zh'.
const Map<String, String> _languageAliases = <String, String>{
  'zho': 'chi',
  'zh': 'chi',
  'chinese': 'chi',
  'en': 'eng',
  'english': 'eng',
  'ja': 'jpn',
  'japanese': 'jpn',
  'ko': 'kor',
  'korean': 'kor',
  'fr': 'fra',
  'fre': 'fra',
  'french': 'fra',
  'de': 'deu',
  'ger': 'deu',
  'german': 'deu',
  'es': 'spa',
  'spanish': 'spa',
  'ru': 'rus',
  'russian': 'rus',
};

String _canonicalLanguage(String raw) {
  final String code = raw.trim().toLowerCase();
  return _languageAliases[code] ?? code;
}

/// Whether [language] (a server stream code, possibly absent) satisfies the
/// preferred [preferred] code. Empty on either side never matches: "auto"
/// must not force a track.
bool trackLanguageMatches(String preferred, String? language) {
  if (preferred.isEmpty || language == null || language.isEmpty) return false;
  return _canonicalLanguage(preferred) == _canonicalLanguage(language);
}
