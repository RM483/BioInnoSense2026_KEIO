/// MockBleRepository — 実機(DGS2 + Leafony)が無くても全画面を動かすための
/// BleRepository実装。ファームウェアのステートマシンを簡易に模倣し、
/// 1Hzで現実的なEVT_DATAを生成する。
///
/// 有効化: `flutter run --dart-define=USE_MOCK_BLE=true`
/// (bleRepositoryProvider が本実装へ差し替わる。UI/Controller層は無変更)
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../../core/error/app_exception.dart';
import 'ble_service.dart';
import 'hpp_codec.dart';

class MockBleRepository implements BleRepository {
  MockBleRepository({this.seed, this.emitSummary = true});

  final int? seed;

  /// falseにするとCMD_STOPでEVT_SUMMARYを返さない
  /// (サマリ喪失時のローカル統計フォールバックのテスト用)。
  final bool emitSummary;

  late final _rng = Random(seed);

  final _frameController = StreamController<HppFrame>.broadcast();
  final _stateController =
      StreamController<BluetoothConnectionState>.broadcast();

  Timer? _dataTimer;
  bool _connected = false;
  bool _measuring = false;
  int _seq = 0;

  // ---- 呼気セッション(BAP)模倣 ----
  Timer? _breathTimer;
  int _breathTick = 0;
  int _sessionId = 0;
  Timer? _arqTimer; // EVT_RESULT再送(ACK_EVT未着時) — FWのARQを模倣
  int? _pendingResultSeq;
  Uint8List? _pendingResultPayload;

  // ---- 模擬センサ状態 ----
  DateTime? _sessionStart;
  double _baselinePpb = 3200; // 犬の空腹時呼気の想定ベースライン
  double _breathPhase = 0;
  int _batteryMv = 4100;
  int _sampleCount = 0;
  double _sumPpb = 0;
  int _maxPpb = 0;
  int _minPpb = 1 << 30;

  static const _fwStateIdle = 2; // SM_IDLE
  static const _fwStateMeasuring = 3; // SM_MEASURING

  @override
  Stream<HppFrame> get frames => _frameController.stream;

  @override
  Stream<BluetoothConnectionState> get connectionState =>
      _stateController.stream;

  @override
  Stream<List<ScannedDevice>> scan(
      {Duration timeout = const Duration(seconds: 10)}) {
    // 実機同様、少し遅れて発見される
    return Stream<List<ScannedDevice>>.periodic(
      const Duration(milliseconds: 600),
      (i) => [
        ScannedDevice(
          id: 'mock-hydropaw-0001',
          name: 'HydroPaw-MOCK',
          rssi: -48 - _rng.nextInt(8),
        ),
      ],
    ).take(5);
  }

  @override
  Future<void> connect(String deviceId) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    _connected = true;
    _stateController.add(BluetoothConnectionState.connected);
  }

  @override
  Future<void> disconnect() async {
    _stopStream();
    _connected = false;
    _stateController.add(BluetoothConnectionState.disconnected);
  }

  @override
  Future<void> send(int type, [List<int> payload = const []]) async {
    if (!_connected) {
      throw const BleException('not connected');
    }
    // FWのACK応答(100ms以内)を模倣
    await Future<void>.delayed(const Duration(milliseconds: 30));
    switch (type) {
      case Hpp.cmdStartCont:
        _ack(type);
        _startStream();
      case Hpp.cmdBreath:
        _ack(type);
        _startBreathSession();
      case Hpp.cmdAckEvt:
        // 信頼配送ACK: 再送を止める(応答は返さない — FWと同じ)
        if (payload.isNotEmpty && payload[0] == _pendingResultSeq) {
          _arqTimer?.cancel();
          _pendingResultSeq = null;
          _pendingResultPayload = null;
        }
      case Hpp.cmdStop:
        _ack(type);
        if (_breathTimer != null) {
          _stopBreathSession(); // 呼気セッション中止(部分結果は破棄)
        } else {
          if (emitSummary) _emitSummary();
          _stopStream();
        }
      case Hpp.cmdSingle:
        _ack(type);
        _emitData(single: true);
      case Hpp.cmdGetStatus:
        _ack(type);
        _emitStatus();
      case Hpp.cmdGetInfo:
        _ack(type);
        _emitInfo();
      case Hpp.cmdSleep || Hpp.cmdWake || Hpp.cmdZero:
        _ack(type);
      default:
        _emit(Hpp.nak, [type, 0x05 /* E_INVALID_CMD */]);
    }
  }

  void dispose() {
    _dataTimer?.cancel();
    _breathTimer?.cancel();
    _arqTimer?.cancel();
    _frameController.close();
    _stateController.close();
  }

  /// テスト専用: 任意のフレームを受信ストリームへ注入する
  /// (再接続後のEVT_STATUS再同期などの検証に使用)。
  @visibleForTesting
  void debugEmitFrame(HppFrame frame) => _frameController.add(frame);

  // ---- 内部 ----

  void _startStream() {
    if (_measuring) return;
    _measuring = true;
    _sessionStart = DateTime.now();
    _sampleCount = 0;
    _sumPpb = 0;
    _maxPpb = 0;
    _minPpb = 1 << 30;
    _dataTimer = Timer.periodic(
        const Duration(seconds: 1), (_) => _emitData());
  }

  void _stopStream() {
    _measuring = false;
    _dataTimer?.cancel();
    _dataTimer = null;
  }

  void _ack(int cmd) => _emit(Hpp.ack, [cmd]);

  /// 呼気を模した波形: ベースライン + ゆっくりしたドリフト +
  /// 周期的な呼気ピーク + ノイズ。ウォームアップ中はフラグ付き。
  void _emitData({bool single = false}) {
    final elapsed = DateTime.now().difference(_sessionStart ?? DateTime.now());
    final tMs = elapsed.inMilliseconds;

    _breathPhase += 0.10 + _rng.nextDouble() * 0.04;
    _baselinePpb += (_rng.nextDouble() - 0.5) * 60;
    _baselinePpb = _baselinePpb.clamp(1500, 9000);

    final breath = max(0.0, sin(_breathPhase)) * 2600; // 呼気ピーク
    final noise = (_rng.nextDouble() - 0.5) * 240;
    final ppb = (_baselinePpb + breath + noise).round().clamp(0, 130000);

    final tempC10 = 248 + _rng.nextInt(8); // 24.8-25.5℃
    final rh10 = 420 + _rng.nextInt(30); // 42-45%

    var flags = 0;
    if (tMs < 60000) flags |= Hpp.flagWarmup;

    if ((flags & 0x03) == 0) {
      _sampleCount++;
      _sumPpb += ppb;
      if (ppb > _maxPpb) _maxPpb = ppb;
      if (ppb < _minPpb) _minPpb = ppb;
    }
    _batteryMv = max(3300, _batteryMv - (_rng.nextInt(10) == 0 ? 1 : 0));

    final p = ByteData(13)
      ..setUint32(0, tMs, Endian.little)
      ..setInt32(4, ppb, Endian.little)
      ..setInt16(8, tempC10, Endian.little)
      ..setUint16(10, rh10, Endian.little)
      ..setUint8(12, flags);
    _emit(Hpp.evtData, p.buffer.asUint8List());

    if (single) _stopStream();
  }

  void _emitSummary() {
    final duration = _sessionStart == null
        ? 0
        : DateTime.now().difference(_sessionStart!).inSeconds;
    final avg = _sampleCount == 0 ? 0 : (_sumPpb / _sampleCount).round();
    final p = ByteData(16)
      ..setUint16(0, _sampleCount, Endian.little)
      ..setInt32(2, avg, Endian.little)
      ..setInt32(6, _maxPpb, Endian.little)
      ..setInt32(10, _sampleCount == 0 ? 0 : _minPpb, Endian.little)
      ..setUint16(14, duration, Endian.little);
    _emit(Hpp.evtSummary, p.buffer.asUint8List());
  }

  void _emitStatus() {
    final p = ByteData(12)
      ..setUint8(0, _measuring ? _fwStateMeasuring : _fwStateIdle)
      ..setUint16(1, _batteryMv, Endian.little)
      ..setUint8(3, 1)
      ..setUint32(4, DateTime.now().millisecondsSinceEpoch ~/ 1000 % 86400,
          Endian.little)
      ..setUint16(8, 0, Endian.little) // crc_errors
      ..setUint16(10, 0, Endian.little); // resyncs
    _emit(Hpp.evtStatus, p.buffer.asUint8List());
  }

  void _emitInfo() {
    final p = Uint8List(14);
    p[0] = 1; // fw major
    p[1] = 1; // fw minor
    p.setRange(2, 14, '032122030234'.codeUnits);
    _emit(Hpp.evtInfo, p);
  }

  void _emit(int type, List<int> payload) {
    if (_frameController.isClosed) return;
    _frameController.add(
        HppFrame(type, _seq++ & 0xFF, Uint8List.fromList(payload)));
  }

  // ---- 呼気セッション(BAP): FWの WARMUP→READY→BREATH→ANALYZE→RESULT を
  //      短縮タイムライン(約20秒)で模倣する。 ----

  void _startBreathSession() {
    _sessionId++;
    _breathTick = 0;
    _sessionStart = DateTime.now();
    _measuring = true;
    _emitPhase(Hpp.phaseWarmup);
    _breathTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _breathStep());
  }

  void _stopBreathSession() {
    _breathTimer?.cancel();
    _breathTimer = null;
    _measuring = false;
  }

  void _emitPhase(int phase, [int detail = 0]) =>
      _emit(Hpp.evtPhase, [phase, detail]);

  void _breathStep() {
    _breathTick++;
    final t = _breathTick;
    // タイムライン: 1-3s WARMUP / 4-6s READY / 7-16s BREATH / 17s ANALYZE / 18s RESULT
    const baseline = 1800.0;
    double ppb = baseline + (_rng.nextDouble() - 0.5) * 120;
    if (t == 4) _emitPhase(Hpp.phaseReady);
    if (t == 7) _emitPhase(Hpp.phaseBreath);
    if (t >= 7 && t <= 16) {
      // 立上り→プラトーの呼気波形
      final k = (t - 6) / 4.0;
      ppb = baseline + 5200 * (k > 1 ? 1 : k) + (_rng.nextDouble() - 0.5) * 200;
    }
    _emitBreathData(ppb.round(), humid: t >= 7 && t <= 16);
    if (t == 17) _emitPhase(Hpp.phaseAnalyze);
    if (t >= 18) {
      _stopBreathSession();
      _emitPhase(Hpp.phaseDone, 92);
      _emitResult();
    }
  }

  void _emitBreathData(int ppb, {required bool humid}) {
    final tMs =
        DateTime.now().difference(_sessionStart ?? DateTime.now()).inMilliseconds;
    final p = ByteData(13)
      ..setUint32(0, tMs, Endian.little)
      ..setInt32(4, ppb, Endian.little)
      ..setInt16(8, 250 + _rng.nextInt(6), Endian.little)
      ..setUint16(10, humid ? 460 + _rng.nextInt(20) : 400 + _rng.nextInt(8),
          Endian.little)
      ..setUint8(12, 0);
    _emit(Hpp.evtData, p.buffer.asUint8List());
  }

  /// EVT_RESULT(30B)。ACK_EVTが来るまで1秒間隔で再送する(選択的ARQ模倣)。
  void _emitResult() {
    final quality = 88 + _rng.nextInt(10); // 高品質呼気
    const confidence = 100;
    const flags = Hpp.rfRhOk | Hpp.rfWarmupOk;
    final p = ByteData(30)
      ..setUint8(0, _sessionId & 0xFF)
      ..setUint8(1, quality)
      ..setUint8(2, confidence)
      ..setUint8(3, flags)
      ..setInt32(4, 1800, Endian.little) // baseline
      ..setInt32(8, 5300, Endian.little) // peak
      ..setInt32(12, 4900, Endian.little) // plateau
      ..setUint32(16, 46000, Endian.little) // AUC
      ..setUint16(20, 42, Endian.little) // rise 4.2s
      ..setUint16(22, 100, Endian.little) // duration 10.0s
      ..setInt16(24, 252, Endian.little)
      ..setInt16(26, 62, Endian.little) // ΔRH +6.2%
      ..setUint16(28, 40, Endian.little); // pre-MAD
    final payload = p.buffer.asUint8List();
    final seq = _seq & 0xFF; // _emitが使うSEQを控えて再送に使う
    _pendingResultSeq = seq;
    _pendingResultPayload = Uint8List.fromList(payload);
    _emit(Hpp.evtResult, payload);
    var attempts = 1;
    _arqTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_pendingResultSeq == null || attempts >= 5) {
        timer.cancel();
        return;
      }
      attempts++;
      // 同一SEQで再送(受信側の重複排除を通す) — FWと同じ振る舞い
      if (!_frameController.isClosed && _pendingResultPayload != null) {
        _frameController.add(
            HppFrame(Hpp.evtResult, _pendingResultSeq!, _pendingResultPayload!));
      }
    });
  }
}
