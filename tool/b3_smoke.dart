// B3 smoke: probe -> login -> persist -> restart -> restore -> views -> logout
// against a real Emby server.
//
// Credentials come from the environment and are never written to disk:
//   EMBY_LAN_URL=http://<host>:<port> EMBY_USER=<user> EMBY_PASS=<pass> \
//     dart run tool/b3_smoke.dart
//
// Output is deliberately limited to endpoint kind, prefixes of server/device
// ids and counts — no token, password or full URL.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/emby_exception.dart';
import 'package:media_player/data/api/emby_http_client.dart';
import 'package:media_player/data/auth/auth_repository.dart';
import 'package:media_player/data/endpoints/endpoint_probe.dart';
import 'package:media_player/data/endpoints/endpoint_resolver.dart';
import 'package:media_player/data/models/server_profile.dart';
import 'package:media_player/data/storage/device_id_store.dart';
import 'package:media_player/data/storage/file_key_value_store.dart';
import 'package:media_player/data/storage/key_value_store.dart';
import 'package:media_player/data/storage/profile_store.dart';
import 'package:media_player/data/storage/session_store.dart';
import 'package:media_player/data/storage/token_store.dart';

Future<void> main(List<String> args) async {
  final lanUrl = Platform.environment['EMBY_LAN_URL'];
  final username = Platform.environment['EMBY_USER'];
  final password = Platform.environment['EMBY_PASS'];

  if (lanUrl == null || username == null || password == null) {
    stderr.writeln(
      'usage: EMBY_LAN_URL=... EMBY_USER=... EMBY_PASS=... '
      'dart run tool/b3_smoke.dart',
    );
    exit(2);
  }

  final workspace = await Directory.systemTemp.createTemp('b3_smoke');
  var failures = 0;

  void pass(String message) => stdout.writeln('PASS $message');
  void skip(String message) => stdout.writeln('SKIP $message');
  void fail(String message, Object error) {
    failures++;
    stdout.writeln('FAIL $message: $error');
  }

  stdout.writeln('B3 smoke');
  stdout.writeln('- lan address: provided');
  stdout.writeln('- wan address: skipped (not configured)');

  try {
    // --- Wrong password must not store anything -------------------------
    {
      final store = FileKeyValueStore(File('${workspace.path}/wrong/store.json'));
      final repository = await _buildRepository(store, lanUrl);
      final profile = ServerProfile(
        serverId: '',
        name: 'smoke',
        lanUrl: lanUrl,
      );
      try {
        await repository.login(
          username: username,
          password: 'definitely-not-the-password',
          profile: profile,
        );
        fail('wrong password', 'login unexpectedly succeeded');
      } on EmbyException catch (error) {
        if (error.code == AppErrorCode.unauthorized) {
          final token = await store.read(TokenStore.key);
          if (token == null) {
            pass('wrong password rejected, no token stored');
          } else {
            fail('wrong password', 'token was stored despite 401');
          }
        } else {
          fail('wrong password', 'unexpected code ${error.code}');
        }
      }
      await repository.dispose();
    }

    // --- Real login, then "restart" and restore --------------------------
    final store = FileKeyValueStore(File('${workspace.path}/main/store.json'));
    String userId;

    {
      final repository = await _buildRepository(store, lanUrl);
      final session = await repository.login(
        username: username,
        password: password,
        profile: ServerProfile(serverId: '', name: 'smoke', lanUrl: lanUrl),
      );
      final profile = await ProfileStore(store).read();
      final endpoint = repository.endpoint;

      if (endpoint == null || profile == null || profile.serverId != endpoint.serverId) {
        fail('probe+login', 'endpoint/public profile missing');
        return;
      }

      userId = session.userId;
      pass(
        'probe+login: endpoint=${endpoint.kind.name} '
        'server=${_prefix(endpoint.serverId)} '
        'device=${_prefix(session.deviceId)} user=${session.userName}',
      );
      await repository.dispose();
    }

    {
      // New objects over the same storage = app restart.
      final repository = await _buildRepository(store, lanUrl);
      final restored = await repository.restore();
      if (restored == null || restored.userId != userId) {
        fail('restart restore', 'session not recovered');
      } else {
        pass('restart restore: endpoint=${repository.endpoint?.kind.name} user=${restored.userName}');
      }

      final endpoint = repository.endpoint;
      if (endpoint == null) {
        fail('views', 'no endpoint after restore');
      } else {
        final views = await repository.authorizedGet(
          endpoint.resolve('/Users/$userId/Views'),
        );
        pass('views: ${views['TotalRecordCount'] ?? '?'} via token header');
      }

      await repository.logout();
      final tokenGone = await store.read(TokenStore.key) == null;
      final profileKept = await ProfileStore(store).read() != null;
      if (tokenGone && profileKept) {
        pass('logout: token cleared, profile kept');
      } else {
        fail('logout', 'tokenGone=$tokenGone profileKept=$profileKept');
      }
      await repository.dispose();
    }

    skip('serverMismatch: needs a second Emby instance (unit-tested)');
  } finally {
    await workspace.delete(recursive: true);
  }

  stdout.writeln(failures == 0 ? 'RESULT pass' : 'RESULT fail ($failures)');
  exit(failures == 0 ? 0 : 1);
}

Future<AuthRepository> _buildRepository(KeyValueStore store, String lanUrl) async {
  final deviceId = await DeviceIdStore(store).getOrCreate();
  final client = EmbyHttpClient(Dio(), deviceId: deviceId);
  final resolver = EndpointResolver(HttpEndpointProbe(client));
  return AuthRepository(
    client: client,
    resolver: resolver,
    tokenStore: TokenStore(store),
    sessionStore: SessionStore(store),
    profileStore: ProfileStore(store),
    deviceId: deviceId,
    deviceName: '${Platform.operatingSystem} ${Platform.localHostname}',
  );
}

String _prefix(String value) =>
    value.length <= 8 ? value : value.substring(0, 8);
