# ⑩ 実装計画 & テスト方針

## 実装計画 (フェーズ)

| Phase | 内容 | 完了条件 |
|---|---|---|
| 1 | HPPプロトコル (C/Dart) + 単体テスト | 双方のcodecテスト green |
| 2 | STM32: DGS2ドライバ+ステートマシン | 実機でCSV取得、状態遷移確認 |
| 3 | STM32: BLEリンク+省電力 | スマホからコマンド往復、STOP2電流確認 |
| 4 | Flutter: 基盤(テーマ/ルータ/認証) | ログイン〜ホーム遷移 |
| 5 | Flutter: BLE接続+測定+グラフ | 実機E2Eで1Hz描画 |
| 6 | Flutter: 履歴/犬/食事/症状/設定 | CRUD完了 |
| 7 | Firebase: rules/indexes/Functions | エミュレータテスト green |
| 8 | 統合テスト・電力測定・リリース準備 | チェックリスト全項目 |

## テスト方針

### Unit Test
- **C (ホストPC, firmware/Tests)**: `dgs2` CSVパーサ(正常/欠損/ゴミ/境界)、
  `hpp` encode/decode/CRC/分割再組立/再同期。`make test` で実行。HALはリンク不要の設計。
- **Dart (app/test)**: `HppCodec`(Cと同一テストベクタ)、`Measurement`統計、Repositoryはfake注入。

### Widget Test
- ログイン画面: バリデーション、ボタン活性。ホーム: 犬カード表示。ProviderScope overrideでfake使用。

### Integration Test
- `integration_test/app_test.dart`: 起動→匿名ログイン→ホーム表示。
  BLEはFakeBleRepositoryで模擬フレーム注入し測定フロー(開始→データ→停止→保存)を検証。

### BLE Test (実機)
- 手順書ベース: 接続/切断/再接続(バックオフ)、MTU 23強制時の分割再組立、
  距離減衰、iOS/Androidバックグラウンド遷移、CRC破損注入(テスト用FWフラグ)。

### STM32 Test (実機)
- HILチェックリスト: DGS2タイムアウト(ケーブル抜去)、IWDGリセット、STOP2電流実測、
  60s切断→自動停止、電池電圧境界。

### 品質ゲート
- `flutter analyze` 0 warning / C は `-Wall -Wextra -Werror`。
- カバレッジ目標: codec/パーサ 100%、application層 80%。
