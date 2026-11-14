import 'package:media_player/data/cast/dlna_cast_service.dart';
import 'package:media_player/data/cast/dlna_device.dart';

/// Cast double for controller/page tests; no LAN sockets.
class FakeDlnaCastService implements DlnaCastService {
  List<DlnaDevice> devices = <DlnaDevice>[];
  Object? discoverError;
  Object? castError;
  int discoverCalls = 0;
  final List<({DlnaDevice device, String url, String title})> casts =
      <({DlnaDevice device, String url, String title})>[];
  final List<DlnaDevice> stops = <DlnaDevice>[];

  @override
  Future<List<DlnaDevice>> discover({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    discoverCalls++;
    if (discoverError != null) throw discoverError!;
    return devices;
  }

  @override
  Future<void> cast(DlnaDevice device, String url, {String title = ''}) async {
    if (castError != null) throw castError!;
    casts.add((device: device, url: url, title: title));
  }

  @override
  Future<void> stop(DlnaDevice device) async {
    stops.add(device);
  }

  @override
  Future<void> pause(DlnaDevice device) async {}

  @override
  Future<void> play(DlnaDevice device) async {}
}
