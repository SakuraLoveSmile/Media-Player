import '../../core/network/endpoint_kind.dart';
import '../models/server_profile.dart';

/// PlaybackInfo negotiation inputs for the current endpoint (contract §3.3,
/// §10.9 e).
///
/// Pure on purpose: the playback path reads the in-memory profile and must not
/// await a disk read per request, so a missing profile is handled here instead
/// of being loaded.
class PlaybackOptions {
  const PlaybackOptions({
    required this.maxStreamingBitrate,
    required this.enableTranscoding,
  });

  final int maxStreamingBitrate;
  final bool enableTranscoding;

  /// Emby's "no limit" value, used whenever direct play must be favoured.
  static const int unrestrictedBitrate = 1000000000;

  static PlaybackOptions forEndpoint(
    EndpointKind kind,
    ServerProfile? profile,
  ) {
    // Missing profile or a non-positive cap is treated as a LAN endpoint: ask
    // for the highest bitrate and retry logic still applies (contract §10.9 e).
    if (profile == null || profile.wanBitrateCapMbps <= 0) {
      return const PlaybackOptions(
        maxStreamingBitrate: unrestrictedBitrate,
        enableTranscoding: true,
      );
    }
    if (kind == EndpointKind.lan) {
      return const PlaybackOptions(
        maxStreamingBitrate: unrestrictedBitrate,
        enableTranscoding: true,
      );
    }
    if (profile.forceDirectOnWan) {
      return const PlaybackOptions(
        maxStreamingBitrate: unrestrictedBitrate,
        enableTranscoding: false,
      );
    }
    return PlaybackOptions(
      maxStreamingBitrate: profile.wanBitrateCapMbps * 1000000,
      enableTranscoding: true,
    );
  }
}
