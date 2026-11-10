import 'app_error.dart';

/// The only exception the MoviePilot data layer throws.
///
/// Mirrors [EmbyException] so the UI can share one error taxonomy
/// (contract §6). `toString` never carries the URL or the API token, so it is
/// safe in logs; the server-provided [message] is kept for diagnostics and is
/// only ever shown after the caller maps it.
class MoviePilotException implements Exception {
  MoviePilotException(this.code, {this.message = ''});

  final AppErrorCode code;
  final String message;

  bool get retryable => code.retryable;

  @override
  String toString() =>
      'MoviePilotException(${code.name}${message.isEmpty ? '' : ': $message'})';
}
