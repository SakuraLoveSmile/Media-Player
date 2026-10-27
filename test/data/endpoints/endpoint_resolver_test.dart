import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/core/errors/emby_exception.dart';
import 'package:media_player/core/network/endpoint_kind.dart';
import 'package:media_player/data/endpoints/endpoint_probe.dart';
import 'package:media_player/data/endpoints/endpoint_resolver.dart';
import 'package:media_player/data/models/server_profile.dart';

class FakeProbe implements EndpointProbe {
  FakeProbe(this.responder);

  final Future<String?> Function(String base, Duration timeout) responder;
  int calls = 0;
  final List<String> bases = <String>[];

  @override
  Future<String?> fetchServerId(String base, {required Duration timeout}) {
    calls++;
    bases.add(base);
    return responder(base, timeout);
  }
}

void main() {
  late DateTime now;

  EndpointResolver buildResolver(
    FakeProbe probe, {
    Duration? timeout,
  }) {
    return EndpointResolver(
      probe: probe,
      clock: () => now,
      lanTimeout: timeout ?? const Duration(milliseconds: 60),
      wanTimeout: timeout ?? const Duration(milliseconds: 60),
    );
  }

  const profile = ServerProfile(
    serverId: 's1',
    name: 'Home',
    lanUrl: 'http://192.168.1.10:8096',
    wanUrl: 'https://emby.example.com',
  );

  setUp(() {
    now = DateTime(2026, 10, 27, 12);
  });

  test('prefers the LAN and returns the normalized base', () async {
    final probe = FakeProbe((base, _) async => 's1');
    final resolved = await buildResolver(probe).resolve(profile);

    expect(resolved.kind, EndpointKind.lan);
    expect(resolved.baseUrl, 'http://192.168.1.10:8096');
    expect(resolved.serverId, 's1');
    expect(resolved.resolvedAt, now);
    expect(probe.calls, 1);
  });

  test('accepts a /emby reverse-proxy prefix', () async {
    final probe = FakeProbe((base, _) async {
      return base.endsWith('/emby') ? 's1' : null;
    });
    final resolved = await buildResolver(probe).resolve(profile);

    expect(resolved.baseUrl, 'http://192.168.1.10:8096/emby');
    expect(probe.calls, 2);
  });

  test('falls back to WAN when the LAN probe hangs', () async {
    final probe = FakeProbe((base, _) async {
      if (base.startsWith('http://192.168')) return Completer<String?>().future;
      return 's1';
    });

    final stopwatch = Stopwatch()..start();
    final resolved = await buildResolver(probe).resolve(profile);
    stopwatch.stop();

    expect(resolved.kind, EndpointKind.wan);
    expect(resolved.baseUrl, 'https://emby.example.com');
    expect(stopwatch.elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 50)));
  });

  test('aggregates a failure for every candidate', () async {
    final probe = FakeProbe((base, _) async {
      throw EmbyException(AppErrorCode.networkUnreachable, message: 'boom');
    });

    await expectLater(
      buildResolver(probe).resolve(profile),
      throwsA(isA<EmbyException>()
          .having((e) => e.code, 'code', AppErrorCode.networkUnreachable)
          .having((e) => e.failures.length, 'failures', 4)
          .having((e) => e.failures.first.message, 'message', 'boom')),
    );
  });

  test('adopts the probe id when the profile has none yet', () async {
    const fresh = ServerProfile(
      serverId: '',
      name: '',
      lanUrl: 'http://192.168.1.10:8096',
    );
    final probe = FakeProbe((base, _) async => 'discovered');

    final resolved = await buildResolver(probe).resolve(fresh);

    expect(resolved.serverId, 'discovered');
  });

  test('rejects a mismatching server id and keeps probing', () async {
    final probe = FakeProbe((base, _) async {
      return base.startsWith('http://192.168') ? 'someone-else' : 's1';
    });

    final resolved = await buildResolver(probe).resolve(profile);

    expect(resolved.kind, EndpointKind.wan);
    expect(resolved.serverId, 's1');
  });

  test('reports serverMismatch when no candidate matches', () async {
    final probe = FakeProbe((base, _) async => 'someone-else');

    await expectLater(
      buildResolver(probe).resolve(profile),
      throwsA(isA<EmbyException>().having(
        (e) => e.failures.every((f) => f.code == AppErrorCode.serverMismatch),
        'all mismatched',
        isTrue,
      )),
    );
  });

  test('a LAN-only preference never touches the WAN', () async {
    final probe = FakeProbe((base, _) async {
      throw EmbyException(AppErrorCode.networkUnreachable);
    });

    await expectLater(
      buildResolver(probe)
          .resolve(profile.copyWith(preference: EndpointPreference.lan)),
      throwsA(isA<EmbyException>()),
    );
    expect(probe.calls, 2);
    expect(probe.bases.every((b) => b.startsWith('http://192.168')), isTrue);
  });

  test('a profile without addresses fails without probing', () async {
    final probe = FakeProbe((base, _) async => 's1');

    await expectLater(
      buildResolver(probe)
          .resolve(const ServerProfile(serverId: 's1', name: 'Home')),
      throwsA(isA<EmbyException>().having(
        (e) => e.message,
        'message',
        'no address configured',
      )),
    );
    expect(probe.calls, 0);
  });

  test('caches the result for five minutes', () async {
    final probe = FakeProbe((base, _) async => 's1');
    final resolver = buildResolver(probe);

    await resolver.resolve(profile);
    final firstCalls = probe.calls;

    now = now.add(const Duration(minutes: 4, seconds: 59));
    final cached = await resolver.resolve(profile);
    expect(probe.calls, firstCalls);
    expect(cached.baseUrl, 'http://192.168.1.10:8096');

    now = now.add(const Duration(seconds: 2));
    await resolver.resolve(profile);
    expect(probe.calls, greaterThan(firstCalls));
  });

  test('forceRefresh bypasses the cache', () async {
    final probe = FakeProbe((base, _) async => 's1');
    final resolver = buildResolver(probe);

    await resolver.resolve(profile);
    final firstCalls = probe.calls;
    await resolver.resolve(profile, forceRefresh: true);

    expect(probe.calls, greaterThan(firstCalls));
  });

  test('shares one probe round between concurrent callers', () async {
    final probe = FakeProbe((base, _) async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return 's1';
    });
    final resolver = buildResolver(probe);

    final results = await Future.wait(<Future<Object?>>[
      for (var i = 0; i < 5; i++) resolver.resolve(profile),
    ]);

    expect(probe.calls, 1);
    expect(results, hasLength(5));
  });

  test('invalidate forces a new probe', () async {
    final probe = FakeProbe((base, _) async => 's1');
    final resolver = buildResolver(probe);

    await resolver.resolve(profile);
    resolver.invalidate(serverId: 's1');
    await resolver.resolve(profile);

    expect(probe.calls, 2);
  });

  test('invalidate ignores a different server', () async {
    final probe = FakeProbe((base, _) async => 's1');
    final resolver = buildResolver(probe);

    await resolver.resolve(profile);
    resolver.invalidate(serverId: 'other');
    await resolver.resolve(profile);

    expect(probe.calls, 1);
  });
}
