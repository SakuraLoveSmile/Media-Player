import 'idna.dart';

/// Normalizes user-entered server addresses (contract §1.2).
///
/// Rules: trim, prepend `http://` when the scheme is missing, accept only
/// http/https, strip trailing slashes and drop query/fragment/userinfo.
/// A non-ASCII host (e.g. `上杉九月.cn`) is stored in its ASCII punycode form,
/// because DNS never resolves the percent-encoded host Dart's Uri produces.
/// Invalid input returns `null` — the UI validates at the input boundary, so
/// the data layer never receives an unparsable address.
abstract final class UrlNormalizer {
  static final RegExp _hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://');
  static final RegExp _whitespace = RegExp(r'\s');

  /// Returns a canonical base URL without a trailing slash, or `null`.
  static String? normalize(String raw, {String defaultScheme = 'http'}) {
    final schemePrefix = defaultScheme.toLowerCase();
    if (schemePrefix != 'http' && schemePrefix != 'https') {
      throw ArgumentError.value(defaultScheme, 'defaultScheme');
    }
    var value = raw.trim();
    if (value.isEmpty) return null;
    // A user-typed address never contains raw whitespace; refusing it here
    // also stops Uri from percent-encoding it into a bogus host.
    if (_whitespace.hasMatch(value)) return null;

    if (!_hasScheme.hasMatch(value)) {
      value = '$schemePrefix://$value';
    }

    final uri = Uri.tryParse(value);
    if (uri == null) return null;

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;

    // Uri keeps a non-ASCII host percent-encoded, which DNS cannot resolve;
    // decode it back and store/use the ASCII (punycode) form instead.
    final String host;
    try {
      host = uri.host.contains('%') ? Uri.decodeComponent(uri.host) : uri.host;
    } on ArgumentError {
      return null;
    }
    if (host.isEmpty || _whitespace.hasMatch(host)) return null;
    final asciiHost = Idna.toAscii(host);
    if (asciiHost.isEmpty || _whitespace.hasMatch(asciiHost)) return null;

    var path = uri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }

    // Rebuild instead of `replace` so query/fragment/userinfo are dropped and
    // IPv6 hosts keep their brackets.
    return Uri(
      scheme: scheme,
      host: asciiHost,
      port: uri.hasPort ? uri.port : null,
      path: path,
    ).toString();
  }

  /// Display form of a stored address: the ASCII (punycode) host is rendered
  /// back as Unicode, e.g. `https://media.xn--fhqths51enha.cn` becomes
  /// `https://media.上杉九月.cn`.
  ///
  /// Presentation only — never store or request this string. Input that is not
  /// a usable address is returned trimmed and unchanged.
  static String display(String raw) {
    final canonical = normalize(raw);
    if (canonical == null) return raw.trim();

    final uri = Uri.parse(canonical);
    final unicodeHost = Idna.toUnicode(uri.host);
    if (unicodeHost == uri.host) return canonical;

    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://$unicodeHost$port${uri.path}';
  }

  /// Normalizes a public (WAN) address and forces HTTPS.
  ///
  /// WAN playback goes through frp HTTPS; a saved `http://` host makes the
  /// server answer the PlaybackInfo POST with a 301 instead of the JSON, while
  /// GETs silently follow it — pages load but playback fails. Upgrading here
  /// also repairs old entries saved before the WAN field defaulted to HTTPS.
  /// A missing scheme defaults to HTTPS, so typing just the domain is enough.
  static String? normalizeWan(String raw) {
    final normalized = normalize(raw, defaultScheme: 'https');
    if (normalized == null) return null;
    final uri = Uri.parse(normalized);
    return uri.scheme == 'https'
        ? normalized
        : uri.replace(scheme: 'https').toString();
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
