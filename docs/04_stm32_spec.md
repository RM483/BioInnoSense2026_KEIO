# ④ STM32仕様 (Leafony AP03 / STM32L452RE)

## 1. ペリフェラル割当 (CubeMX)

| ペリフェラル | 用途 | 設定 |
|---|---|---|
| USART1 (PA9/PA10) | DGS2センサ | 9600bps 8N1, RX割込み |
| USART2 (PA2/PA3) | AC02 BLE | 115200bps 8N1, RX割込み, **Wakeup from Stop有効(カーネルクロック=HSI16)** |
| LPUART1 (PC1/PC0) | デバッグログ | 115200bps (Releaseは `HYDROPAW_LOG_DISABLE` で無効化) |
| ADC1 IN9 (PA4) | 電池電圧 (分圧1/2) | 12bit, 同期クロック(PCLK/2), ソフトトリガ, 起動時キャリブレーション |
| IWDG | ウォッチドッグ | ~8.2s, メインループでリフレッシュ。**オプションバイトでStop/Standby中フリーズ**(初回起動時に自動書換え+リセット) |
| GPIO PB0 | LED (状態表示) | Push-Pull |
| GPIO PA8 | DGS2電源制御 (ハイサイドSW) | 任意(基板依存) |

クロック: **HSI16 (16MHz) → SYSCLK 16MHz**。低消費電力優先、処理は軽量のため十分。
USART2はStop2からのWakeupのためHSIカーネルクロックを選択。

`firmware/HydroPaw.ioc` に上記を反映済み。CubeMXでコード生成後、`App/` を
ソースパスに追加し `main.c` のUSER CODEセクションがアプリを起動する。

## 2. ステートマシン

```
BOOT ──init ok──> SENSOR_INIT ──SN取得成功──> IDLE(STOP2)
 │                   │ 3回失敗                  │ CMD_START_CONT / CMD_SINGLE
 │                   v                          v
 └──HW fault──> ERROR <──致命的エラー── MEASURING ──CMD_STOP──> IDLE
                    │  CMD_WAKE/リセット           │ CMD_SLEEP
                    └────────────────> IDLE      v
                                               SLEEP(STOP2+DGS2 Sleep)
                                                  │ USART2 RX (BLE経由コマンド)
                                                  └──────> IDLE
```

| 状態 | 動作 | 消費電力 |
|---|---|---|
| BOOT | HAL/クロック/ペリフェラル初期化 | - |
| SENSOR_INIT | DGS2起動確認(Wakeバイト+'\r'→応答)、SN取得 | Run |
| IDLE | コマンド待ち。10s無通信でSleep移行タイマ | Run→STOP2 |
| MEASURING | DGS2連続('C')、1Hzパース→HPP送信 | Run |
| SLEEP | DGS2 's'、MCU STOP2。USART2 RXでWake | <10µA(MCU) |
| ERROR | EVT_ERROR送出、LED点滅。CMD_WAKEで'r'リセット→復帰試行。60sでSLEEPへ(電池保護) | Run→STOP2 |

イベント駆動: メインループは `sm_tick()` を回し、UART RX(割込み→リングバッファ)、
タイマ、コマンドをイベントとして処理。ISR内では**バッファ格納のみ**行い処理しない。

## 3. DGS2 制御 (UARTプロトコル)

コマンドは**大文字/小文字を区別**する(DGS2 970-Seriesデータシート Rev 24a準拠)。

| 送信 | 意味 |
|---|---|
| `\r` | 単発測定(1行応答) |
| `C`  | 連続測定(約1Hz)開始/停止トグル ※大文字 |
| `s`  | Sleep(センサバイアス維持, 0.4mA)。任意の1バイト受信でWake(そのバイトはコマンドとして解釈されない) |
| `Z`  | ゼロ校正(クリーンエア中に実行) |
| `r`  | モジュールリセット(EEPROM設定は保持)。ERROR復旧に使用 |
| `e`  | EEPROM設定・診断ダンプ(複数行テキスト) |

応答CSV(1行, 7フィールド, 末尾 `<space><cr><lf>`):
```
SN[12], PPB, TEMP(℃×100), RH(%×100), ADC_G, ADC_T, ADC_H
例: 032122030234, 1588, 2436, 3278, 32291, 26636, 20390
     (= H2 1588ppb, 24.36℃, 32.78%)
```
パーサはフィールド数(=7)・SN12桁英数字・数値・生値レンジ
(TEMP [-5000:15000], RH [0:10000])を検証し、失敗時 `E_SENSOR_PARSE`。

連続モードのトグル性(状態問い合わせ不可)への対処:
- 開始後 **1.5s以内にデータが無ければ再試行** — 1回目は無害な`\r`プローブ、
  2回目以降は`C`再トグル(最大3回、超過でERROR)。
- IDLE中に測定行が流れ続ける場合(MCUのみリセットされた等)は
  取り残された連続モードと判断し、停止トグルを自動送信(最大3回)。

## 4. 異常値チェック (validator)

レンジはDGS2 H2センサ(110-005: 測定レンジ0-100ppm、短期絶対最大120%)の
データシート値に基づく。

| チェック | 条件 | 処置 |
|---|---|---|
| レンジ | -5,000 ≤ ppb ≤ 120,000 (負側はゼロ点ノイズ許容) | 外れたら flags.OUT_OF_RANGE |
| 温度 | -20 ≤ T ≤ 40℃ (性能保証レンジ) | 外れたら UNSTABLE |
| 湿度 | 15 ≤ RH ≤ 95% (動作レンジ) | 外れたら UNSTABLE |
| 固着 | 直近30サンプル完全同値(≠0) | flags.STUCK |
| ウォームアップ | 測定開始後60s未満 | flags.WARMUP |
| タイムアウト | 連続モードで3s無受信(開始直後は1.5s) | リトライ→E_SENSOR_TIMEOUT |

## 5. 低消費電力設計

- IDLE 10s無通信 → 自動SLEEP (DGS2 's' + STOP2)。
- ERROR 60s滞在 → 自動SLEEP (電池保護。CMD_WAKEで復帰試行可)。
- STOP2復帰: USART2 RXDスタートビット検出(Wakeup from Stop, カーネルクロックHSI16)。
- 復帰後: SystemClock再構成 → IWDG即リフレッシュ → DGS2へWakeバイト → コマンド処理。
- **IWDGはオプションバイト(IWDG_STOP/IWDG_STDBY=FREEZE)でStop中停止**。
  未設定の個体は初回起動時に自動書換え+リセット(power_option_bytes_ensure)。
- 未使用GPIOはAnalog、デバッグログはReleaseで `HYDROPAW_LOG_DISABLE`。

## 6. エラー処理方針

- 全関数は `app_err_t` を返す。ISRはエラーを直接扱わずフラグ化。
- リトライ規定: DGS2通信3回 / 初期化3回。超過で ERROR 状態+`EVT_ERROR`。
- ERROR からの復旧: `CMD_WAKE` 受信で DGS2へ 'r'(モジュールリセット)を送り
  SENSOR_INIT から再初期化。
- IWDG: メインループ毎リフレッシュ。ハング時は自動リセット→BOOT。
- HPPデコーダの `crc_errors` / `resyncs` は EVT_STATUS で報告(診断用)。
- HardFault_Handler: 即時リセット(USER CODEセクション内で実装)。

## 7. モジュール構成と責務

| モジュール | 責務 |
|---|---|
| `ring_buffer` | ISR安全な汎用リングバッファ (SPSC) |
| `dgs2` | DGS2コマンド送信・CSVパース・検証 |
| `hpp` | HPPフレームencode/decode + CRC16 (HAL非依存・ホストテスト対象) |
| `ble_link` | USART2送受信、HPPフレーム抽出、コマンドディスパッチ |
| `state_machine` | 状態遷移・測定統計・サマリ生成 |
| `power` | STOP2移行/復帰、オプションバイト管理、バッテリーADC |
| `log` | LPUART1デバッグログ(printf形式、Release除去可) |
| `app_error` | エラーコード定義(HPPと共通) |
