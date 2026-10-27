import 'dart:async';

import '../../core/errors/app_error.dart';
import '../../core/errors/emby_exception.dart';
import '../../core/errors/endpoint_failure.dart';
import '../../core/network/endpoint_kind.dart';
import '../../core/network/url_normalizer.dart';
import '../models/resolved_endpoint.dart';
import '../models/server_profile.dart';
import 'endpoint_probe.dart';

typedef Clock = DateTime Function();

/// Picks the single base URL used by an app run (contract §1.3, §10.3).
///
/// Pure: never writes to disk, so `lastGoodEndpoint` persistence stays in
/// [AuthRepository] and every rule here is unit-testable.
class EndpointResolver {
  EndpointResolver({
    required EndpointProbe probe,
    Clock? clock,
    this.cacheTtl = const Duration(minutes: 5),
    this.lanTimeout = const Duration(milliseconds: 1500),
    this.wanTimeout = const Duration(seconds: 3),
  })  : _probe = probe,
        _clock = clock ?? DateTime.now;

  final EndpointProbe _probe;
  final Clock _clock;
  final Duration cacheTtl;
  final Duration lanTimeout;
  final Duration wanTimeout;

  ResolvedEndpoint? _cached;
  String? _cachedKey;
  DateTime? _cachedAt;

  Future<ResolvedEndpoint>? _inFlight;
  String? _inFlightKey;

  ResolvedEndpoint? get cached => _cached;

  Future<ResolvedEndpoint> resolve(
    ServerProfile profile, {
    bool forceRefresh = false,
  }) {
    final key = _key(profile);

    if (!forceRefresh) {
      final cached = _cached;
      final cachedAt = _cachedAt;
      if (cached != null &&
          _cachedKey == key &&
          cachedAt != null &&
          _clock().difference(cachedAt) < cacheTtl) {
        return Future<ResolvedEndpoint>.value(cached);
      }

      final inFlight = _inFlight;
      if (inFlight != null && _inFlightKey == key) return inFlight;
    }

    final future = _resolve(profile);
    _inFlight = future;
    _inFlightKey = key;

    return future.whenComplete(() {
      if (identical(_inFlight, future)) {
        _inFlight = null;
        _inFlightKey = null;
      }
    });
  }

  void invalidate({String? serverId}) {
    if (serverId != null && _cached?.serverId != serverId) return;
    _cached = null;
    _cachedKey = null;
    _cachedAt = null;
  }

  Future<ResolvedEndpoint> _resolve(ServerProfile profile) async {
    final attempts = _attempts(profile);
    if (attempts.isEmpty) {
      throw EmbyException(
        AppErrorCode.networkUnreachable,
        message: 'no address configured',
      );
    }

    final failures = <EndpointFailure>[];
    final expectedId = profile.serverId;
    final now = _clock();

    for (final attempt in attempts) {
      for (final base in UrlNormalizer.candidates(attempt.rawUrl)) {
        try {
          // The extra margin only guards against an adapter that ignores its
          // own timeout; the probe normally returns first.
          final id = await _probe
              .fetchServerId(base, timeout: attempt.timeout)
              .timeout(attempt.timeout + const Duration(milliseconds: 250));

          if (id == null) {
            failures.add(EndpointFailure(
              kind: attempt.kind,
              baseUrl: base,
              code: AppErrorCode.serverError,
              message: 'not an Emby server',
            ));
            continue;
          }

          if (expectedId.isNotEmpty && id != expectedId) {
            failures.add(EndpointFailure(
              kind: attempt.kind,
              baseUrl: base,
              code: AppErrorCode.serverMismatch,
              message: 'server id mismatch',
            ));
            continue;
          }

          final resolved = ResolvedEndpoint(
            baseUrl: base,
            kind: attempt.kind,
            serverId: id,
            resolvedAt: now,
          );
          _cached = resolved;
          _cachedKey = _key(profile);
          _cachedAt = now;
          return resolved;
        } on TimeoutException {
          failures.add(EndpointFailure(
            kind: attempt.kind,
            baseUrl: base,
            code: AppErrorCode.networkUnreachable,
            message: 'probe timeout',
          ));
        } on EmbyException catch (error) {
          failures.add(EndpointFailure(
            kind: attempt.kind,
            baseUrl: base,
            code: error.code,
            message: error.message,
          ));
        }
      }
    }

    throw EmbyException(
      AppErrorCode.networkUnreachable,
      failures: failures,
    );
  }

  List<_Attempt> _attempts(ServerProfile profile) {
    final lan = profile.lanUrl;
    final wan = profile.wanUrl;

    _Attempt? lanAttempt;
    _Attempt? wanAttempt;
    if (lan != null && lan.isNotEmpty) {
      lanAttempt = _Attempt(EndpointKind.lan, lan, lanTimeout);
    }
    if (wan != null && wan.isNotEmpty) {
      wanAttempt = _Attempt(EndpointKind.wan, wan, wanTimeout);
    }

    switch (profile.preference) {
      case EndpointPreference.auto:
        return <_Attempt>[?lanAttempt, ?wanAttempt];
      case EndpointPreference.lan:
        return <_Attempt>[?lanAttempt];
      case EndpointPreference.wan:
        return <_Attempt>[?wanAttempt];
    }
  }

  static String _key(ServerProfile profile) =>
      '${profile.serverId}|${profile.lanUrl}|${profile.wanUrl}'
      '|${profile.preference.name}';
}

class _Attempt {
  const _Attempt(this.kind, this.rawUrl, this.timeout);

  final EndpointKind kind;
  final String rawUrl;
  final Duration timeout;
}
