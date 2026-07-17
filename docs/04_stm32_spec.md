# ④ STM32仕様 (Leafony AP03 / STM32L452RE)

## 1. ペリフェラル割当 (CubeMX)

| ペリフェラル | 用途 | 設定 |
|---|---|---|
| USART1 (PA9/PA10) | DGS2センサ | 9600bps 8N1, RX割込み |
| USART2 (PA2/PA3) | AC02 BLE | 115200bps 8N1, RX割込み, **Wakeup from Stop有効** |
| LPUART1 (PC1/PC0) | デバッグログ | 115200bps (Release時無効化可) |
| ADC1 IN9 (PA4) | 電池電圧 (分圧1/2) | 12bit, ソフトトリガ |
| LPTIM1 | Stop2中の周期wake | LSE 32.768kHz |
| IWDG | ウォッチドッグ | ~8s, 測定ループでリフレッシュ |
| RTC | 稼働時間 | LSE |
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
| SENSOR_INIT | DGS2起動確認('\r'→応答)、SN取得 | Run |
| IDLE | コマンド待ち。10s無通信でSleep移行タイマ | Run→STOP2 |
| MEASURING | DGS2連続('c')、1Hzパース→HPP送信 | Run |
| SLEEP | DGS2 's'、MCU STOP2。USART2 RXでWake | <10µA(MCU) |
| ERROR | EVT_ERROR送出、LED点滅、CMD_WAKEで復帰試行 | Run |

イベント駆動: メインループは `sm_process()` を回し、UART RX(割込み→リングバッファ)、
タイマ、コマンドをイベントとして処理。ISR内では**バッファ格納のみ**行い処理しない。

## 3. DGS2 制御 (UARTプロトコル)

| 送信 | 意味 |
|---|---|
| `\r` | 単発測定(1行応答)。Sleep中はWake |
| `c`  | 連続測定(1Hz)開始/停止トグル |
| `s`  | Sleep |
| `e`  | EEPROM設定ダンプ(SN取得に使用) |

応答CSV(1行, CR/LF終端):
```
SN[12], PPB, TEMP_C, RH, ADC_RAW, T_RAW, RH_RAW, DAY, HOUR, MIN, SEC
例: 010314010306, 1520, 25, 41, 232145, 27store961, 40116, 6, 12, 44, 12
```
パーサはトークン数(≥7)・数値妥当性を検証し、失敗時 `E_SENSOR_PARSE`。
連続モードのトグル性に対処するため、開始/停止時は**1.5s以内のデータ有無で実状態を確認**し、
不一致なら 'c' を再送(最大3回)。

## 4. 異常値チェック (validator)

| チェック | 条件 | 処置 |
|---|---|---|
| レンジ | 0 ≤ ppb ≤ 10,000,000 (10,000ppm) | 外れたら flags.OUT_OF_RANGE |
| 温度 | -20 ≤ T ≤ 60℃ | 外れたら UNSTABLE |
| 固着 | 直近30サンプル完全同値(≠0) | flags.STUCK |
| ウォームアップ | 測定開始後60s未満 | flags.WARMUP |
| タイムアウト | 連続モードで3s無受信 | リトライ→E_SENSOR_TIMEOUT |

## 5. 低消費電力設計

- IDLE 10s無通信 → 自動SLEEP (DGS2 's' + STOP2)。
- STOP2復帰: USART2 RXD立ち上がり(Wakeup from Stop) + LPTIM1(60s毎、バッテリー監視)。
- 復帰後: SystemClock再構成 → DGS2へ '\r' でWake → コマンド処理。
- 未使用GPIOはAnalog、デバッグUARTはRelease時クロック停止。

## 6. エラー処理方針

- 全関数は `app_err_t` を返す。ISRはエラーを直接扱わずフラグ化。
- リトライ規定: DGS2通信3回 / 初期化3回。超過で ERROR 状態+`EVT_ERROR`。
- IWDG: メインループ毎リフレッシュ。ハング時は自動リセット→BOOT。
- HardFault_Handler: エラーLED高速点滅+リセット(Release)。

## 7. モジュール構成と責務

| モジュール | 責務 |
|---|---|
| `ring_buffer` | ISR安全な汎用リングバッファ (SPSC) |
| `dgs2` | DGS2コマンド送信・CSVパース・検証 |
| `hpp` | HPPフレームencode/decode + CRC16 (HAL非依存・ホストテスト対象) |
| `ble_link` | USART2送受信、HPPフレーム抽出、コマンドディスパッチ |
| `state_machine` | 状態遷移・測定統計・サマリ生成 |
| `power` | STOP2移行/復帰、バッテリーADC |
| `app_error` | エラーコード定義(HPPと共通) |
