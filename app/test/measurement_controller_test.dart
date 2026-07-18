/// MeasurementControllerのユニットテスト。
/// MockBleRepository(実機なし開発用と同一物)をDIし、
/// 開始→データ蓄積→停止→保存 のセッション全体を検証する。
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hydropaw/core/analytics/app_analytics.dart';
import 'package:hydropaw/features/ble/data/ble_service.dart';
import 'package:hydropaw/features/ble/data/hpp_codec.dart';
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
      appAnalyticsProvider.overrideWithValue(const NoopAnalytics()),
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

  test('水素・温度・湿度が1Hzで更新され、値が妥当な範囲にある', () async {
    final controller =
        container.read(measurementControllerProvider.notifier);
    await controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 3200));

    final samples =
        container.read(measurementControllerProvider).samples;
    expect(samples.length, greaterThanOrEqualTo(3));
    // 水素は変動している(完全同値でない)
    expect(samples.map((s) => s.h2Ppb).toSet().length, greaterThan(1));
    for (final s in samples) {
      expect(s.h2Ppb, inInclusiveRange(0, 130000));
      expect(s.tempC, inInclusiveRange(20.0, 30.0));
      expect(s.rh, inInclusiveRange(35.0, 55.0));
    }
    // 経過時刻が単調増加
    for (var i = 1; i < samples.length; i++) {
      expect(samples[i].timeMs, greaterThan(samples[i - 1].timeMs));
    }
  });

  test('EVT_SUMMARY欠損時はローカル統計で保存される(測定全損しない)', () async {
    // サマリを返さないMockに差し替え
    ble.dispose();
    ble = MockBleRepository(seed: 7, emitSummary: false);
    container.dispose();
    container = ProviderContainer(overrides: [
      bleRepositoryProvider.overrideWithValue(ble),
      measurementRepositoryProvider.overrideWithValue(repo),
      appAnalyticsProvider.overrideWithValue(const NoopAnalytics()),
    ]);
    await ble.connect('mock');

    final controller =
        container.read(measurementControllerProvider.notifier);
    await controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 2500));

    await controller.stopAndSave('dog-1', 'device-1');
    final state = container.read(measurementControllerProvider);
    expect(state.phase, MeasurePhase.saved); // サマリ喪失でもsaved
    expect(repo.saved, hasLength(1));
    final m = repo.saved.first;
    expect(m.avgPpb, greaterThan(0)); // ローカル統計が算出されている
    expect(m.maxPpb, greaterThanOrEqualTo(m.minPpb));
    expect(m.series, isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('呼気セッション: startBreathで結果が自動保存され、品質スコアが付く',
      () async {
    // タイムライン短縮Mock(18tick×30ms)で高速化
    ble.dispose();
    ble = MockBleRepository(seed: 3, breathTickMs: 30);
    container.dispose();
    container = ProviderContainer(overrides: [
      bleRepositoryProvider.overrideWithValue(ble),
      measurementRepositoryProvider.overrideWithValue(repo),
      appAnalyticsProvider.overrideWithValue(const NoopAnalytics()),
    ]);
    await ble.connect('mock');

    final controller =
        container.read(measurementControllerProvider.notifier);
    await controller.startBreath(dogId: 'dog-1', deviceId: 'device-1');
    expect(container.read(measurementControllerProvider).breathMode, isTrue);

    // WARMUP→READY→呼気→解析→RESULT(ARQ) が自動で完結する
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final state = container.read(measurementControllerProvider);
    expect(state.phase, MeasurePhase.saved);
    expect(repo.saved, hasLength(1));
    final m = repo.saved.first;
    expect(m.mode, 'breath');
    expect(m.quality, greaterThanOrEqualTo(80));
    expect(m.confidence, 100);
    expect(m.hasQuality, isTrue);
    expect(m.remeasureAdvised, isFalse);
    expect(m.aucPpbS, greaterThan(0));
  });

  test('EVT_RESULTのARQ再送(同一SEQ)は重複保存されない', () async {
    final controller =
        container.read(measurementControllerProvider.notifier);
    await controller.startBreath(dogId: 'dog-1', deviceId: 'device-1');

    // FWのARQ再送を模擬: 同一SEQのEVT_RESULTを3回注入
    final p = Uint8List(30);
    p[0] = 1; // session
    p[1] = 91; // quality
    p[2] = 100; // confidence
    p[3] = 0x12; // RH_OK|WARMUP_OK
    final frame = HppFrame(Hpp.evtResult, 200, p);
    ble.debugEmitFrame(frame);
    ble.debugEmitFrame(frame);
    ble.debugEmitFrame(frame);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(repo.saved, hasLength(1)); // SEQ重複排除が効いている
    expect(container.read(measurementControllerProvider).phase,
        MeasurePhase.saved);
  });

  test('再接続後: EVT_STATUS(測定中)でUIがmeasuringへ再同期する', () async {
    final controller =
        container.read(measurementControllerProvider.notifier);
    await controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 1500));

    // 切断相当でphaseがずれた状況を作る(FWからのEVT_ERROR受信)
    ble.debugEmitFrame(
        HppFrame(Hpp.evtError, 0, Uint8List.fromList([0x01, 0x00])));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(container.read(measurementControllerProvider).phase,
        MeasurePhase.error);

    // 再接続後のCMD_GET_STATUS応答: FW state=SM_MEASURING(3)
    final p = Uint8List(12);
    p[0] = 3; // SM_MEASURING
    ble.debugEmitFrame(HppFrame(Hpp.evtStatus, 0, p));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(container.read(measurementControllerProvider).phase,
        MeasurePhase.measuring);
  });
}
