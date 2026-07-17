# HydroPaw — 犬呼気水素モニタリングシステム

犬の呼気に含まれる水素濃度(H2)を DGS2センサ + STM32 (Leafony AP03) + BLE (Leafony AC02) で測定し、
Flutterアプリで可視化・Firebaseで管理するシステムの完全な設計・実装一式。

```
犬の呼気 → DGS2 → [UART] → STM32(AP03) → [BLE/AC02] → Flutterアプリ → Firebase
                                              └→ Webダッシュボード(デバッグ用)
```

## 構成

| パス | 内容 |
|---|---|
| `docs/01`〜`10` | 設計書(アーキテクチャ/BLE仕様/STM32仕様/Flutter仕様/Firebase/DB/UI/API/計画・テスト) |
| `firmware/` | STM32ファームウェア (STM32CubeIDEプロジェクト, HAL, `.ioc`/`.project`/`.cproject`付き) + ホスト単体テスト |
| `app/` | Flutterアプリ (Riverpod / GoRouter / Freezed / Hooks / Material3, 日英対応, ダークモード対応) |
| `webapp/` | デバッグ用Webダッシュボード (Vite + React + TS, Mock/BLE Provider差替構成) |
| `firebase/` | Firestoreルール・インデックス・Storageルール・Cloud Functions |

## クイックスタート

1. **設計を読む**: `docs/01_architecture.md` から順に。
2. **ファームウェア**: `firmware/README.md`(CubeIDEへのインポート手順)。
   ホスト単体テストは `cd firmware/Tests && make test`(215アサーション green)。
3. **アプリ**: `app/README.md`。`flutter pub get && dart run build_runner build && flutterfire configure`。
   実機なしで動かす場合: `flutter run --dart-define=USE_MOCK_BLE=true`
   (BLEをモックに差し替え、全画面が動作する)。
4. **Webダッシュボード**: `cd webapp && npm install && npm run dev`
   (実機なしでUI/データ表示を検証。詳細は `webapp/README.md`)。
5. **クラウド**: `cd firebase && firebase deploy`(エミュレータ: `firebase emulators:start`)。

## 機器間プロトコル (HPP)

BLEはAC02のUART透過ブリッジを使い、その上に独自バイナリプロトコル **HPP**
(SOF/CRC16/SEQ付きフレーム)を定義。C / Dart / TypeScript の3実装が
同一テストベクタ(CRC `0x53CC`)で相互検証済み。詳細は `docs/03_ble_spec.md`。

DGS2ドライバは公式データシート(970-Series Rev 24a)準拠:
コマンドは大文字/小文字区別('C'=連続トグル, 'Z'=ゼロ校正, 'r'=リセット)、
測定行は7フィールド(温湿度は×100スケール)、H2レンジ0-100ppm。

## 実機投入前の要確認事項

- AC02 (MK71511) の仮想UARTサービスUUID → `app/lib/features/ble/data/ble_service.dart` の `BleUuids`
  (現状スキャンは名前prefix `HydroPaw` のみで絞り込み)
- DGS2のゼロ校正: 長期保管後は1〜24hのクリーンエア安定化後に `CMD_ZERO` を実行(データシート推奨)
- 電池分圧比・DGS2電源制御ピン → `firmware/Core/Inc/main.h`
- 初回書込み時、IWDGオプションバイトの自動書換えで一度だけ自動リセットが入る(`firmware/README.md`)
