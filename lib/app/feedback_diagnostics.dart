import 'package:dio/dio.dart';
import 'package:feedback_widget/feedback_widget.dart';

/// App-wide diagnostics buffer shared by the API client, the exception
/// capture and the feedback layer.
///
/// The feedback component's `logProvider` exports only recent, whitelisted
/// host events (request method + normalized path summary, status code,
/// duration, exception markers). Request bodies, headers, credentials and full
/// URLs never enter the buffer — the recorder's API cannot accept them.
final FeedbackDiagnosticsRecorder feedbackDiagnostics =
    FeedbackDiagnosticsRecorder(filename: 'media-player-diagnostics.jsonl');

/// `logProvider` wired into [FeedbackConfig] by `buildFeedbackConfig`.
///
/// Returns one JSONL attachment with the buffered host events, or an empty
/// list when nothing has been recorded. Diagnostics are best-effort: failures
/// never block a submission because the recorder swallows its own errors.
List<FeedbackLogFile> provideFeedbackDiagnostics() =>
    feedbackDiagnostics.provide();

/// Normalizes an API request into a stable, log-safe event identifier.
///
/// Only the first path segments are kept; numeric ids and long hex/uuid-like
/// segments collapse to `id`, query strings and the host are never included,
/// and everything outside `[A-Za-z0-9_.-]` becomes `_`. The result satisfies
/// the recorder's event-name whitelist and stays within 64 characters.
String feedbackDiagnosticEvent(String method, String path) {
  // Dio hands us absolute URLs; strip host, query and fragment before any
  // segment can leak into the event name (tokens live in query strings).
  final Uri? uri = Uri.tryParse(path);
  final String rawPath;
  if (uri != null && (uri.hasScheme || uri.host.isNotEmpty)) {
    rawPath = uri.path;
  } else {
    rawPath = path.split('?').first.split('#').first;
  }
  final List<String> segments = <String>[];
  for (final String raw in rawPath.split('/')) {
    if (raw.isEmpty) continue;
    if (segments.length == 4) break;
    final String segment = _safeSegment(raw);
    if (segment.isNotEmpty) segments.add(segment);
  }
  final String prefix = 'http.${method.toLowerCase()}';
  final String event =
      segments.isEmpty ? prefix : '$prefix.${segments.join('_')}';
  return event.length <= 64 ? event : event.substring(0, 64);
}

final RegExp _numericSegment = RegExp(r'^[0-9]+$');
final RegExp _opaqueSegment = RegExp(r'^[0-9a-fA-F-]{8,}$');

String _safeSegment(String segment) {
  if (_numericSegment.hasMatch(segment) || _opaqueSegment.hasMatch(segment)) {
    return 'id';
  }
  final String safe = segment.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
  return safe.isEmpty ? '' : safe;
}

/// Dio interceptor that feeds the host diagnostics buffer with real API
/// traffic: method + normalized path, HTTP status and duration. Network and
/// HTTP failures are recorded as error/warn entries (never with bodies, headers
/// or the full URL). The original request/response/error flow is untouched.
class FeedbackDioInterceptor extends Interceptor {
  FeedbackDioInterceptor([FeedbackDiagnosticsRecorder? recorder])
      : recorder = recorder ?? feedbackDiagnostics;

  /// Recorder that receives the events (tests may inject their own).
  final FeedbackDiagnosticsRecorder recorder;

  static const String _startedAtKey = 'feedback.startedAtMicros';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startedAtKey] = DateTime.now().microsecondsSinceEpoch;
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _record(response.requestOptions, response.statusCode, failed: false);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _record(err.requestOptions, err.response?.statusCode, failed: true);
    handler.next(err);
  }

  void _record(
    RequestOptions options,
    int? status, {
    required bool failed,
  }) {
    int? durationMs;
    final Object? startedAt = options.extra[_startedAtKey];
    if (startedAt is int) {
      final int micros = DateTime.now().microsecondsSinceEpoch - startedAt;
      if (micros >= 0) durationMs = (micros / 1000).round();
    }
    recorder.record(
      level: failed ? 'error' : (status != null && status >= 400 ? 'warn' : 'info'),
      event: feedbackDiagnosticEvent(options.method, options.path),
      code: failed ? (status == null ? 'network' : 'http_error') : null,
      status: status,
      durationMs: durationMs,
    );
  }
}
