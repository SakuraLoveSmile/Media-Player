import '../../core/network/endpoint_kind.dart';
import 'json_read.dart';

/// Server identity and the two addresses used to reach it (contract §1.1).
class ServerProfile {
  const ServerProfile({
    required this.serverId,
    required this.name,
    this.lanUrl,
    this.wanUrl,
    this.preference = EndpointPreference.auto,
    this.wanBitrateCapMbps = 30,
    this.forceDirectOnWan = false,
    this.lastGoodEndpoint,
  });

  factory ServerProfile.fromJson(Map<String, dynamic> json) {
    return ServerProfile(
      serverId: asStringOr(json['serverId'], ''),
      name: asStringOr(json['name'], ''),
      lanUrl: asString(json['lanUrl']),
      wanUrl: asString(json['wanUrl']),
      preference: _preferenceFromName(asString(json['preference'])),
      wanBitrateCapMbps: asInt(json['wanBitrateCapMbps'], fallback: 30),
      forceDirectOnWan: asBool(json['forceDirectOnWan']),
      lastGoodEndpoint: _kindFromName(asString(json['lastGoodEndpoint'])),
    );
  }

  /// Stable id from `System/Info/Public.Id` / login response; empty until the
  /// first successful login.
  final String serverId;
  final String name;
  final String? lanUrl;
  final String? wanUrl;
  final EndpointPreference preference;
  final int wanBitrateCapMbps;
  final bool forceDirectOnWan;
  final EndpointKind? lastGoodEndpoint;

  bool get hasAnyAddress => lanUrl != null || wanUrl != null;

  /// Null arguments keep the current value; pass an explicit empty string to
  /// clear an address.
  ServerProfile copyWith({
    String? serverId,
    String? name,
    String? lanUrl,
    String? wanUrl,
    EndpointPreference? preference,
    int? wanBitrateCapMbps,
    bool? forceDirectOnWan,
    EndpointKind? lastGoodEndpoint,
  }) {
    return ServerProfile(
      serverId: serverId ?? this.serverId,
      name: name ?? this.name,
      lanUrl: lanUrl == '' ? null : (lanUrl ?? this.lanUrl),
      wanUrl: wanUrl == '' ? null : (wanUrl ?? this.wanUrl),
      preference: preference ?? this.preference,
      wanBitrateCapMbps: wanBitrateCapMbps ?? this.wanBitrateCapMbps,
      forceDirectOnWan: forceDirectOnWan ?? this.forceDirectOnWan,
      lastGoodEndpoint: lastGoodEndpoint ?? this.lastGoodEndpoint,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'serverId': serverId,
        'name': name,
        'lanUrl': lanUrl,
        'wanUrl': wanUrl,
        'preference': preference.name,
        'wanBitrateCapMbps': wanBitrateCapMbps,
        'forceDirectOnWan': forceDirectOnWan,
        'lastGoodEndpoint': lastGoodEndpoint?.name,
      };

  static EndpointPreference _preferenceFromName(String? name) {
    return EndpointPreference.values.firstWhere(
      (value) => value.name == name,
      orElse: () => EndpointPreference.auto,
    );
  }

  static EndpointKind? _kindFromName(String? name) {
    if (name == null) return null;
    for (final value in EndpointKind.values) {
      if (value.name == name) return value;
    }
    return null;
  }
}
