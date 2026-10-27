import 'app_error.dart';
import '../network/endpoint_kind.dart';

/// Why one candidate base failed during endpoint resolution (contract §1.3).
///
/// The top-level error is always `networkUnreachable` when every candidate
/// fails; the real reason per endpoint is kept here so the UI can explain it.
class EndpointFailure {
  const EndpointFailure({
    required this.kind,
    required this.baseUrl,
    required this.code,
    this.message = '',
  });

  final EndpointKind kind;
  final String baseUrl;
  final AppErrorCode code;
  final String message;

  @override
  String toString() =>
      'EndpointFailure(${kind.name}, $baseUrl, ${code.name})';
}
