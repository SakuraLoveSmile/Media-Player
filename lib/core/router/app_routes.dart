/// Navigation paths. Kept free of widget imports so any layer may use them.
abstract final class AppRoutes {
  static const String startup = '/';
  static const String login = '/login';
  static const String library = '/library';
  static const String player = '/player';
  static const String series = '/series';
  static const String settings = '/settings';

  static String playerFor(String itemId) => '$player/$itemId';
  static String seriesFor(String seriesId) => '$series/$seriesId';
}
