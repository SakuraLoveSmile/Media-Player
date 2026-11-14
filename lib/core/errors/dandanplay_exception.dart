import 'app_error.dart';

/// The only exception the DandanPlay data layer throws (S17 弹幕).
///
/// Mirrors [EmbyException] / [MoviePilotException] so the UI shares one error
/// taxonomy (contract §6). DandanPlay is a public, unauthenticated API, so
/// `toString` never carries a token; the query (which holds the searched
/// title) is dropped by the redacted log line before it gets here.
class DandanPlayException implements Exception {
  DandanPlayException(this.code, {this.message = ''});

  final AppErrorCode code;
  final String message;

  bool get retryable => code.retryable;

  @override
  String toString() =>
      'DandanPlayException(${code.name}${message.isEmpty ? '' : ': $message'})';
}
