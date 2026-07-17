/// BLE接続ViewModel。接続状態管理と指数バックオフ自動再接続を担う。
import 'dart:async';
import 'dart:math';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../data/ble_service.dart';
import '../data/hpp_codec.dart';

enum BleStatus { idle, scanning, connecting, connected, reconnecting, failed }

class BleState {
  const BleState({
    this.status = BleStatus.idle,
    this.devices = const [],
    this.connectedDeviceId,
    this.batteryMv,
  });

  final BleStatus status;
  final List<ScannedDevice> devices;
  final String? connectedDeviceId;
  final int? batteryMv;

  BleState copyWith({
    BleStatus? status,
    List<ScannedDevice>? devices,
    String? connectedDeviceId,
    int? batteryMv,
  }) =>
      BleState(
        status: status ?? this.status,
        devices: devices ?? this.devices,
        connectedDeviceId: connectedDeviceId ?? this.connectedDeviceId,
        batteryMv: batteryMv ?? this.batteryMv,
      );
}

class BleController extends Notifier<BleState> {
  StreamSubscription<List<ScannedDevice>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _stateSub;
  StreamSubscription<HppFrame>? _frameSub;
  Timer? _keepAlive;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _userDisconnected = false;

  static const _maxBackoff = Duration(seconds: 30);
  static const _reconnectGiveUp = Duration(minutes: 5);
  DateTime? _reconnectStartedAt;

  BleRepository get _repo => ref.read(bleRepositoryProvider);

  @override
  BleState build() {
    ref.onDispose(() {
      _scanSub?.cancel();
      _stateSub?.cancel();
      _frameSub?.cancel();
      _keepAlive?.cancel();
      _reconnectTimer?.cancel();
    });
    return const BleState();
  }

  void startScan() {
    state = state.copyWith(status: BleStatus.scanning, devices: []);
    _scanSub?.cancel();
    _scanSub = _repo.scan().listen(
          (devices) => state = state.copyWith(devices: devices),
        );
  }

  Future<void> connect(String deviceId) async {
    _userDisconnected = false;
    state = state.copyWith(status: BleStatus.connecting);
    try {
      await _repo.connect(deviceId);
      _onConnected(deviceId);
    } catch (_) {
      state = state.copyWith(status: BleStatus.failed);
      rethrow;
    }
  }

  void _onConnected(String deviceId) {
    _reconnectAttempt = 0;
    _reconnectStartedAt = null;
    state = state.copyWith(
        status: BleStatus.connected, connectedDeviceId: deviceId);

    // 切断監視 → 自動再接続
    _stateSub?.cancel();
    _stateSub = _repo.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected && !_userDisconnected) {
        _scheduleReconnect(deviceId);
      }
    });

    // EVT_STATUSから電池残量を反映
    _frameSub?.cancel();
    _frameSub = _repo.frames.listen((f) {
      if (f.type == Hpp.evtStatus) {
        state = state.copyWith(batteryMv: f.statusBatteryMv);
      }
    });

    // Keep-alive: 30s毎にステータス要求(接続監視 + FW側の自動停止防止)
    _keepAlive?.cancel();
    _keepAlive = Timer.periodic(const Duration(seconds: 30), (_) {
      _repo.send(Hpp.cmdGetStatus).ignore();
    });
  }

  /// 指数バックオフ再接続 (1,2,4,8…最大30s間隔、5分で断念)
  void _scheduleReconnect(String deviceId) {
    _keepAlive?.cancel();
    _reconnectStartedAt ??= DateTime.now();
    if (DateTime.now().difference(_reconnectStartedAt!) > _reconnectGiveUp) {
      state = state.copyWith(status: BleStatus.failed);
      return;
    }
    state = state.copyWith(status: BleStatus.reconnecting);
    final delay = Duration(
      seconds: min(pow(2, _reconnectAttempt).toInt(), _maxBackoff.inSeconds),
    );
    _reconnectAttempt++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      try {
        await _repo.connect(deviceId);
        _onConnected(deviceId);
        // 再同期: FW状態を取得(測定継続中なら測定画面が追従する)
        await _repo.send(Hpp.cmdGetStatus);
      } catch (_) {
        _scheduleReconnect(deviceId);
      }
    });
  }

  Future<void> disconnect() async {
    _userDisconnected = true;
    _keepAlive?.cancel();
    _reconnectTimer?.cancel();
    await _repo.disconnect();
    state = const BleState();
  }
}

final bleControllerProvider =
    NotifierProvider<BleController, BleState>(BleController.new);
