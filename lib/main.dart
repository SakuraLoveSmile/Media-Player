import 'package:feedback_widget/feedback_widget.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app/app.dart';
import 'app/feedback_diagnostics.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Host diagnostics: Flutter / platform errors and API events stay in a
  // bounded, whitelisted buffer that the feedback panel can attach. The
  // capture forwards to the original handlers; it never swallows errors.
  FeedbackExceptionCapture.install(feedbackDiagnostics);
  feedbackDiagnostics.record(event: 'app.start');
  // Loads libmpv; without it `Player()` fails at runtime (contract §5).
  MediaKit.ensureInitialized();
  runApp(const ProviderScope(child: MediaPlayerApp()));
}
