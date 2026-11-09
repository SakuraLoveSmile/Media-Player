import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/errors/moviepilot_exception.dart';
import '../../../core/logging/redact.dart';

typedef MpLogSink = void Function(String line);

/// Sole outbound HTTP path for MoviePilot API calls (求片 plan S2).
///
/// Same shape as [EmbyHttpClient]: absolute [Uri] per request (no shared
/// `baseUrl`), plain-text responses decoded here so a malformed body maps to
/// `serverError` instead of an opaque adapter failure, and a redacted log line
/// per request. The differences are the authentication header — MoviePilot
/// takes a single `X-API-KEY` and needs no device identity — and the methods
/// 求片 needs (GET / POST / DELETE).
class MoviePilotHttpClient {
  MoviePilotHttpClient(
    this._dio, {
    this.defaultConnectTimeout = const Duration(seconds: 5),
    this.defaultReceiveTimeout = const Duration(seconds: 10),
    MpLogSink? logSink,
  }) : _log = logSink ?? _discard;

  final Dio _dio;
  final Duration defaultConnectTimeout;
  final Duration defaultReceiveTimeout;
  final MpLogSink _log;

  static void _discard(String _) {}

  Future<Object?> getJson(
    Uri url, {
    required String apiToken,
    Duration? timeout,
  }) {
    return _send(method: 'GET', url: url, apiToken: apiToken, timeout: timeout);
  }

  Future<Object?> postJson(
    Uri url, {
    required String apiToken,
    Object? body,
    Duration? timeout,
  }) {
    return _send(
      method: 'POST',
      url: url,
      apiToken: apiToken,
      body: body,
      timeout: timeout,
    );
  }

  Future<Object?> deleteJson(
    Uri url, {
    required String apiToken,
    Duration? timeout,
  }) {
    return _send(
      method: 'DELETE',
      url: url,
      apiToken: apiToken,
      timeout: timeout,
    );
  }

  Future<Object?> _send({
    required String method,
    required Uri url,
    required String apiToken,
    Object? body,
    Duration? timeout,
  }) async {
    // Path only: the query can carry a `token=` fallback and the header carries
    // the administrator key.
    _log('$method ${redactUrl(url.toString())}');

    try {
      final response = await _dio.requestUri<Object?>(
        url,
        data: body == null ? null : jsonEncode(body),
        options: Options(
          method: method,
          headers: <String, String>{
            Headers.acceptHeader: Headers.jsonContentType,
            Headers.contentTypeHeader: Headers.jsonContentType,
            'X-API-KEY': apiToken,
          },
          // Decode ourselves so a malformed body maps to serverError instead
          // of surfacing as an adapter-level "unknown" network failure.
          responseType: ResponseType.plain,
          followRedirects: true,
          maxRedirects: 5,
          connectTimeout: timeout ?? defaultConnectTimeout,
          receiveTimeout: timeout ?? defaultReceiveTimeout,
          sendTimeout: timeout ?? defaultReceiveTimeout,
        ),
      );
      return _decode(response.data);
    } on DioException catch (error) {
      throw _map(error);
    }
  }

  /// Decodes the plain body into JSON. An empty body becomes null so callers
  /// can treat "no payload" as success, exactly like a `{success: true}` reply.
  Object? _decode(Object? data) {
    if (data is Map || data is List) return data;
    if (data is String) {
      if (data.trim().isEmpty) return null;
      try {
        return jsonDecode(data);
      } on FormatException {
        throw MoviePilotException(
          AppErrorCode.serverError,
          message: 'invalid JSON response',
        );
      }
    }
    return null;
  }

  MoviePilotException _map(DioException error) {
    switch (error.type) {
      case DioExceptionType.badCertificate:
        return MoviePilotException(
          AppErrorCode.tlsUntrusted,
          message: 'bad certificate',
        );
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return MoviePilotException(
          AppErrorCode.networkUnreachable,
          message: error.type.name,
        );
      case DioExceptionType.cancel:
        return MoviePilotException(
          AppErrorCode.networkUnreachable,
          message: 'cancelled',
        );
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        if (_isTls(error.error)) {
          return MoviePilotException(
            AppErrorCode.tlsUntrusted,
            message: 'TLS handshake failed',
          );
        }
        return MoviePilotException(
          AppErrorCode.networkUnreachable,
          message: error.type.name,
        );
      case DioExceptionType.badResponse:
        final status = error.response?.statusCode ?? 0;
        return MoviePilotException(
          _fromStatus(status),
          message: _serverMessage(error.response?.data) ?? 'HTTP $status',
        );
    }
  }

  /// FastAPI puts the human reason in `detail`; v3's own envelope uses
  /// `message`. Truncated so a stack trace cannot reach the UI.
  static String? _serverMessage(Object? data) {
    Object? decoded = data;
    if (data is String) {
      final text = data;
      if (text.trim().isEmpty) return null;
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        // A reverse proxy answered with plain text (an HTML error page, say).
        return text.length > 200 ? text.substring(0, 200) : text;
      }
    }
    if (decoded is! Map) return null;
    final value = decoded['detail'] ?? decoded['message'];
    if (value is! String || value.isEmpty) return null;
    return value.length > 200 ? value.substring(0, 200) : value;
  }

  static bool _isTls(Object? error) =>
      error is HandshakeException || error is TlsException;

  static AppErrorCode _fromStatus(int status) {
    switch (status) {
      case 401:
      case 403:
        // MoviePilot answers 403 for a token that is valid but lacks the
        // administrator role; both mean "fix the settings".
        return AppErrorCode.unauthorized;
      case 404:
        return AppErrorCode.notFound;
      default:
        return AppErrorCode.serverError;
    }
  }
}
