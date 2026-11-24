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
  test('defaults mirror the component: beam, ripple, bead, gesture on', () async {
    final settings = await _load(_container(InMemoryKeyValueStore()));

    expect(settings.launcherStyle, FeedbackLauncherStyle.beam);
    expect(settings.wakeVisual, FeedbackWakeVisual.ripple);
    expect(settings.orbEntrance, FeedbackOrbEntrance.bead);
    expect(settings.idleStyle, FeedbackOrbIdleStyle.handle);
    expect(settings.wakeGestures, <FeedbackWakeGesture>{
      FeedbackWakeGesture.twoFingerHold,
    });
    expect(settings.reflectionEnabled, isTrue);
  });

  test('loads persisted values and normalizes their order', () async {
    final store = InMemoryKeyValueStore();
    await store.write(feedbackLauncherStyleStorageKey, 'orb');
    await store.write(feedbackWakeVisualStorageKey, 'aurora');
    await store.write(feedbackOrbEntranceStorageKey, 'corners');
    await store.write(feedbackOrbIdleStorageKey, 'hidden');
    await store.write(
      feedbackWakeGesturesStorageKey,
      jsonEncode(<String>['two-finger-double-tap', 'three-finger-swipe-up']),
    );
    await store.write(feedbackOrbReflectionStorageKey, 'false');

    final settings = await _load(_container(store));

    expect(settings.launcherStyle, FeedbackLauncherStyle.orb);
    expect(settings.wakeVisual, FeedbackWakeVisual.aurora);
    expect(settings.orbEntrance, FeedbackOrbEntrance.corners);
    expect(settings.idleStyle, FeedbackOrbIdleStyle.hidden);
    expect(settings.wakeGestures, <FeedbackWakeGesture>{
      FeedbackWakeGesture.threeFingerSwipeUp,
      FeedbackWakeGesture.twoFingerDoubleTap,
    });
    expect(settings.reflectionEnabled, isFalse);
  });

  test('unknown or corrupted stored values fall back safely', () async {
    final store = InMemoryKeyValueStore();
    await store.write(feedbackLauncherStyleStorageKey, 'beam-ish');
    await store.write(feedbackWakeVisualStorageKey, 'sparkle');
    await store.write(feedbackOrbEntranceStorageKey, 'warp');
    await store.write(feedbackOrbIdleStorageKey, 'bogus');
    await store.write(feedbackWakeGesturesStorageKey, '{not json');
    await store.write(feedbackOrbReflectionStorageKey, 'maybe');

    final settings = await _load(_container(store));

    expect(settings.launcherStyle, FeedbackLauncherStyle.beam);
    expect(settings.wakeVisual, FeedbackWakeVisual.ripple);
    expect(settings.orbEntrance, FeedbackOrbEntrance.bead);
    expect(settings.idleStyle, FeedbackOrbIdleStyle.handle);
    expect(settings.wakeGestures, isEmpty);
    expect(settings.reflectionEnabled, isTrue);
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

  test('the launcher, wake visual and entrance persist by name', () async {
    final store = InMemoryKeyValueStore();
    final container = _container(store);
    await _load(container);
    final controller = container.read(feedbackOrbSettingsProvider.notifier);

    await controller.setLauncherStyle(FeedbackLauncherStyle.orb);
    await controller.setWakeVisual(FeedbackWakeVisual.aurora);
    await controller.setOrbEntrance(FeedbackOrbEntrance.turn);

    expect(await store.read(feedbackLauncherStyleStorageKey), 'orb');
    expect(await store.read(feedbackWakeVisualStorageKey), 'aurora');
    expect(await store.read(feedbackOrbEntranceStorageKey), 'turn');
    final settings = container.read(feedbackOrbSettingsProvider).value;
    expect(settings?.launcherStyle, FeedbackLauncherStyle.orb);
    expect(settings?.wakeVisual, FeedbackWakeVisual.aurora);
    expect(settings?.orbEntrance, FeedbackOrbEntrance.turn);
  });

  test('setReflectionEnabled persists the switch and updates the state', () async {
    final store = InMemoryKeyValueStore();
    final container = _container(store);
    await _load(container);

    await container
        .read(feedbackOrbSettingsProvider.notifier)
        .setReflectionEnabled(false);

    expect(await store.read(feedbackOrbReflectionStorageKey), 'false');
    expect(
      container.read(feedbackOrbSettingsProvider).value?.reflectionEnabled,
      isFalse,
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
      <FeedbackWakeGesture>{
        FeedbackWakeGesture.twoFingerHold,
        FeedbackWakeGesture.threeFingerSwipeUp,
      },
    );

    await controller.toggleWakeGesture(
      FeedbackWakeGesture.threeFingerSwipeUp,
      enabled: false,
    );
    expect(
      container.read(feedbackOrbSettingsProvider).value?.wakeGestures,
      <FeedbackWakeGesture>{FeedbackWakeGesture.twoFingerHold},
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
