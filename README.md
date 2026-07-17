# HydroPaw — 犬呼気水素モニタリングシステム

犬の呼気に含まれる水素濃度(H2)を DGS2センサ + STM32 (Leafony AP03) + BLE (Leafony AC02) で測定し、
Flutterアプリで可視化・Firebaseで管理するシステムの完全な設計・実装一式。

```
犬の呼気 → DGS2 → [UART] → STM32(AP03) → [BLE/AC02] → Flutterアプリ → Firebase
```

## 構成

| パス | 内容 |
|---|---|
| `docs/01`〜`10` | 設計書(アーキテクチャ/BLE仕様/STM32仕様/Flutter仕様/Firebase/DB/UI/API/計画・テスト) |
| `firmware/` | STM32ファームウェア (STM32CubeIDE, HAL, `.ioc`付き) + ホスト単体テスト |
| `app/` | Flutterアプリ (Riverpod / GoRouter / Freezed / Hooks / Material3, 日英対応) |
| `firebase/` | Firestoreルール・インデックス・Storageルール・Cloud Functions |

## クイックスタート

1. **設計を読む**: `docs/01_architecture.md` から順に。
2. **ファームウェア**: `firmware/README.md`。単体テストは `cd firmware/Tests && make test`(検証済み: 48アサーション green)。
3. **アプリ**: `app/README.md`。`flutter pub get && dart run build_runner build && flutterfire configure`。
4. **クラウド**: `cd firebase && firebase deploy`(エミュレータ: `firebase emulators:start`)。

## 機器間プロトコル (HPP)

BLEはAC02のUART透過ブリッジを使い、その上に独自バイナリプロトコル **HPP**
(SOF/CRC16/SEQ付きフレーム)を定義。C実装とDart実装は同一テストベクタ
(CRC `0x53CC`)で相互検証済み。詳細は `docs/03_ble_spec.md`。

## 実機投入前の要確認事項

- AC02 (MK71511) の仮想UARTサービスUUID → `app/lib/features/ble/data/ble_service.dart` の `BleUuids`
- DGS2のCSV列構成(ロットにより差異の可能性) → `firmware/App/Src/dgs2.c` のパーサ
- 電池分圧比・DGS2電源制御ピン → `firmware/Core/Inc/main.h`
