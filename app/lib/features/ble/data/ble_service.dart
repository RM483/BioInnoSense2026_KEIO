/// BLEサービス — flutter_blue_plus のラッパ。
/// AC02 (MK71511) のUART透過サービスに接続し、HPPフレームを送受信する。
import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../core/error/app_exception.dart';
import 'hpp_codec.dart';
import 'mock_ble_repository.dart';

/// `--dart-define=USE_MOCK_BLE=true` でモック(実機なし開発)へ切替。
const bool kUseMockBle =
    bool.fromEnvironment('USE_MOCK_BLE', defaultValue: false);

/// AC02仮想UARTサービスのUUID。
/// NOTE: 実機のAC02ファームウェアで要確認。異なる場合はここだけ変更する。
abstract final class BleUuids {
  static final service = Guid('0179bbd0-5351-48b5-bf6d-2167639bc867');
  static final tx = Guid('0179bbd1-5351-48b5-bf6d-2167639bc867'); // FW→App Notify
  static final rx = Guid('0179bbd2-5351-48b5-bf6d-2167639bc867'); // App→FW Write
  static const namePrefix = 'HydroPaw';
}

class ScannedDevice {
  const ScannedDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });
  final String id;
  final String name;
  final int rssi;
}

abstract interface class BleRepository {
  Stream<List<ScannedDevice>> scan({Duration timeout});
  Future<void> connect(String deviceId);
  Future<void> disconnect();
  Stream<BluetoothConnectionState> get connectionState;
  Stream<HppFrame> get frames;
  Future<void> send(int type, [List<int> payload]);
}

final bleRepositoryProvider = Provider<BleRepository>((ref) {
  if (kUseMockBle) {
    final mock = MockBleRepository();
    ref.onDispose(mock.dispose);
    return mock;
  }
  final service = FlutterBluePlusBleRepository();
  ref.onDispose(service.dispose);
  return service;
});

class FlutterBluePlusBleRepository implements BleRepository {
  final _codec = HppCodec();
  final _frameController = StreamController<HppFrame>.broadcast();
  final _stateController =
      StreamController<BluetoothConnectionState>.broadcast();

  BluetoothDevice? _device;
  BluetoothCharacteristic? _txChar;
  BluetoothCharacteristic? _rxChar;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _stateSub;
  int _txSeq = 0;

  @override
  Stream<HppFrame> get frames => _frameController.stream;

  @override
  Stream<BluetoothConnectionState> get connectionState =>
      _stateController.stream;

  @override
  Stream<List<ScannedDevice>> scan(
      {Duration timeout = const Duration(seconds: 10)}) {
    Future(() async {
      // 二重スキャン開始の例外を防ぐ
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }
      // NOTE: AC02がサービスUUIDをアドバタイズしない場合に備え、
      // UUIDフィルタは使わず名前prefixのみで絞り込む(要実機確認)。
      await FlutterBluePlus.startScan(timeout: timeout);
    });
    return FlutterBluePlus.scanResults.map(
      (results) => results
          .where((r) =>
              r.advertisementData.advName.startsWith(BleUuids.namePrefix))
          .map((r) => ScannedDevice(
                id: r.device.remoteId.str,
                name: r.advertisementData.advName,
                rssi: r.rssi,
              ))
          .toList(),
    );
  }

  @override
  Future<void> connect(String deviceId) async {
    await FlutterBluePlus.stopScan();
    final device = BluetoothDevice.fromId(deviceId);
    _device = device;

    _stateSub?.cancel();
    _stateSub = device.connectionState.listen(_stateController.add);

    await device.connect(timeout: const Duration(seconds: 15));
    if (!device.isConnected) {
      throw const BleException('connect failed');
    }
    await device.requestMtu(247); // 分割を減らす(失敗しても再組立で動作)

    final services = await device.discoverServices();
    final uartService = services.firstWhere(
      (s) => s.uuid == BleUuids.service,
      orElse: () => throw const BleException('UART service not found'),
    );
    _txChar = uartService.characteristics
        .firstWhere((c) => c.uuid == BleUuids.tx,
            orElse: () => throw const BleException('TX char not found'));
    _rxChar = uartService.characteristics
        .firstWhere((c) => c.uuid == BleUuids.rx,
            orElse: () => throw const BleException('RX char not found'));

    _codec.reset();
    await _txChar!.setNotifyValue(true);
    _notifySub?.cancel();
    _notifySub = _txChar!.onValueReceived.listen((chunk) {
      for (final frame in _codec.feed(chunk)) {
        _frameController.add(frame);
      }
    });
  }

  @override
  Future<void> disconnect() async {
    await _notifySub?.cancel();
    _notifySub = null;
    await _device?.disconnect();
    _device = null;
    _txChar = null;
    _rxChar = null;
  }

  @override
  Future<void> send(int type, [List<int> payload = const []]) async {
    final rx = _rxChar;
    if (rx == null) {
      throw const BleException('not connected');
    }
    final frame = HppCodec.encode(type, _txSeq++, payload);
    await rx.write(frame, withoutResponse: true);
  }

  void dispose() {
    _notifySub?.cancel();
    _stateSub?.cancel();
    _frameController.close();
    _stateController.close();
  }
}
