import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../core/errors/app_error.dart';
import '../../core/errors/emby_exception.dart';
import '../../core/logging/redact.dart';
import 'emby_headers.dart';

typedef LogSink = void Function(String line);

/// Sole outbound HTTP path for Emby API calls (contract §1.4, §10.4).
///
/// Every call takes an absolute [Uri]; there is deliberately no shared
/// `baseUrl`, so a LAN request can never leak onto the WAN endpoint or the
/// other way round.
class EmbyHttpClient {
  EmbyHttpClient(
    this._dio, {
    required this.deviceId,
    this.defaultConnectTimeout = const Duration(seconds: 5),
    this.defaultReceiveTimeout = const Duration(seconds: 10),
    LogSink? logSink,
  }) : _log = logSink ?? _discard;

  final Dio _dio;
  final String deviceId;
  final Duration defaultConnectTimeout;
  final Duration defaultReceiveTimeout;
  final LogSink _log;

  static void _discard(String _) {}

  Future<Map<String, dynamic>> getJson(
    Uri url, {
    String? token,
    Duration? timeout,
  }) {
    return _send(method: 'GET', url: url, token: token, timeout: timeout);
  }

  Future<Map<String, dynamic>> postJson(
    Uri url, {
    Object? body,
    String? token,
    String? authorization,
    Duration? timeout,
  }) {
    return _send(
      method: 'POST',
      url: url,
      body: body,
      token: token,
      authorization: authorization,
      timeout: timeout,
    );
  }

  Future<Map<String, dynamic>> _send({
    required String method,
    required Uri url,
    Object? body,
    String? token,
    String? authorization,
    Duration? timeout,
  }) async {
    _log('$method ${redactUrl(url.toString())}');

    try {
      final response = await _dio.requestUri<Object?>(
        url,
        data: body,
        options: Options(
          method: method,
          headers: <String, String>{
            Headers.acceptHeader: Headers.jsonContentType,
            Headers.contentTypeHeader: Headers.jsonContentType,
            EmbyHeaders.deviceId: deviceId,
            EmbyHeaders.token: ?token,
            EmbyHeaders.authorization: ?authorization,
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

  Map<String, dynamic> _decode(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    // `GET /Sessions` answers with a bare array (contract §3.5), while the
    // session API exposes maps only. Normalise arrays into the same `Items`
    // envelope the rest of the API uses instead of failing the call.
    if (data is List) return _items(data);
    if (data is String) {
      if (data.trim().isEmpty) return const <String, dynamic>{};
      final Object? decoded;
      try {
        decoded = jsonDecode(data);
      } on FormatException {
        throw EmbyException(
          AppErrorCode.serverError,
          message: 'invalid JSON response',
        );
      }
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      if (decoded is List) return _items(decoded);
      throw EmbyException(
        AppErrorCode.serverError,
        message: 'unexpected JSON shape',
      );
    }
    return const <String, dynamic>{};
  }

  static Map<String, dynamic> _items(List<dynamic> list) =>
      <String, dynamic>{'Items': List<Object?>.from(list)};

  EmbyException _map(DioException error) {
    switch (error.type) {
      case DioExceptionType.badCertificate:
        return EmbyException(AppErrorCode.tlsUntrusted,
            message: 'bad certificate');
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return EmbyException(
          AppErrorCode.networkUnreachable,
          message: error.type.name,
        );
      case DioExceptionType.cancel:
        return EmbyException(AppErrorCode.networkUnreachable,
            message: 'cancelled');
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        if (_isTls(error.error)) {
          return EmbyException(AppErrorCode.tlsUntrusted,
              message: 'TLS handshake failed');
        }
        return EmbyException(
          AppErrorCode.networkUnreachable,
          message: error.type.name,
        );
      case DioExceptionType.badResponse:
        final status = error.response?.statusCode ?? 0;
        return EmbyException(_fromStatus(status), message: 'HTTP $status');
    }
  }

  static bool _isTls(Object? error) =>
      error is HandshakeException || error is TlsException;

  static AppErrorCode _fromStatus(int status) {
    switch (status) {
      case 401:
        return AppErrorCode.unauthorized;
      case 403:
        return AppErrorCode.forbidden;
      case 404:
        return AppErrorCode.notFound;
      default:
        return AppErrorCode.serverError;
    }
  }
}
