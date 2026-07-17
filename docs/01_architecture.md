# ① システム全体アーキテクチャ — HydroPaw

犬の呼気水素濃度(H2)を測定・記録・可視化するシステム。プロジェクト名 **HydroPaw**。

## 1. 全体構成(固定)

```
犬の呼気
  ↓ (呼気採取マスク/チャンバー)
DGS2 水素センサ (SPEC Sensors, UART 9600bps 8N1)
  ↓ USART1 (CSVテキスト)
STM32L452RE (Leafony AP03 STM32 MCUリーフ)
  │  DGS2制御 / パース / 異常値チェック / 状態管理 / 低消費電力
  ↓ USART2 (HPPバイナリフレーム)
Leafony AC02 BLE Sugar (Lapis MK71511, UART透過ブリッジ)
  ↓ BLE (GATT: UART透過サービス, Notify/Write)
Flutterアプリ (iOS / Android)
  │  リアルタイムグラフ / 測定管理 / 犬プロフィール
  ↓ HTTPS (Firebase SDK)
Firebase (Auth / Firestore / Storage / Crashlytics / Analytics)
```

## 2. レイヤ責務

| レイヤ | 責務 | 責務外 |
|---|---|---|
| DGS2 | H2濃度(ppb)・温度・湿度の測定とCSV出力 | 判定・保存 |
| STM32 FW | センサ制御、パース、検証、HPPフレーム化、省電力、状態管理 | UI、クラウド、BLEスタック(AC02に委譲) |
| AC02 | BLE GATT ⇔ UART の透過ブリッジ | データ加工 |
| Flutter | 接続管理、HPP解釈、可視化、クラウド同期、UX | センサ制御ロジックの重複実装 |
| Firebase | 認証、永続化、画像、集計(Functions)、監視 | リアルタイム波形処理 |

## 3. データフロー

1. **測定**: App→`CMD_START`→STM32→DGS2連続測定(1Hz)→`EVT_DATA`(1Hz Notify)→Appがバッファに蓄積しグラフ描画。
2. **終了**: App→`CMD_STOP`→STM32が統計(平均/最大/サンプル数)を`EVT_SUMMARY`で返送→AppがMeasurementとしてFirestoreに保存。
3. **オフライン**: Firestoreオフライン永続化で保持、再接続時に自動同期。
4. **画像**: 犬の写真はStorage、URLをFirestore `dogs` に保持。

## 4. 主要設計判断 (ADR要約)

| # | 決定 | 理由 |
|---|---|---|
| A1 | AC02はUART透過ブリッジとして使用(カスタムGATT不採用) | AC02実機のファーム書換え不要。BLE仕様は透過サービス上の独自フレーミング(HPP)で担保 |
| A2 | HPPはバイナリ固定ヘッダ+CRC16 | BLE MTU(20B〜)分割耐性、破損検出、version/typeで前方互換 |
| A3 | 1Hz連続モニタをコア、単発測定も対応 | 省電力はIdle時 STOP2 + DGS2 Sleepで確保 |
| A4 | 波形生データはクラウドへ送らずサマリ+間引き系列(最大600点)を保存 | Firestoreコスト・1MBドキュメント制限対策 |
| A5 | Clean Architecture / Feature First / Repository / MVVM(Controller=ViewModel) | 保守性最優先、テスト容易性 |
| A6 | エラーコードはC/Dartで単一対応表を共有(docs/03) | 二重定義による不整合防止 |

## 5. 非機能要件

- **省電力**: Idle時 MCU STOP2(<10µA)+DGS2 Sleep(<1mA)。測定中のみフルアクティブ。
- **信頼性**: 全UART受信はIT+リングバッファ、CRC16検証、タイムアウト+リトライ(3回)+IWDG(8s)。
- **BLE切断耐性**: Appは指数バックオフ再接続(1s→2s→4s…最大30s)。FWは接続喪失後60s測定継続し安全停止→Sleep。
- **セキュリティ**: Firestoreルールでuid完全分離。BLEはペアリング+アプリ層でデバイスID検証。
- **アクセシビリティ**: 最小フォント16sp、タップ領域48dp、WCAG AAコントラスト、日英対応。

## 6. 異常シナリオ

| シナリオ | 挙動 |
|---|---|
| センサ未応答 | FW: 3回リトライ→`EVT_ERROR(E_SENSOR_TIMEOUT)`→App: エラー画面+再試行導線 |
| 異常値(範囲外/固着) | FW: フラグ付き`EVT_DATA`。Appはグレー表示し統計から除外 |
| BLE切断(測定中) | App: データ保持+自動再接続。FW: 60s猶予後 STOP→Sleep |
| クラウド不達 | Firestoreオフラインキャッシュ→自動再送 |
| 電池低下 | `EVT_STATUS.battery_mv`をAppが監視、閾値で警告 |
