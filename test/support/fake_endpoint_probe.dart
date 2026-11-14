import 'package:media_player/data/endpoints/endpoint_probe.dart';

/// Reachability double for the servers list (S64).
class FakeEndpointProbe implements EndpointProbe {
  FakeEndpointProbe({this.online = const <String>{}});

  /// Base addresses that answer with a server id.
  final Set<String> online;

  /// Bases probed, in order.
  final List<String> requests = <String>[];

  @override
  Future<String?> fetchServerId(
    String base, {
    required Duration timeout,
  }) async {
    requests.add(base);
    return online.contains(base) ? 'server-id' : null;
  }
}
