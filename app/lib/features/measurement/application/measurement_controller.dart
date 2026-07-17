/// 測定セッションViewModel。
/// BLEフレームストリームを購読し、サンプル蓄積・統計・保存を担う。
import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/error/app_exception.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../../ble/data/ble_service.dart';
import '../../ble/data/hpp_codec.dart';
import '../data/measurement_repository.dart';
import '../domain/measurement.dart';

enum MeasurePhase { idle, starting, measuring, stopping, saved, error }

class MeasureState {
  const MeasureState({
    this.phase = MeasurePhase.idle,
    this.samples = const [],
    this.errorCode,
    this.summary,
    this.droppedFrames = 0,
  });

  final MeasurePhase phase;
  final List<H2Sample> samples;
  final int? errorCode;
  final Measurement? summary;

  /// SEQ跳びから推定した欠測フレーム数(BLE切断・干渉の指標)
  final int droppedFrames;

  H2Sample? get latest => samples.isEmpty ? null : samples.last;

  double get averagePpm {
    final valid = samples.where((s) => s.isValid && !s.isWarmup).toList();
    if (valid.isEmpty) return 0;
    return valid.map((s) => s.h2Ppm).reduce((a, b) => a + b) / valid.length;
  }

  double get peakPpm {
    if (samples.isEmpty) return 0;
    return samples.map((s) => s.h2Ppm).reduce((a, b) => a > b ? a : b);
  }

  MeasureState copyWith({
    MeasurePhase? phase,
    List<H2Sample>? samples,
    int? errorCode,
    Measurement? summary,
    int? droppedFrames,
  }) =>
      MeasureState(
        phase: phase ?? this.phase,
        samples: samples ?? this.samples,
        errorCode: errorCode ?? this.errorCode,
        summary: summary ?? this.summary,
        droppedFrames: droppedFrames ?? this.droppedFrames,
      );
}

class MeasurementController extends Notifier<MeasureState> {
  StreamSubscription<HppFrame>? _sub;
  DateTime? _startedAt;
  int? _lastSeq;

  static const _ackTimeout = Duration(milliseconds: 300);
  static const _ackRetries = 2;
  static const _summaryTimeout = Duration(seconds: 3);

  /// 30分×1Hz=1800点 + 余裕
  static const _maxSamples = 2000;

  BleRepository get _ble => ref.read(bleRepositoryProvider);

  @override
  MeasureState build() {
    ref.onDispose(() => _sub?.cancel());
    return const MeasureState();
  }

  /// コマンド送信 + ACK待ち(300ms×2回再送)。
  Future<void> _sendWithAck(int cmd, [List<int> payload = const []]) async {
    for (var attempt = 0; attempt <= _ackRetries; attempt++) {
      final ackFuture = _ble.frames
          .where((f) =>
              (f.type == Hpp.ack || f.type == Hpp.nak) && f.ackCmd == cmd)
          .first
          .timeout(_ackTimeout);
      await _ble.send(cmd, payload);
      try {
        final res = await ackFuture;
        if (res.type == Hpp.nak) {
          throw SensorException(res.nakError, 'NAK for cmd=$cmd');
        }
        return;
      } on TimeoutException {
        continue; // 再送
      }
    }
    throw const BleException('ACK timeout');
  }

  Future<void> start({int intervalS = 1}) async {
    if (state.phase == MeasurePhase.measuring) return;
    state = const MeasureState(phase: MeasurePhase.starting);
    try {
      _startedAt = DateTime.now();
      _lastSeq = null;
      _listenFrames();
      await _sendWithAck(Hpp.cmdStartCont, [intervalS]);
      state = state.copyWith(phase: MeasurePhase.measuring);
      unawaited(
          ref.read(analyticsProvider).logEvent(name: 'measure_start'));
    } on AppException {
      state = state.copyWith(phase: MeasurePhase.error);
      rethrow;
    }
  }

  void _listenFrames() {
    _sub?.cancel();
    _sub = _ble.frames.listen((f) {
      _trackSeq(f.seq);
      switch (f.type) {
        case Hpp.evtData:
          final sample = H2Sample(
            timeMs: f.dataTimeMs,
            h2Ppb: f.dataH2Ppb,
            tempC: f.dataTempC,
            rh: f.dataRh,
            flags: f.dataFlags,
          );
          final samples = [...state.samples, sample];
          if (samples.length > _maxSamples) samples.removeAt(0);
          state = state.copyWith(samples: samples);
        case Hpp.evtStatus:
          // 再接続後の再同期: FWが測定継続中ならUIも測定表示へ復帰
          if (f.statusIsMeasuring &&
              state.phase != MeasurePhase.measuring &&
              state.phase != MeasurePhase.stopping &&
              state.samples.isNotEmpty) {
            state = state.copyWith(phase: MeasurePhase.measuring);
          }
        case Hpp.evtError:
          state = state.copyWith(
              phase: MeasurePhase.error, errorCode: f.errorCode);
        default:
          break;
      }
    });
  }

  void _trackSeq(int seq) {
    final last = _lastSeq;
    _lastSeq = seq;
    if (last == null) return;
    final gap = (seq - last - 1) & 0xFF;
    if (gap > 0 && gap < 0x80) {
      state = state.copyWith(droppedFrames: state.droppedFrames + gap);
    }
  }

  /// 停止→サマリ受信→Firestore保存。
  /// サマリがタイムアウトしても手元のサンプルから統計を自己算出して
  /// 保存する(30分の測定をフレーム1枚の喪失で失わない)。
  Future<void> stopAndSave(String dogId, String deviceId) async {
    if (state.phase != MeasurePhase.measuring) return;
    if (dogId.isEmpty) {
      state = state.copyWith(phase: MeasurePhase.error);
      throw StateError('dogId is required to save a measurement');
    }
    state = state.copyWith(phase: MeasurePhase.stopping);
    try {
      final summaryFuture = _ble.frames
          .where((f) => f.type == Hpp.evtSummary)
          .first
          .timeout(_summaryTimeout);
      await _sendWithAck(Hpp.cmdStop);

      Measurement m;
      try {
        final s = await summaryFuture;
        m = _fromFwSummary(s, dogId, deviceId);
      } on TimeoutException {
        m = _fromLocalSamples(dogId, deviceId); // フォールバック
      }

      await ref.read(measurementRepositoryProvider).save(dogId, m);
      state = state.copyWith(phase: MeasurePhase.saved, summary: m);
      unawaited(ref
          .read(analyticsProvider)
          .logEvent(name: 'measure_complete', parameters: {
        'duration_s': m.durationS,
        'avg_ppb': m.avgPpb,
        'dropped_frames': state.droppedFrames,
      }));
    } on Object {
      state = state.copyWith(phase: MeasurePhase.error);
      rethrow;
    } finally {
      await _sub?.cancel();
    }
  }

  Measurement _fromFwSummary(HppFrame s, String dogId, String deviceId) =>
      Measurement(
        id: '',
        dogId: dogId,
        deviceId: deviceId,
        startedAt: _startedAt ?? DateTime.now(),
        durationS: s.summaryDurationS,
        sampleCount: s.summaryCount,
        avgPpb: s.summaryAvgPpb,
        maxPpb: s.summaryMaxPpb,
        minPpb: s.summaryMinPpb,
        mode: 'continuous',
        series: decimateSeries(state.samples),
      );

  Measurement _fromLocalSamples(String dogId, String deviceId) {
    final valid =
        state.samples.where((s) => s.isValid && !s.isWarmup).toList();
    final ppbs = valid.map((s) => s.h2Ppb).toList();
    final started = _startedAt ?? DateTime.now();
    return Measurement(
      id: '',
      dogId: dogId,
      deviceId: deviceId,
      startedAt: started,
      durationS: DateTime.now().difference(started).inSeconds,
      sampleCount: valid.length,
      avgPpb: ppbs.isEmpty
          ? 0
          : (ppbs.reduce((a, b) => a + b) / ppbs.length).round(),
      maxPpb: ppbs.isEmpty ? 0 : ppbs.reduce((a, b) => a > b ? a : b),
      minPpb: ppbs.isEmpty ? 0 : ppbs.reduce((a, b) => a < b ? a : b),
      mode: 'continuous',
      series: decimateSeries(state.samples),
    );
  }

  void resetSession() {
    _sub?.cancel();
    state = const MeasureState();
  }
}

final measurementControllerProvider =
    NotifierProvider<MeasurementController, MeasureState>(
        MeasurementController.new);
