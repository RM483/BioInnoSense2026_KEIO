# ③ BLE仕様 — HPP (HydroPaw Protocol) v1

## 1. 前提
AC02 (Lapis MK71511) は **UART透過ブリッジ**として使用する(ファーム書換え不要)。
GATTはモジュール標準の仮想UARTサービスをそのまま利用し、アプリケーション仕様は
その上のバイト列プロトコル **HPP** で定義する。

## 2. GATT (AC02仮想UARTサービス)

| 項目 | 値 | 備考 |
|---|---|---|
| Device Name | `HydroPaw-XXXX` (XXXX=ユニークID下4桁) | Advertising |
| Service | 仮想UARTサービス (MK71511標準) | UUIDは `ble_constants.dart` / AC02実機で要確認 |
| TX Characteristic (FW→App) | **Notify** | HPPフレームを透過送信 |
| RX Characteristic (App→FW) | **Write Without Response** | HPPコマンド |
| MTU | 247要求 (最低23で動作可) | フレームは20B分割受信を前提に再組立 |

> UUID既定値(要実機確認): Service `0179bbd0-5351-48b5-bf6d-2167639bc867`,
> TX `0179bbd1-…`, RX `0179bbd2-…`。異なる場合は定数1箇所の変更で対応。

Read系(状態・情報)はCharacteristic Readではなく `CMD_GET_STATUS` / `CMD_GET_INFO` で実現する
(透過ブリッジのため)。

## 3. HPPフレーム形式

```
+------+------+------+------+------+---------------+----------+
| SOF  | VER  | TYPE | SEQ  | LEN  | PAYLOAD       | CRC16    |
| 0xA5 | 0x01 | u8   | u8   | u8   | LEN bytes(≤48)| u16 BE   |
+------+------+------+------+------+---------------+----------+
```
- **SEQ**: 送信毎に+1 (ロス検出用)。**CRC16**: CCITT-FALSE (poly 0x1021, init 0xFFFF)、SOF〜PAYLOAD末尾まで。
- マルチバイト値はリトルエンディアン (CRCのみBE)。
- 受信側はSOF探索→LEN分待機→CRC検証。不正時は1バイト捨てて再同期。

## 4. コマンド (App→FW)

| TYPE | 名称 | Payload | 説明 |
|---|---|---|---|
| 0x01 | CMD_START_CONT | interval_s:u8 (1..60) | 連続測定開始 (1=1Hz) |
| 0x02 | CMD_STOP | - | 測定停止→EVT_SUMMARY返送 |
| 0x03 | CMD_SINGLE | - | 単発測定→EVT_DATA 1回 |
| 0x04 | CMD_SLEEP | - | DGS2 Sleep+MCU STOP2 |
| 0x05 | CMD_WAKE | - | 復帰 (UART RXで自動Wake後の明示確認。ERROR状態からの復旧試行も担う) |
| 0x06 | CMD_GET_STATUS | - | EVT_STATUS要求 |
| 0x07 | CMD_GET_INFO | - | EVT_INFO要求 |
| 0x08 | CMD_ZERO | - | DGS2ゼロ校正('Z')。IDLE時のみ受理(クリーンエア中に実行すること) |

全コマンドに対し FW は **ACK(0x40)** または **NAK(0x41)** を100ms以内に返す。

## 5. 応答・イベント (FW→App)

| TYPE | 名称 | Payload |
|---|---|---|
| 0x40 | ACK | cmd:u8 |
| 0x41 | NAK | cmd:u8, err:u8 |
| 0x81 | EVT_DATA | t_ms:u32, h2_ppb:i32, temp_c10:i16, rh_10:u16, flags:u8 (13B) |
| 0x82 | EVT_SUMMARY | n:u16, avg_ppb:i32, max_ppb:i32, min_ppb:i32, duration_s:u16 (16B) |
| 0x83 | EVT_STATUS | state:u8, battery_mv:u16, sensor_ok:u8, uptime_s:u32, crc_errors:u16, resyncs:u16 (12B) ※末尾4Bはv1.1追加の診断統計。旧8B形式とは前方互換(受信側は先頭8Bのみ必須) |
| 0x84 | EVT_ERROR | code:u8, detail:u8 |
| 0x85 | EVT_INFO | fw_major:u8, fw_minor:u8, sensor_sn:char[12] |

`temp_c10` = 温度×10 (25.3℃→253)。`rh_10` = 湿度×10。

### EVT_DATA flags
| bit | 意味 |
|---|---|
| 0 | OUT_OF_RANGE (測定レンジ外) |
| 1 | STUCK (固着疑い: 30サンプル完全同値) |
| 2 | WARMUP (ウォームアップ中、参考値) |
| 3 | UNSTABLE (温湿度急変中) |

## 6. エラーコード (C/Dart共通)

| code | 名称 | App側の扱い |
|---|---|---|
| 0x00 | OK | - |
| 0x01 | E_SENSOR_TIMEOUT | エラー画面+再試行 |
| 0x02 | E_SENSOR_PARSE | 再試行(自動) |
| 0x03 | E_OUT_OF_RANGE | 値をグレー表示 |
| 0x04 | E_BUSY | 前操作完了待ちトースト |
| 0x05 | E_INVALID_CMD | 内部エラー報告(Crashlytics) |
| 0x06 | E_INVALID_PARAM | 同上 |
| 0x07 | E_LOW_BATTERY | 電池警告 |
| 0x08 | E_INTERNAL | エラー画面 |
| 0x09 | E_CRC | 自動再送要求(コマンド再送) |

## 7. 通信タイミング

```
App                 FW(STM32)              DGS2
 |--CMD_START_CONT-->|                       |
 |<------ACK---------|--'C' (連続開始)------>|
 |                   |<---CSV(1Hz)-----------|
 |<--EVT_DATA(1Hz)---|  (パース+検証)         |
 |--CMD_STOP-------->|--'C' (連続停止)------>|
 |<------ACK---------|                       |
 |<--EVT_SUMMARY-----|                       |
 |--CMD_SLEEP------->|--'s' (Sleep)--------->|
 |<------ACK---------|  MCU→STOP2            |
```
※ DGS2の連続測定コマンドは**大文字'C'**(コマンドは大文字/小文字を区別 — データシートRev 24a)。
- EVT_DATA間隔: interval_s (既定1s)。ACKタイムアウト: App側300ms、2回再送、失敗でエラー表示。
- Keep-alive: Appは接続中常時30s毎に CMD_GET_STATUS(接続監視・バッテリー取得・FW自動停止の抑止を兼ねる)。

## 8. 再接続戦略 (App)

1. 切断検知 → 1s, 2s, 4s, 8s… 最大30s間隔の指数バックオフで自動再接続(ユーザー操作なし)。
2. 再接続成功 → `CMD_GET_STATUS` で FW 状態を取得し UI 状態を再同期
   (FWが測定継続中なら測定表示へ復帰)。
3. 5分失敗 → 再接続画面へ誘導。
4. FW側: 切断中も測定は60s継続し、60s超で自動STOP+Sleep。
   **切断中のデータはFW側でバッファ・再送しない**(AC02は透過ブリッジで
   FWは接続状態を直接知り得ないため)。切断期間のサンプルは欠測となり、
   AppがSEQ跳びから欠測数を検出・記録する(`droppedFrames`)。
