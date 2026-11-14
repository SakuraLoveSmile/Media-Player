import '../models/live_tv_channel.dart';
import '../models/live_tv_program.dart';

/// Live TV read model used by the UI (S21).
///
/// Declared separately from [LiveTvRepository] so the live page can be tested
/// with a fake and never touch HTTP, exactly like `LibraryService`.
abstract interface class LiveTvService {
  /// `GET /LiveTv/Channels`: every channel the user may watch, with its number,
  /// primary image tag and airing program when the server carries guide data.
  Future<List<LiveTvChannel>> channels();

  /// `GET /LiveTv/Programs`: the EPG. [channelId] narrows the query to one
  /// channel (`ChannelIds`); null lists the whole guide.
  Future<List<LiveTvProgram>> programs({String? channelId});

  /// Channel logo URL with `api_key` (same `/Items/{id}/Images/Primary` shape as
  /// the library posters). Null when logged out.
  Uri? channelImageUrl(String channelId, {String? tag, int? maxWidth});
}
