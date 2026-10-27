import 'json_read.dart';

/// Authenticated session (contract §4). Contains the access token, so it must
/// never be logged or serialized into a document.
class AuthSession {
  const AuthSession({
    required this.userId,
    required this.userName,
    required this.accessToken,
    required this.deviceId,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      userId: asStringOr(json['userId'], ''),
      userName: asStringOr(json['userName'], ''),
      accessToken: asStringOr(json['accessToken'], ''),
      deviceId: asStringOr(json['deviceId'], ''),
    );
  }

  /// Persisted metadata intentionally excludes the token; the token lives in
  /// its own store (contract §10.1).
  factory AuthSession.fromMetaJson(
    Map<String, dynamic> json, {
    required String accessToken,
  }) {
    return AuthSession(
      userId: asStringOr(json['userId'], ''),
      userName: asStringOr(json['userName'], ''),
      accessToken: accessToken,
      deviceId: asStringOr(json['deviceId'], ''),
    );
  }

  final String userId;
  final String userName;
  final String accessToken;
  final String deviceId;

  AuthSession copyWith({String? accessToken}) {
    return AuthSession(
      userId: userId,
      userName: userName,
      accessToken: accessToken ?? this.accessToken,
      deviceId: deviceId,
    );
  }

  Map<String, dynamic> toMetaJson() => <String, dynamic>{
        'userId': userId,
        'userName': userName,
        'deviceId': deviceId,
      };

  @override
  String toString() => 'AuthSession(user: $userName)';
}
