/// BLE関連の定数 — **UUIDはここ1箇所にのみ定義する**。
///
/// このブランチ(feature/arduino-fis-variant)は 半導体式(FIS SB-19)+ Arduino Uno R4 WiFi
/// 変種を対象とする。R4は Nordic UART Service (NUS) で HPP フレームを notify する
/// (arduino_fis/config.h と一致)。フレーム形式は本家と同一なので、UUIDと広告名prefixを
/// R4に合わせるだけでアプリはそのまま動作する。
/// (webapp/src/providers/BleProvider.ts の同名定数も同時に更新すること)
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

abstract final class BleUuids {
  /// Nordic UART Service (R4 arduino_fis と一致)
  static final service = Guid('6e400001-b5a3-f393-e0a9-e50e24dcca9e');

  /// FW→App (Notify)
  static final tx = Guid('6e400003-b5a3-f393-e0a9-e50e24dcca9e');

  /// App→FW (Write / Write Without Response)
  static final rx = Guid('6e400002-b5a3-f393-e0a9-e50e24dcca9e');

  /// Advertising名のprefix (スキャンフィルタに使用)。R4は "Fuwan-R4" で広告する。
  static const namePrefix = 'Fuwan';
}
