import 'package:media_player/core/device/pip.dart';

/// PIP double for controller/page tests; no platform channels. [result] false
/// simulates a platform refusal; [failure] throws from the call.
class FakePipController implements PipController {
  FakePipController({this.result = true, this.failure});

  bool result;
  Object? failure;
  int calls = 0;

  @override
  Future<bool> enterPip() async {
    calls++;
    final Object? error = failure;
    if (error != null) throw error;
    return result;
  }
}
