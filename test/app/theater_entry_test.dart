import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/app.dart';
import 'package:media_player/app/providers.dart';
import 'package:media_player/app/services.dart';
import 'package:media_player/data/models/auth_session.dart';
import 'package:media_player/data/offline/offline_repository.dart';

import '../data/offline/offline_test_session.dart';
import '../support/fake_library_service.dart';
import '../support/fake_playback_engine.dart';
import '../support/fake_playback_reporter.dart';
import '../support/fake_playback_service.dart';
import '../support/fake_poster_cache.dart';
import 'session_gate_test.dart' show FakeAuth;

class _DisconnectedAuth extends FakeAuth {
  @override
  Future<AuthSession?> restore() async =>
      throw const SocketException('offline');
}

void main() {
  for (final disconnected in [false, true]) {
    testWidgets(
      'offline route reachable with ${disconnected ? "failed restore" : "signed out"}',
      (tester) async {
        final repository = (await tester.runAsync(() async {
          final directory = await Directory.systemTemp.createTemp(
            'theater-entry-',
          );
          final repository = OfflineRepository(
            directory: directory,
            session: OfflineTestSession('http://127.0.0.1:1'),
          );
          await repository.initialize();
          return repository;
        }))!;
        final directory = repository.directory;
        addTearDown(() async {
          repository.dispose();
          await directory.delete(recursive: true);
        });
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              bootstrapProvider.overrideWith(
                (ref) async => AppServices(
                  auth: disconnected ? _DisconnectedAuth() : FakeAuth(),
                  library: FakeLibraryService(),
                  posters: FakePosterCache(),
                  playback: FakePlaybackService(),
                  createEngine: FakePlaybackEngine.new,
                  createReporter: FakePlaybackReporter.new,
                  offline: repository,
                ),
              ),
            ],
            child: const MediaPlayerApp(),
          ),
        );
        await tester.pumpAndSettle();
        final entry = find.byKey(
          Key(disconnected ? 'startup-offline' : 'login-offline'),
        );
        await tester.ensureVisible(entry);
        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(find.text('下载与离线媒体'), findsOneWidget);
        expect(find.textContaining('还没有离线媒体'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
