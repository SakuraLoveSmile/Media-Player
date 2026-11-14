import 'dart:io';
import 'dart:typed_data';

import '../../core/errors/app_error.dart';
import '../../core/errors/emby_exception.dart';
import '../auth/api_session.dart';
import '../models/media_stream.dart';
import '../models/resolved_endpoint.dart';

/// Raw-byte fetch mirroring [EmbyHttpClient.getBytes]; injected for tests.
typedef SubtitleFetch = Future<Uint8List> Function(
  Uri url, {
  String? token,
  Duration? timeout,
});

/// External subtitle delivery (contract §3.7): resolve the server URL, download
/// once, cache by item + source + stream index, and hand a local file to the
/// engine so player auth differences never matter.
abstract interface class SubtitleService {
  /// Local path of the external subtitle for [stream]; downloads on first use.
  Future<String> externalFile({
    required String itemId,
    required String mediaSourceId,
    required MediaStream stream,
  });
}

class SubtitleRepository implements SubtitleService {
  // Public named parameters (`directory`, `fetch`) with private fields, the
  // same trade-off as PlayerController's constructor.
  // ignore_for_file: prefer_initializing_formals
  SubtitleRepository(
    this._session, {
    required Directory directory,
    required SubtitleFetch fetch,
  }) : _directory = directory,
       _fetch = fetch;

  final ApiSession _session;
  final Directory _directory;
  final SubtitleFetch _fetch;

  @override
  Future<String> externalFile({
    required String itemId,
    required String mediaSourceId,
    required MediaStream stream,
  }) async {
    final endpoint = _session.endpoint;
    final token = _session.accessToken;
    if (endpoint == null || token == null || token.isEmpty) {
      throw EmbyException(AppErrorCode.unauthorized);
    }

    final String extension = _extension(stream.codec);
    final File file = File(
      '${_directory.path}/${itemId}_${mediaSourceId}_${stream.index}.$extension',
    );
    if (file.existsSync()) return file.path;

    final Uri url = _url(endpoint, itemId, mediaSourceId, stream, token);
    final Uint8List bytes;
    try {
      bytes = await _fetch(url, token: token);
    } on EmbyException {
      rethrow;
    } catch (_) {
      throw EmbyException(AppErrorCode.subtitleFailed);
    }
    if (bytes.isEmpty) throw EmbyException(AppErrorCode.subtitleFailed);

    _directory.createSync(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Prefer the server-provided DeliveryUrl; fall back to the documented
  /// subtitle stream path (contract §3.7). Same endpoint as the session.
  Uri _url(
    ResolvedEndpoint endpoint,
    String itemId,
    String mediaSourceId,
    MediaStream stream,
    String token,
  ) {
    final String? delivery = stream.deliveryUrl;
    Uri uri;
    if (delivery != null && delivery.isNotEmpty) {
      uri = delivery.startsWith('http://') || delivery.startsWith('https://')
          ? Uri.parse(delivery)
          : endpoint.resolve(delivery);
    } else {
      uri = endpoint.resolve(
        '/Videos/$itemId/$mediaSourceId/Subtitles/${stream.index}'
        '/Stream.${_extension(stream.codec)}',
      );
    }
    if (uri.queryParameters.containsKey('api_key')) return uri;
    return uri.replace(
      queryParameters: <String, String>{
        ...uri.queryParameters,
        'api_key': token,
      },
    );
  }

  static String _extension(String? codec) {
    switch (codec?.toLowerCase()) {
      case 'ass':
      case 'ssa':
        return 'ass';
      case 'subrip':
      case 'srt':
        return 'srt';
      case 'pgssub':
        return 'sup';
      default:
        return codec?.toLowerCase() ?? 'srt';
    }
  }
}
