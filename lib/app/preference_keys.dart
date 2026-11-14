/// Non-secret host preference keys shared by the app layer and the bootstrap
/// (the HTTP client is built before Riverpod providers exist).
abstract final class AppPreferenceKeys {
  /// 忽略 SSL 证书错误 (S32); `'true'` / `'false'`.
  static const String ignoreSsl = 'app.ignoreSsl.v1';

  /// Hidden library view ids (S32), a JSON array of strings.
  static const String hiddenLibraries = 'app.hiddenLibraries.v1';
}
