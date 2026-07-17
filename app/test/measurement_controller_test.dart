/// MeasurementControllerのユニットテスト。
/// MockBleRepository(実機なし開発用と同一物)をDIし、
/// 開始→データ蓄積→停止→保存 のセッション全体を検証する。
import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hydropaw/core/firebase/firebase_providers.dart';
import 'package:hydropaw/features/ble/data/ble_service.dart';
import 'package:hydropaw/features/ble/data/mock_ble_repository.dart';
import 'package:hydropaw/features/measurement/application/measurement_controller.dart';
import 'package:hydropaw/features/measurement/data/measurement_repository.dart';
import 'package:hydropaw/features/measurement/domain/measurement.dart';

class _InMemoryMeasurementRepository implements MeasurementRepository {
  final saved = <Measurement>[];

  @override
  Future<String> save(String dogId, Measurement m) async {
    saved.add(m);
    return 'doc-${saved.length}';
  }

  @override
  Future<List<Measurement>> fetchHistory(String dogId,
          {DateTime? before, int limit = 20}) async =>
      saved;

  @override
  Stream<Measurement?> watchLatest(String dogId) =>
      Stream.value(saved.isEmpty ? null : saved.last);
}

class _FakeAnalytics extends Fake implements FirebaseAnalytics {
  @override
  Future<void> logEvent({
    required String name,
    Map<String, Object?>? parameters,
    AnalyticsCallOptions? callOptions,
  }) async {}
}

void main() {
  late MockBleRepository ble;
  late _InMemoryMeasurementRepository repo;
  late ProviderContainer container;

  setUp(() async {
    ble = MockBleRepository(seed: 42);
    repo = _InMemoryMeasurementRepository();
    container = ProviderContainer(overrides: [
      bleRepositoryProvider.overrideWithValue(ble),
      measurementRepositoryProvider.overrideWithValue(repo),
      analyticsProvider.overrideWithValue(_FakeAnalytics()),
    ]);
    await ble.connect('mock');
  });

  tearDown(() {
    container.dispose();
    ble.dispose();
  });

  test('開始でACKを受けてmeasuringへ遷移し、1Hzでサンプルが蓄積される', () async {
    final controller =
        container.read(measurementControllerProvider.notifier);
    await controller.start();
    expect(container.read(measurementControllerProvider).phase,
        MeasurePhase.measuring);

    await Future<void>.delayed(const Duration(milliseconds: 2500));
    final state = container.read(measurementControllerProvider);
    expect(state.samples.length, greaterThanOrEqualTo(2));
    expect(state.latest!.isWarmup, isTrue); // 開始60秒はウォームアップ
  });

  test('停止でEVT_SUMMARYを受けて保存される', () async {
    final controller =
        container.read(measurementControllerProvider.notifier);
    await controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 2500));

    await controller.stopAndSave('dog-1', 'device-1');
    final state = container.read(measurementControllerProvider);
    expect(state.phase, MeasurePhase.saved);
    expect(repo.saved, hasLength(1));
    expect(repo.saved.first.dogId, 'dog-1');
    expect(repo.saved.first.sampleCount, greaterThan(0));
    expect(repo.saved.first.series, isNotEmpty);
  });

  test('dogId未指定の保存は拒否される(空パス書込み防止)', () async {
    final controller =
        container.read(measurementControllerProvider.notifier);
    await controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 1200));

    await expectLater(
        controller.stopAndSave('', 'device-1'), throwsStateError);
    expect(repo.saved, isEmpty);
  });

  test('未接続での開始はBleExceptionでerrorへ', () async {
    await ble.disconnect();
    final controller =
        container.read(measurementControllerProvider.notifier);
    await expectLater(controller.start(), throwsA(isA<Exception>()));
    expect(container.read(measurementControllerProvider).phase,
        MeasurePhase.error);
  });
}
