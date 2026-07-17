/// BLE関連の定数 — **UUIDはここ1箇所にのみ定義する**。
///
/// AC02 (Lapis MK71511) の仮想UARTサービスUUIDは実機未確認のため、
/// 以下は docs/03_ble_spec.md 記載の暫定値。実機到着後、
/// nRF Connect等でサービス構成を確認し、この3つの値だけを差し替える。
/// (webapp/src/providers/BleProvider.ts の同名定数も同時に更新すること)
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

abstract final class BleUuids {
  /// 仮想UARTサービス (要実機確認)
  static final service = Guid('0179bbd0-5351-48b5-bf6d-2167639bc867');

  /// FW→App (Notify) (要実機確認)
  static final tx = Guid('0179bbd1-5351-48b5-bf6d-2167639bc867');

  /// App→FW (Write Without Response) (要実機確認)
  static final rx = Guid('0179bbd2-5351-48b5-bf6d-2167639bc867');

  /// Advertising名のprefix (スキャンフィルタに使用)
  static const namePrefix = 'HydroPaw';
}
