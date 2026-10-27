/// Normalizes user-entered server addresses (contract §1.2).
///
/// Rules: trim, prepend `http://` when the scheme is missing, accept only
/// http/https, strip trailing slashes and drop query/fragment/userinfo.
/// Invalid input returns `null` — the UI validates at the input boundary, so
/// the data layer never receives an unparsable address.
abstract final class UrlNormalizer {
  static final RegExp _hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://');
  static final RegExp _whitespace = RegExp(r'\s');

  /// Returns a canonical base URL without a trailing slash, or `null`.
  static String? normalize(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return null;
    // A user-typed address never contains raw whitespace; refusing it here
    // also stops Uri from percent-encoding it into a bogus host.
    if (_whitespace.hasMatch(value)) return null;

    if (!_hasScheme.hasMatch(value)) {
      value = 'http://$value';
    }

    final uri = Uri.tryParse(value);
    if (uri == null) return null;

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    if (uri.host.isEmpty || _whitespace.hasMatch(uri.host)) return null;

    var path = uri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }

    // Rebuild instead of `replace` so query/fragment/userinfo are dropped and
    // IPv6 hosts keep their brackets.
    return Uri(
      scheme: scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: path,
    ).toString();
  }

  /// Candidate bases in probe order: the normalized value, then the same value
  /// under a `/emby` reverse-proxy sub-path.
  static List<String> candidates(String raw) {
    final base = normalize(raw);
    if (base == null) return const <String>[];
    if (base.toLowerCase().endsWith('/emby')) return <String>[base];
    return <String>[base, '$base/emby'];
  }
}
