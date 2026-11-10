import '../../../core/errors/app_error.dart';
import '../../../core/errors/moviepilot_exception.dart';

/// Response-shape unwrapping for the MoviePilot v3 API (求片 plan S2).
///
/// v3 is not uniform: most endpoints answer `{success, data, message}`, some
/// still return a bare list or a bare object, and paged ones answer
/// `{data: {list, total}}`. Unwrapping lives here as pure functions so the
/// repository stays readable and every shape is testable without HTTP.
abstract final class MpEnvelope {
  /// Extracts the payload of a `{success, data}` / bare response.
  ///
  /// A `success: false` body is a business failure, not a transport one: it is
  /// raised as [MoviePilotException] carrying the server's message.
  static Object? unwrap(Object? json, {String what = 'response'}) {
    final body = _asMap(json);
    if (body != null) {
      final success = body['success'];
      if (success is bool && !success) {
        throw MoviePilotException(
          AppErrorCode.serverError,
          message: _message(body) ?? 'MoviePilot rejected $what',
        );
      }
      // `data` may legitimately be null (e.g. DELETE answers `{success: true}`).
      if (body.containsKey('data')) return body['data'];
      return body;
    }
    // Bare list (many v3 collection endpoints) or a scalar/empty body.
    return json;
  }

  /// Unwraps a list payload, tolerating every collection envelope.
  ///
  /// Accepts a bare list, `{success, data: [...]}` and `{data: {list: [...]}}`.
  static List<Map<String, dynamic>> list(Object? json, {String what = 'list'}) {
    final payload = unwrap(json, what: what);
    final direct = _asList(payload);
    if (direct != null) return direct;

    final map = _asMap(payload);
    if (map != null) {
      final nested = _asList(map['list']);
      if (nested != null) return nested;
      // Some endpoints name the collection after the resource.
      for (final key in const <String>['items', 'results', 'data']) {
        final found = _asList(map[key]);
        if (found != null) return found;
      }
      return const <Map<String, dynamic>>[];
    }
    return const <Map<String, dynamic>>[];
  }

  /// Unwraps a single-object payload (`{success, data: {...}}` or bare object).
  static Map<String, dynamic> object(Object? json, {String what = 'object'}) {
    final payload = unwrap(json, what: what);
    return _asMap(payload) ?? const <String, dynamic>{};
  }

  /// Reads the total out of a paged envelope; null when the endpoint does not
  /// report one.
  static int? total(Object? json) {
    final outer = _asMap(json);
    if (outer == null) return null;
    final inner = _asMap(outer['data']);
    final source = inner ?? outer;
    final value = source['total'] ?? source['TotalRecordCount'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    // The v3 collection header carries the total; callers that need it can
    // read it from the response itself (see MoviePilotRepository).
    return null;
  }

  static String? _message(Map<String, dynamic> body) {
    final message = body['message'];
    return message is String && message.isNotEmpty ? message : null;
  }

  static Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static List<Map<String, dynamic>>? _asList(Object? value) {
    if (value is! List) return null;
    return value
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }
}
