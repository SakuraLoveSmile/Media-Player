import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:feedback_widget/feedback_widget.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/feedback_config.dart';
import 'package:media_player/app/feedback_diagnostics.dart';

class _JsonAdapter implements HttpClientAdapter {
  _JsonAdapter(this.statusCode);

  final int statusCode;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString(
        '{"ok":true}',
        statusCode,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}

FeedbackServiceConfig _service() => const FeedbackServiceConfig(
  apiBase: 'http://localhost:8787',
  appId: 'dev.mediaplayer.media_player.test',
);

void main() {
  setUp(feedbackDiagnostics.clear);
  tearDown(feedbackDiagnostics.clear);

  group('feedbackDiagnosticEvent', () {
    test('keeps meaningful path segments and collapses ids', () {
      expect(
        feedbackDiagnosticEvent('GET', '/Users/123/Items/abc-def-1234'),
        'http.get.Users_id_Items_id',
      );
      expect(feedbackDiagnosticEvent('get', '/'), 'http.get');
      expect(
        feedbackDiagnosticEvent('POST', '/Items/9/PlaybackInfo?x=1'),
        'http.post.Items_id_PlaybackInfo',
      );
    });

    test('never exceeds the recorder event-name limit', () {
      final String longPath =
          '/${List<String>.generate(12, (int i) => 'segment$i').join('/')}';
      final String event = feedbackDiagnosticEvent('GET', longPath);
      expect(event.length, lessThanOrEqualTo(64));
      expect(RegExp(r'^[a-zA-Z][a-zA-Z0-9_.-]{0,63}$').hasMatch(event), isTrue);
    });
  });

  group('recorder export', () {
    test('exports buffered host events as one JSONL attachment', () {
      feedbackDiagnostics.record(
        event: 'http.get.Items',
        status: 200,
        durationMs: 12,
      );

      final List<FeedbackLogFile> files = provideFeedbackDiagnostics();
      expect(files, hasLength(1));
      expect(files.single.filename, 'media-player-diagnostics.jsonl');
      final Map<String, Object?> line =
          jsonDecode(utf8.decode(files.single.bytes).trim()) as Map<String, Object?>;
      expect(line['event'], 'http.get.Items');
      expect(line['status'], 200);
      expect(line['durationMs'], 12);
    });

    test('exports nothing when no host event happened', () {
      expect(provideFeedbackDiagnostics(), isEmpty);
    });
  });

  group('FeedbackDioInterceptor', () {
    test('records method, normalized path, status and duration', () async {
      final FeedbackDiagnosticsRecorder recorder = FeedbackDiagnosticsRecorder();
      final Dio dio = Dio()..httpClientAdapter = _JsonAdapter(200);
      dio.interceptors.add(FeedbackDioInterceptor(recorder));

      await dio.get<Object?>(
        'https://emby.example.test/Users/42/Items?api_key=secret-token',
      );

      final List<FeedbackLogFile> files = recorder.provide();
      expect(files, hasLength(1));
      final String text = utf8.decode(files.single.bytes);
      expect(text, contains('"event":"http.get.Users_id_Items"'));
      expect(text, contains('"status":200'));
      expect(text, isNot(contains('secret-token')));
      expect(text, isNot(contains('emby.example.test')));
      expect(text, isNot(contains('/Users/42')));
    });

    test('records HTTP failures as error events without response bodies', () async {
      final FeedbackDiagnosticsRecorder recorder = FeedbackDiagnosticsRecorder();
      final Dio dio = Dio()..httpClientAdapter = _JsonAdapter(500);
      dio.interceptors.add(FeedbackDioInterceptor(recorder));

      await expectLater(
        dio.get<Object?>('https://emby.example.test/Items?token=abc'),
        throwsA(isA<DioException>()),
      );

      final String text = utf8.decode(recorder.provide().single.bytes);
      expect(text, contains('"level":"error"'));
      expect(text, contains('"code":"http_error"'));
      expect(text, contains('"status":500'));
      expect(text, isNot(contains('abc')));
    });
  });

  group('buildFeedbackConfig log integration', () {
    test('wires the host diagnostics provider by default', () async {
      feedbackDiagnostics.record(event: 'app.start');
      final FeedbackConfig config = buildFeedbackConfig(
        service: _service(),
        pageLabel: 'library',
      );

      final List<FeedbackLogFile>? files = await config.logProvider!();
      expect(files, hasLength(1));
      expect(utf8.decode(files!.single.bytes), contains('"event":"app.start"'));
    });

    test('allows tests to disable or replace the provider', () {
      expect(
        buildFeedbackConfig(
          service: _service(),
          pageLabel: 'library',
          logProvider: null,
        ).logProvider,
        isNull,
      );
      Future<List<FeedbackLogFile>> none() async => const <FeedbackLogFile>[];
      expect(
        buildFeedbackConfig(
          service: _service(),
          pageLabel: 'library',
          logProvider: none,
        ).logProvider,
        none,
      );
    });
  });
}
