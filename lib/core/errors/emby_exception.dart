import 'app_error.dart';
import 'endpoint_failure.dart';
import '../network/endpoint_kind.dart';

/// The only exception the data layer throws (contract §6).
///
/// `toString` never includes URLs or tokens so it is safe in logs.
class EmbyException implements Exception {
  EmbyException(
    this.code, {
    this.message = '',
    this.endpointKind,
    List<EndpointFailure> failures = const <EndpointFailure>[],
  }) : failures = List.unmodifiable(failures);

  final AppErrorCode code;
  final String message;
  final EndpointKind? endpointKind;
  final List<EndpointFailure> failures;

  bool get retryable => code.retryable;

  @override
  String toString() => 'EmbyException(${code.name}${message.isEmpty ? '' : ': $message'})';
}
