import 'dart:convert';

import 'package:feedback_widget/feedback_widget.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_player/app/feedback_orb_settings.dart';
import 'package:media_player/data/storage/key_value_store.dart';

ProviderContainer _container(KeyValueStore store) {
  final ProviderContainer container = ProviderContainer(
    overrides: [
      feedbackOrbStoreProvider.overrideWith((Ref ref) async => store),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<FeedbackOrbSettings> _load(ProviderContainer container) =>
    container.read(feedbackOrbSettingsProvider.future);

void main() {
  test('defaults to the collapsed handle and no wake gesture', () async {
    final settings = await _load(_container(InMemoryKeyValueStore()));

    expect(settings.idleStyle, FeedbackOrbIdleStyle.handle);
    expect(settings.wakeGestures, isEmpty);
  });

  test('loads persisted values and normalizes their order', () async {
    final store = InMemoryKeyValueStore();
    await store.write(feedbackOrbIdleStorageKey, 'hidden');
    await store.write(
      feedbackWakeGesturesStorageKey,
      jsonEncode(<String>['two-finger-double-tap', 'three-finger-swipe-up']),
    );

    final settings = await _load(_container(store));

    expect(settings.idleStyle, FeedbackOrbIdleStyle.hidden);
    expect(settings.wakeGestures, <FeedbackWakeGesture>{
      FeedbackWakeGesture.threeFingerSwipeUp,
      FeedbackWakeGesture.twoFingerDoubleTap,
    });
  });

  test('unknown or corrupted stored values fall back safely', () async {
    final store = InMemoryKeyValueStore();
    await store.write(feedbackOrbIdleStorageKey, 'bogus');
    await store.write(feedbackWakeGesturesStorageKey, '{not json');

    final settings = await _load(_container(store));

    expect(settings.idleStyle, FeedbackOrbIdleStyle.handle);
    expect(settings.wakeGestures, isEmpty);
  });

  test('setIdleStyle persists and updates the state', () async {
    final store = InMemoryKeyValueStore();
    final container = _container(store);
    await _load(container);

    await container
        .read(feedbackOrbSettingsProvider.notifier)
        .setIdleStyle(FeedbackOrbIdleStyle.edge);

    expect(await store.read(feedbackOrbIdleStorageKey), 'edge');
    expect(
      container.read(feedbackOrbSettingsProvider).value?.idleStyle,
      FeedbackOrbIdleStyle.edge,
    );
  });

  test('setWakeGestures persists stable ids and updates the state', () async {
    final store = InMemoryKeyValueStore();
    final container = _container(store);
    await _load(container);

    await container.read(feedbackOrbSettingsProvider.notifier).setWakeGestures(
      <FeedbackWakeGesture>{
        FeedbackWakeGesture.twoFingerHold,
        FeedbackWakeGesture.twoFingerDoubleTap,
      },
    );

    final raw = await store.read(feedbackWakeGesturesStorageKey);
    expect(jsonDecode(raw!), <String>[
      'two-finger-hold',
      'two-finger-double-tap',
    ]);
    expect(
      container.read(feedbackOrbSettingsProvider).value?.wakeGestures,
      <FeedbackWakeGesture>{
        FeedbackWakeGesture.twoFingerHold,
        FeedbackWakeGesture.twoFingerDoubleTap,
      },
    );
  });

  test('toggleWakeGesture adds and removes one gesture', () async {
    final store = InMemoryKeyValueStore();
    final container = _container(store);
    await _load(container);
    final controller = container.read(feedbackOrbSettingsProvider.notifier);

    await controller.toggleWakeGesture(
      FeedbackWakeGesture.threeFingerSwipeUp,
      enabled: true,
    );
    expect(
      container.read(feedbackOrbSettingsProvider).value?.wakeGestures,
      <FeedbackWakeGesture>{FeedbackWakeGesture.threeFingerSwipeUp},
    );

    await controller.toggleWakeGesture(
      FeedbackWakeGesture.threeFingerSwipeUp,
      enabled: false,
    );
    expect(
      container.read(feedbackOrbSettingsProvider).value?.wakeGestures,
      isEmpty,
    );
  });

  test(
    'a failing write surfaces an error and keeps the previous value',
    () async {
      final store = _ThrowingStore();
      final container = _container(store);
      await _load(container);

      await expectLater(
        container
            .read(feedbackOrbSettingsProvider.notifier)
            .setIdleStyle(FeedbackOrbIdleStyle.hidden),
        throwsA(isA<FeedbackOrbSettingsException>()),
      );
      expect(
        container.read(feedbackOrbSettingsProvider).value?.idleStyle,
        FeedbackOrbIdleStyle.handle,
      );
    },
  );
}

class _ThrowingStore implements KeyValueStore {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {
    throw StateError('disk full');
  }

  @override
  Future<void> delete(String key) async {}
}
