import '../../core/errors/app_error.dart';
import '../../core/network/url_normalizer.dart';
import '../../data/models/server_profile.dart';

/// Result of validating the login form before any network call.
sealed class LoginFormResult {
  const LoginFormResult();
}

class LoginFormInvalid extends LoginFormResult {
  const LoginFormInvalid(this.message);

  final String message;
}

class LoginFormValid extends LoginFormResult {
  const LoginFormValid({
    required this.profile,
    required this.username,
    required this.password,
  });

  final ServerProfile profile;
  final String username;
  final String password;
}

/// Validates and normalizes the login form (contract §1.2, §1.4).
///
/// Addresses are normalized here, at the UI boundary, so the data layer only
/// ever sees http/https bases.
LoginFormResult validateLoginForm({
  required String lanUrl,
  required String wanUrl,
  required String username,
  required String password,
}) {
  final rawLan = lanUrl.trim();
  final rawWan = wanUrl.trim();

  if (rawLan.isEmpty && rawWan.isEmpty) {
    return const LoginFormInvalid('请至少填写一个服务器地址');
  }

  final normalizedLan =
      rawLan.isEmpty ? null : UrlNormalizer.normalize(rawLan);
  if (rawLan.isNotEmpty && normalizedLan == null) {
    return const LoginFormInvalid('局域网地址格式不正确，需要 http:// 或 https://');
  }

  final normalizedWan =
      rawWan.isEmpty ? null : UrlNormalizer.normalize(rawWan);
  if (rawWan.isNotEmpty && normalizedWan == null) {
    return const LoginFormInvalid('公网地址格式不正确，需要 https://');
  }

  if (username.trim().isEmpty) {
    return const LoginFormInvalid('请输入用户名');
  }

  if (password.isEmpty) {
    return const LoginFormInvalid('请输入密码');
  }

  return LoginFormValid(
    profile: ServerProfile(
      serverId: '',
      name: '',
      lanUrl: normalizedLan,
      wanUrl: normalizedWan,
    ),
    username: username.trim(),
    password: password,
  );
}

/// User-facing text for each failure (contract §6: no raw exceptions in UI).
String loginErrorMessage(AppErrorCode code) {
  return switch (code) {
    AppErrorCode.unauthorized => '用户名或密码错误',
    AppErrorCode.forbidden => '该账号没有访问权限',
    AppErrorCode.networkUnreachable => '无法连接服务器，请检查地址与网络',
    AppErrorCode.tlsUntrusted => '服务器证书不受信任',
    AppErrorCode.serverMismatch => '该地址属于另一台服务器',
    AppErrorCode.notFound => '服务器地址不正确（404）',
    AppErrorCode.serverError => '服务器返回异常，请稍后重试',
    _ => '登录失败，请稍后重试',
  };
}
