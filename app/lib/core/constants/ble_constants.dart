/// BLE関連の定数 — **UUIDはここ1箇所にのみ定義する**。
///
/// AC02 (Leafony BLE Sugar) の仮想UARTサービスUUID。
/// 2026-07-20 に実機(AC02)へ接続し nRF Connect でGATT構成を確認・確定。
/// (webapp/src/providers/BleProvider.ts の同名定数も同時に更新すること)
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

abstract final class BleUuids {
  /// 仮想UARTサービス (実機確認済み 2026-07-20)
  static final service = Guid('442f1570-8a00-9a28-cbe1-e1d4212d53eb');

  /// FW→App (Notify) (実機確認済み)
  static final tx = Guid('442f1571-8a00-9a28-cbe1-e1d4212d53eb');

  /// App→FW (Write / Write Without Response) (実機確認済み)
  static final rx = Guid('442f1572-8a00-9a28-cbe1-e1d4212d53eb');

  /// Advertising名のprefix (スキャンフィルタに使用)。
  /// AC02はService UUIDを広告せず、既定名 "Leaf_A_#<id>" で広告するため
  /// 名前prefixで絞り込む (実機確認済み 2026-07-20)。
  /// 将来FW側でカスタム広告名を設定したら "HydroPaw" 等へ更新する。
  static const namePrefix = 'Leaf_A';
}
