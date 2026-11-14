/// Danmaku rendering preferences (S17 弹幕), persisted as one JSON blob under
/// [storageKey]. The player controller loads them at open and the player
/// options sheet edits the same key. Living in the data layer keeps any future
/// settings surface from importing the player feature (tool/check_layering.sh),
/// the same trade-off as [PlaybackSettings].
class DanmakuSettings {
  const DanmakuSettings({
    this.enabled = false,
    this.density = 1.0,
    this.opacity = 1.0,
    this.speed = 1.0,
    this.fullArea = false,
  });

  /// KeyValueStore key shared by the player controller and the options sheet.
  static const String storageKey = 'player.danmaku.v1';

  factory DanmakuSettings.fromJson(Map<String, dynamic> json) {
    return DanmakuSettings(
      enabled: json['enabled'] as bool? ?? false,
      density: ((json['density'] as num?)?.toDouble() ?? 1.0).clamp(0.1, 1.0),
      opacity: ((json['opacity'] as num?)?.toDouble() ?? 1.0).clamp(0.1, 1.0),
      speed: ((json['speed'] as num?)?.toDouble() ?? 1.0).clamp(0.5, 2.0),
      fullArea: json['fullArea'] as bool? ?? false,
    );
  }

  /// Off by default: danmaku talks to a public third-party API, so the user
  /// opts in once and the choice persists.
  final bool enabled;

  /// Fraction of the available lanes allowed on screen at once (0.1–1.0);
  /// the overlay turns it into a max-concurrent cap.
  final double density;

  /// Overlay opacity (0.1–1.0).
  final double opacity;

  /// Scroll speed multiplier (0.5–2.0); travel duration = base / speed.
  final double speed;

  /// false = comments stay in the top half of the video box (Yamby default,
  /// keeps the subtitle band clear); true = the full box.
  final bool fullArea;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'enabled': enabled,
    'density': density,
    'opacity': opacity,
    'speed': speed,
    'fullArea': fullArea,
  };

  DanmakuSettings copyWith({
    bool? enabled,
    double? density,
    double? opacity,
    double? speed,
    bool? fullArea,
  }) {
    return DanmakuSettings(
      enabled: enabled ?? this.enabled,
      density: density ?? this.density,
      opacity: opacity ?? this.opacity,
      speed: speed ?? this.speed,
      fullArea: fullArea ?? this.fullArea,
    );
  }
}
