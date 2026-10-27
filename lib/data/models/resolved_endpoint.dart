import '../../core/network/endpoint_kind.dart';

/// Result of a successful `System/Info/Public` probe (contract §1.3).
class ResolvedEndpoint {
  const ResolvedEndpoint({
    required this.baseUrl,
    required this.kind,
    required this.serverId,
    required this.resolvedAt,
  });

  /// Normalized base without a trailing slash, including any `/emby` prefix
  /// that the probe required.
  final String baseUrl;
  final EndpointKind kind;
  final String serverId;
  final DateTime resolvedAt;

  Uri resolve(String pathAndQuery) {
    final suffix = pathAndQuery.startsWith('/') ? pathAndQuery : '/$pathAndQuery';
    return Uri.parse('$baseUrl$suffix');
  }

  @override
  String toString() => 'ResolvedEndpoint(${kind.name}, $baseUrl)';
}
