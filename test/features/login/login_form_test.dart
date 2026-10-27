import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/errors/app_error.dart';
import 'package:media_player/features/login/login_form.dart';

void main() {
  LoginFormResult validate({
    String lan = '',
    String wan = '',
    String user = 'test',
    String pass = 'secret',
  }) {
    return validateLoginForm(
      lanUrl: lan,
      wanUrl: wan,
      username: user,
      password: pass,
    );
  }

  String messageOf(LoginFormResult result) {
    expect(result, isA<LoginFormInvalid>());
    return (result as LoginFormInvalid).message;
  }

  test('requires at least one address', () {
    expect(messageOf(validate()), '请至少填写一个服务器地址');
    expect(messageOf(validate(lan: '   ')), '请至少填写一个服务器地址');
  });

  test('rejects invalid addresses with the matching field', () {
    expect(
      messageOf(validate(lan: 'ftp://host')),
      '局域网地址格式不正确，需要 http:// 或 https://',
    );
    expect(
      messageOf(validate(wan: 'not a url')),
      '公网地址格式不正确，需要 https://',
    );
  });

  test('requires username and password', () {
    expect(messageOf(validate(lan: '192.168.1.10:8096', user: ' ')), '请输入用户名');
    expect(messageOf(validate(lan: '192.168.1.10:8096', pass: '')), '请输入密码');
  });

  test('normalizes a bare host and port', () {
    final result = validate(lan: ' 192.168.1.10:8096/ ');

    expect(result, isA<LoginFormValid>());
    final valid = result as LoginFormValid;
    expect(valid.profile.lanUrl, 'http://192.168.1.10:8096');
    expect(valid.profile.wanUrl, isNull);
    expect(valid.profile.serverId, isEmpty);
    expect(valid.username, 'test');
  });

  test('accepts a WAN-only profile', () {
    final result = validate(wan: 'https://emby.example.com/');

    expect(result, isA<LoginFormValid>());
    final valid = result as LoginFormValid;
    expect(valid.profile.lanUrl, isNull);
    expect(valid.profile.wanUrl, 'https://emby.example.com');
  });

  test('keeps both addresses and trims the username', () {
    final result = validate(
      lan: 'http://192.168.1.10:8096',
      wan: ' https://emby.example.com/emby/ ',
      user: '  test  ',
    );

    final valid = result as LoginFormValid;
    expect(valid.profile.lanUrl, 'http://192.168.1.10:8096');
    expect(valid.profile.wanUrl, 'https://emby.example.com/emby');
    expect(valid.username, 'test');
    expect(valid.password, 'secret');
  });

  test('maps error codes to user text', () {
    expect(loginErrorMessage(AppErrorCode.unauthorized), '用户名或密码错误');
    expect(loginErrorMessage(AppErrorCode.serverMismatch), '该地址属于另一台服务器');
    expect(loginErrorMessage(AppErrorCode.tlsUntrusted), '服务器证书不受信任');
    expect(
      loginErrorMessage(AppErrorCode.networkUnreachable),
      contains('无法连接服务器'),
    );
    expect(
      loginErrorMessage(AppErrorCode.playbackUnsupported),
      '登录失败，请稍后重试',
    );
  });
}
