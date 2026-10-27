/// Log helpers that cannot leak credentials (contract §10.6).
library;

/// Keeps scheme/host/port/path and drops query, fragment and userinfo.
Uri redactUri(Uri uri) => Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
    );

String redactUrl(String url) {
  final uri = Uri.tryParse(url);
  return uri == null ? '<unparsable>' : redactUri(uri).toString();
}
