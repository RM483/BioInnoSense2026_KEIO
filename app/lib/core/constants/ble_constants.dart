/// BLE関連の定数 — **UUIDはここ1箇所にのみ定義する**。
///
/// このブランチ(feature/arduino-fis-variant)は 半導体式(FIS SB-19)+ Arduino Uno R4 WiFi
/// 変種を対象とする。R4は Nordic UART Service (NUS) で HPP フレームを notify する
/// (arduino_fis/config.h と一致)。フレーム形式は本家と同一なので、UUIDと広告名prefixを
/// R4に合わせるだけでアプリはそのまま動作する。
/// (webapp/src/providers/BleProvider.ts の同名定数も同時に更新すること)
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

abstract final class BleUuids {
  /// STM32+AC02実機用 (2026-07-20 実機確認済み / webapp BleProvider と一致)。
  /// Arduino R4(NUS)変種でテストする時は Fuwan/6e400001... へ戻すこと。
  static final service = Guid('442f1570-8a00-9a28-cbe1-e1d4212d53eb');

  /// FW→App (Notify)
  static final tx = Guid('442f1571-8a00-9a28-cbe1-e1d4212d53eb');

  /// App→FW (Write / Write Without Response)
  static final rx = Guid('442f1572-8a00-9a28-cbe1-e1d4212d53eb');

  /// Advertising名のprefix。AC02はService UUIDを広告せず
  /// 既定名 "Leaf_A_#<id>" で広告するため名前prefixで絞る。
  static const namePrefix = 'Leaf_A';
}
