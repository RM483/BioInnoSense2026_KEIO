/// MockBleRepository — 実機(DGS2 + Leafony)が無くても全画面を動かすための
/// BleRepository実装。ファームウェアのステートマシンを簡易に模倣し、
/// 1Hzで現実的なEVT_DATAを生成する。
///
/// 有効化: `flutter run --dart-define=USE_MOCK_BLE=true`
/// (bleRepositoryProvider が本実装へ差し替わる。UI/Controller層は無変更)
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_service.dart';
import 'hpp_codec.dart';

class MockBleRepository implements BleRepository {
  MockBleRepository({this.seed});

  final int? seed;
  late final _rng = Random(seed);

  final _frameController = StreamController<HppFrame>.broadcast();
  final _stateController =
      StreamController<BluetoothConnectionState>.broadcast();

  Timer? _dataTimer;
  bool _connected = false;
  bool _measuring = false;
  int _seq = 0;

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
      case Hpp.cmdStop:
        _ack(type);
        _emitSummary();
        _stopStream();
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
    _frameController.close();
    _stateController.close();
  }

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
}
