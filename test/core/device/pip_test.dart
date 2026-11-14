import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/core/device/pip.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MethodChannelPipController', () {
    const MethodChannelPipController controller = MethodChannelPipController();

    void mock(Future<dynamic> Function(MethodCall call)? handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            MethodChannelPipController.channel,
            handler,
          );
    }

    tearDown(() => mock(null));

    test('enterPip invokes the MainActivity contract', () async {
      final List<MethodCall> calls = <MethodCall>[];
      mock((MethodCall call) async {
        calls.add(call);
        return true;
      });

      expect(await controller.enterPip(), isTrue);
      expect(MethodChannelPipController.channel.name, 'media_player/pip');
      expect(calls.single.method, 'enterPip');
      expect(calls.single.arguments, isNull);
    });

    test('a refused request stays false', () async {
      mock((MethodCall call) async => false);
      expect(await controller.enterPip(), isFalse);
    });

    test('a null verdict degrades to false', () async {
      mock((MethodCall call) async => null);
      expect(await controller.enterPip(), isFalse);
    });

    test('a PlatformException degrades to false', () async {
      mock((MethodCall call) async {
        throw PlatformException(code: 'pip', message: 'refused');
      });
      expect(await controller.enterPip(), isFalse);
    });

    test('a missing plugin implementation degrades to false', () async {
      // No mock handler registered: the test messenger reports the channel as
      // unimplemented, exactly like a platform without the MainActivity hook.
      expect(await controller.enterPip(), isFalse);
    });
  });

  group('NoopPipController', () {
    test('enterPip always returns false', () async {
      expect(await const NoopPipController().enterPip(), isFalse);
    });
  });
}
