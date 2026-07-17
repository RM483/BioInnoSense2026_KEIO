# ⑬ 実機テスト手順書 (STM32ファームウェア)

対象: Leafony AP03 (STM32L452RETxP) + DGS2 970-001(H2) + AC02 BLE Sugar。
ホスト単体テスト(218アサーション)で担保済みの部分は再テスト不要 —
ここには **実機でしか確認できない項目** だけを載せる。

準備物: ST-Link, USB-UARTアダプタ(LPUART1ログ用, 115200bps),
電流計(μAレンジ), 可変電源(電池テスト用), nRF Connect(スマホ),
水素源(校正ガス or 呼気), Tera Term等。

---

## T0. 書き込みと初回起動 (オプションバイト)

1. `firmware/README.md` の手順でCubeIDEからDebugビルドを書き込む。
2. LPUART1ログを観察。**初回起動時のみ**オプションバイト書換えによる
   自動リセットが1回入る(ログが2回 `HydroPaw FW v1.x boot` を出す)。
3. STM32CubeProgrammer → OB画面で `IWDG_STOP = 0 (frozen)` を確認。
   - [ ] 合格基準: 2回目以降の起動でリセットループが起きない
   - 失敗時: FWは自動的にSTOP2を諦めRun待機する(`STOP2 skipped:` ログ)。
     動作は正常のまま消費電流のみ増える。OBを手動で書き換えて再確認。

## T1. ピン割当の実配線確認 (Leafonyバス)

docs/04の表と基板実配線を1本ずつ導通確認:
PA9/PA10↔DGS2, PA2/PA3↔AC02, PC1/PC0↔デバッグUART, PA4↔電池分圧,
PA8↔DGS2電源SW(実装されている場合), PB0↔LED。
- [ ] 特にDGS2のTX/RXクロス接続(DGS2のTXD→PA10)
- [ ] 電池分圧比が1/2であること(実測: 電池4.0V時にPA4=2.0V)

## T2. DGS2通信と実測値

1. 起動ログ後、LEDが消灯(IDLE)になること = SN取得成功。
2. Tera TermでLPUART1に `state 1 -> 2` (SENSOR_INIT→IDLE)が出る。
3. **実測値確認**: nRF Connectを使わず、まずDGS2単体をUSB-UARTで直結し
   `\r` 送信→7フィールドCSVが返ることを確認(ロット差の検出)。
   - [ ] TEMP/RHが×100スケールであること(例: 2436 = 24.36℃)
   - [ ] SNが12桁英数字
4. 呼気/H2ガスを当てPPB値が上昇すること(ダミー値でない実測の確認)。
5. ゼロ校正: クリーンエアで1時間(理想24時間)通電後、アプリ設定または
   nRF ConnectからCMD_ZERO(下記T3のフレーム)を送りPPBが0近傍になること。

## T3. BLE往復 (nRF Connectでの生フレーム試験)

AC02の仮想UARTサービスUUIDを確認し、`app/lib/core/constants/
ble_constants.dart` と `webapp/src/providers/BleProvider.ts` を実UUIDに更新。

nRF ConnectでRX特性へ以下のHEXをWrite (Without Response):
| コマンド | フレーム(HEX) |
|---|---|
| CMD_START_CONT(1s) | `A5 01 01 00 01 01 53 CC` |
| CMD_STOP | `A5 01 02 01 00` + CRC(実機ログで確認) |
| CMD_GET_STATUS | `A5 01 06 00 00` + CRC |
| CMD_ZERO | `A5 01 08 00 00` + CRC |

- [ ] STARTに対しACK(0x40)が100ms以内に返る
- [ ] EVT_DATA(0x81, 13B)が1Hzで届き、**h2_ppbが呼気で変動する実測値**
- [ ] STOPでEVT_SUMMARY(0x82, 16B)が返る
- [ ] EVT_STATUS(0x83)が12B(末尾にcrc_errors/resyncs)
- [ ] 未定義TYPE(例:0x30)にNAK(E_INVALID_CMD)

## T4. アプリ結合 (実BLE)

1. `flutter run`(dart-defineなし=実BLE)。スキャンに `HydroPaw-…` が出る。
2. 接続→測定→リアルタイム更新→終了→解析中→結果→履歴保存の一連。
3. - [ ] 測定値がMockと明確に異なる実データパターンであること

## T5. 切断・再接続

1. 測定中にスマホのBluetoothをOFF→アプリが「再接続」表示。
2. 60秒以内にON→自動再接続し測定画面が継続する。
3. 60秒以上放置→FWが自動停止しSleepへ(ログ `state 3 -> 2 -> 4`)。
4. 再接続後にアプリから再開できる。
   - [ ] STOP2からの復帰: 接続後の最初のコマンドはACKが返らない場合が
     ある(Wake消費)。アプリの自動再送で回復すること。

## T6. 低消費電力 (STOP2)

1. IDLEで10秒放置→ログ `enter STOP2`。
2. 電流計で **MCU部が10µA台**(基板全体はAC02+DGS2 Sleepを含め~0.5mA台)
   へ落ちることを確認。
3. 8.2秒以上スリープ→**リセットせず**BLEコマンドで復帰する(T0の核心)。
4. 復帰ログ `wake from STOP2` の後、通常動作。

## T7. ウォッチドッグ & 長時間

1. 連続測定を30分放置→自動停止(セッション上限)しサマリが届く。
2. 一晩(8h以上) IDLE/SLEEPで放置→朝に接続して応答すること
   (ハング・リセットループ・メモリ枯渇がないことの実証)。
3. デバッグで意図的にハングさせる場合: `sm_tick`直前に`while(1);`を
   一時挿入→約8.2秒でリセット→起動ログが出ることを確認(後で削除)。

## T8. 電池低下

1. 可変電源で電池入力を4.0V→3.2Vへ徐々に低下。
2. - [ ] 3.3V未満になって最大60秒以内にEVT_ERROR(E_LOW_BATTERY, detail=電圧/100mV)が1回だけ届く
3. - [ ] アプリ測定中なら**中断せず**電池アイコンの警告が出る
4. 3.4V以上へ戻し再度下げる→再通知される。

## T9. 異常系

- [ ] DGS2ケーブル抜去(測定中)→3秒×3リトライ→EVT_ERROR(E_SENSOR_TIMEOUT)
  →アプリがエラー画面→ケーブル復旧→CMD_WAKEで復帰('r'リセット送信)
- [ ] 起動時にDGS2未接続→2秒×3リトライ→ERROR→LED点滅→60秒でSleep(電池保護)
- [ ] UARTノイズ注入(端子タッチ等)でもCRCで弾かれ、EVT_STATUSの
  crc_errors/resyncsが増えるだけで動作継続

## T10. Release構成

1. Releaseビルド(`HYDROPAW_LOG_DISABLE`定義済み)を書き込み。
2. - [ ] LPUART1が無音でも全機能が動く(ログ依存の動作がない)
3. - [ ] Debug/Releaseで消費電流を比較記録

---

### 既知の実機依存項目 (コードでは未確定)

| 項目 | 対応箇所 |
|---|---|
| AC02仮想UARTサービスUUID | ble_constants.dart / BleProvider.ts (要書換え) |
| DGS2ロットのCSV列差異 | dgs2.c パーサ(7列前提) |
| 電池分圧比・VREF実測 | power.c `power_read_battery_mv` の係数 |
| Leafonyバスの実ピン対応 | HydroPaw.ioc / main.h |
| STOP2復帰時の初回バイト損失量 | T5-4で実測(アプリ再送で吸収) |
