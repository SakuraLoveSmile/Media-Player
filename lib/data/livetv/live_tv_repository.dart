import '../../core/errors/app_error.dart';
import '../../core/errors/emby_exception.dart';
import '../auth/api_session.dart';
import '../models/json_read.dart';
import '../models/live_tv_channel.dart';
import '../models/live_tv_program.dart';
import 'live_tv_service.dart';

/// Emby Live TV queries (S21).
///
/// Mirrors `LibraryRepository`: every request is derived from the session's
/// resolved endpoint so LAN and WAN URLs cannot mix, and failures surface as
/// `EmbyException` for the controller to map to copy. A server without Live TV
/// enabled answers an error, which the page renders as an empty/error state
/// rather than crashing.
class LiveTvRepository implements LiveTvService {
  LiveTvRepository(this._session);

  final ApiSession _session;

  /// `CurrentProgram` drives the airing title + progress bar; `ImageTags` and
  /// `Number` are list presentation. No `MediaSources`/`MediaStreams`: only
  /// playback negotiation asks for those (contract §2).
  static const String channelFields = 'CurrentProgram,ImageTags,Number';

  /// Guide fields for the EPG list. `ChannelId` links a program back to its
  /// channel; the dates drive the schedule and any progress bar.
  static const String programFields = 'ChannelId,StartDate,EndDate,Overview';

  @override
  Future<List<LiveTvChannel>> channels() async {
    final json = await _session.authorizedGet(
      _uri('/LiveTv/Channels', <String, String>{
        'UserId': _userId,
        'Fields': channelFields,
        'AddCurrentProgram': 'true',
        'EnableTotalRecordCount': 'false',
      }),
    );
    return asMapList(json['Items'])
        .map(LiveTvChannel.fromJson)
        .where((channel) => channel.id.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<List<LiveTvProgram>> programs({String? channelId}) async {
    final json = await _session.authorizedGet(
      _uri('/LiveTv/Programs', <String, String>{
        'UserId': _userId,
        'Fields': programFields,
        if (channelId != null && channelId.isNotEmpty) 'ChannelIds': channelId,
        'EnableTotalRecordCount': 'false',
      }),
    );
    return asMapList(json['Items'])
        .map(LiveTvProgram.fromJson)
        .toList(growable: false);
  }

  @override
  Uri? channelImageUrl(String channelId, {String? tag, int? maxWidth}) {
    final endpoint = _session.endpoint;
    final token = _session.accessToken;
    if (endpoint == null || token == null) return null;

    return endpoint
        .resolve('/Items/$channelId/Images/Primary')
        .replace(
          queryParameters: <String, String>{
            if (maxWidth != null) 'maxWidth': '$maxWidth',
            if (tag != null && tag.isNotEmpty) 'tag': tag,
            'quality': '90',
            'api_key': token,
          },
        );
  }

  String get _userId {
    final id = _session.userId;
    if (id == null || id.isEmpty) {
      throw EmbyException(AppErrorCode.unauthorized);
    }
    return id;
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final endpoint = _session.endpoint;
    if (endpoint == null) {
      throw EmbyException(AppErrorCode.unauthorized);
    }
    final uri = endpoint.resolve(path);
    return query == null ? uri : uri.replace(queryParameters: query);
  }
}
