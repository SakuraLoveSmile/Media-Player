/// Navigation paths. Kept free of widget imports so any layer may use them.
abstract final class AppRoutes {
  static const String startup = '/';
  static const String login = '/login';
  static const String home = '/home';
  static const String library = '/library';
  static const String person = '/person';
  static const String collection = '/collection';
  static const String search = '/search';
  static const String favorites = '/favorites';
  static const String player = '/player';
  static const String series = '/series';

  /// One season's episode list (S78), pushed from the series page's 季 row.
  static const String season = '/season';
  static const String detail = '/detail';
  static const String settings = '/settings';
  static const String settingsCache = '/settings/cache';
  static const String settingsLibraries = '/settings/libraries';
  static const String settingsPlayer = '/settings/player';
  static const String settingsMpv = '/settings/mpv';
  static const String settingsDanmaku = '/settings/danmaku';
  static const String settingsScreenshot = '/settings/screenshot';
  static const String settingsAppearance = '/settings/appearance';
  static const String servers = '/servers';
  static const String request = '/request';

  /// Live TV channel list (S21), pushed from the home action.
  static const String liveTv = '/livetv';

  /// Read-only server administration (S24), pushed from settings; admins only.
  static const String admin = '/admin';

  /// Login targeting an existing saved server (S20 切换 with no session).
  static String loginFor(String serverId) =>
      '$login?server=${Uri.encodeQueryComponent(serverId)}';

  /// Login that creates a brand-new saved server on success (S20 添加).
  static String loginAdd() => '$login?add=1';

  /// The progress list, pushed from the search page and from settings.
  static const String myRequests = '/request/mine';

  /// [source] pins the version picked on the detail page (S7); omitted when
  /// the server default should be negotiated. [audio] / [subtitle] carry the
  /// track indices picked in the detail page's 当前轨道 rows (S37).
  ///
  /// [portrait] opens the player in 竖屏播放; continuous play (上一集/下一集,
  /// sheet 选集, 自动连播) forwards the current mode so switching episodes does
  /// not flip the device back to landscape (S78).
  static String playerFor(
    String itemId, {
    String? source,
    int? audio,
    int? subtitle,
    bool portrait = false,
  }) {
    final List<String> query = <String>[
      if (source != null && source.isNotEmpty)
        'source=${Uri.encodeQueryComponent(source)}',
      if (audio != null) 'audio=$audio',
      if (subtitle != null) 'subtitle=$subtitle',
      if (portrait) 'portrait=1',
    ];
    return query.isEmpty
        ? '$player/$itemId'
        : '$player/$itemId?${query.join('&')}';
  }

  /// Library page scoped to one view (S28 媒体库 strip / 更多).
  /// [genre] narrows the first page (S46 类型 chips); [studioId]/[studioName]
  /// come from a detail page 工作室 link (S60). All parts are optional.
  static String libraryFor(
    String viewId, {
    String? genre,
    String? studioId,
    String? studioName,
  }) {
    final List<String> query = <String>[
      if (viewId.isNotEmpty) 'view=${Uri.encodeQueryComponent(viewId)}',
      if (genre != null && genre.isNotEmpty)
        'genre=${Uri.encodeQueryComponent(genre)}',
      if (studioId != null && studioId.isNotEmpty)
        'studio=${Uri.encodeQueryComponent(studioId)}',
      if (studioName != null && studioName.isNotEmpty)
        'studioName=${Uri.encodeQueryComponent(studioName)}',
    ];
    return query.isEmpty ? library : '$library?${query.join('&')}';
  }

  /// Person filmography (S34 演员 page).
  static String personFor(String personId, {String? name}) =>
      '$person/$personId${_nameQuery(name)}';

  /// BoxSet children (S34 合集 page).
  static String collectionFor(String collectionId, {String? name}) =>
      '$collection/$collectionId${_nameQuery(name)}';

  static String _nameQuery(String? name) => name == null || name.isEmpty
      ? ''
      : '?name=${Uri.encodeQueryComponent(name)}';

  static String seriesFor(String seriesId) => '$series/$seriesId';

  /// Season page (S78): the season id is the path parameter and its series
  /// rides as a query so the page can still fetch the series hero and episodes.
  static String seasonFor(String seasonId, {required String seriesId}) =>
      '$season/$seasonId?series=${Uri.encodeQueryComponent(seriesId)}';
  static String detailFor(String itemId) => '$detail/$itemId';
}
