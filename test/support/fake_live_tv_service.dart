import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/emby_exception.dart';
import 'package:media_player/data/livetv/live_tv_service.dart';
import 'package:media_player/data/models/live_tv_channel.dart';
import 'package:media_player/data/models/live_tv_program.dart';

/// Configurable Live TV double for widget/controller tests (S21). No HTTP.
class FakeLiveTvService implements LiveTvService {
  FakeLiveTvService({
    List<LiveTvChannel>? channelResults,
    List<LiveTvProgram>? programResults,
    this.failure,
    this.unauthorized = false,
  }) : channelResults = channelResults ?? const <LiveTvChannel>[],
       programResults = programResults ?? const <LiveTvProgram>[];

  List<LiveTvChannel> channelResults;
  List<LiveTvProgram> programResults;

  /// Thrown by [channels] / [programs] when set.
  Object? failure;
  bool unauthorized;

  int channelCalls = 0;
  final List<String?> programRequests = <String?>[];

  /// Null keeps [channelImageUrl] null so tiles render their placeholder. Set
  /// it to exercise the logo path.
  String? imageHost;
  String imageToken = 'token-1';

  @override
  Future<List<LiveTvChannel>> channels() async {
    channelCalls++;
    _maybeThrow();
    return channelResults;
  }

  @override
  Future<List<LiveTvProgram>> programs({String? channelId}) async {
    programRequests.add(channelId);
    _maybeThrow();
    if (channelId == null || channelId.isEmpty) return programResults;
    return programResults
        .where((p) => p.channelId == channelId)
        .toList(growable: false);
  }

  @override
  Uri? channelImageUrl(String channelId, {String? tag, int? maxWidth}) {
    final host = imageHost;
    if (host == null) return null;
    return Uri.parse(
      'http://$host/Items/$channelId/Images/Primary'
      '?maxWidth=${maxWidth ?? ''}&tag=${tag ?? ''}&api_key=$imageToken',
    );
  }

  void _maybeThrow() {
    if (unauthorized) {
      throw EmbyException(AppErrorCode.unauthorized);
    }
    final error = failure;
    if (error != null) throw error;
  }
}

/// A channel with an airing program spanning [now], so the progress bar renders
/// deterministically in widget tests.
LiveTvChannel fakeChannel(
  String id, {
  String name = '',
  String? number,
  bool withProgram = true,
}) {
  final now = DateTime.now();
  return LiveTvChannel(
    id: id,
    name: name.isEmpty ? 'Channel $id' : name,
    number: number,
    currentProgram: withProgram
        ? LiveTvProgram(
            id: 'prog-$id',
            name: 'Program $id',
            startDate: now.subtract(const Duration(minutes: 30)),
            endDate: now.add(const Duration(minutes: 30)),
            channelId: id,
          )
        : null,
  );
}
