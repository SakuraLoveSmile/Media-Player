import 'dart:io';

import 'package:media_player_watch_server/watch_server.dart';

Future<void> main() async {
  final env = Platform.environment;
  final raw = env['EMBY_URL'];
  final id = env['EMBY_SERVER_ID'];
  if (raw == null || id == null || id.isEmpty) {
    stderr.writeln('Set EMBY_URL and EMBY_SERVER_ID before starting.');
    exitCode = 64;
    return;
  }
  try {
    final server = WatchServer(
      verifier: EmbyWatchVerifier(baseUrl: Uri.parse(raw), serverId: id),
    );
    await server.start(
      address: InternetAddress(env['HOST'] ?? '127.0.0.1'),
      port: int.parse(env['PORT'] ?? '18444'),
    );
    stdout.writeln(
      'MediaPlayer watch service listening on port ${server.port}',
    );
    ProcessSignal.sigterm.watch().listen((_) async {
      await server.close();
      exit(0);
    });
    ProcessSignal.sigint.watch().listen((_) async {
      await server.close();
      exit(0);
    });
  } catch (_) {
    stderr.writeln(
      'Unable to start watch service. Check configuration and port.',
    );
    exitCode = 64;
  }
}
