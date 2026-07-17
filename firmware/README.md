# HydroPaw Firmware (Leafony AP03 / STM32L452RE)

STM32CubeIDE標準の開発フローに準拠。`Core/` のCubeMX生成対象ファイルは
すべて正規の **USER CODEセクション** 構造になっており、CubeMXで何度
再生成してもアプリコードは失われない。

## STM32CubeIDEでの開き方

### 初回 (推奨: 既存プロジェクトとしてインポート)
1. STM32CubeIDE → `File > Import… > General > Existing Projects into Workspace`
   → ルートに `firmware/` を指定 → プロジェクト `HydroPaw` をインポート。
2. `HydroPaw.ioc` をダブルクリック → **Generate Code** (Alt+K)。
   `Drivers/`(HAL/CMSIS)・スタートアップ・リンカスクリプト
   (`STM32L452RETXP_FLASH.ld`)が生成される。既存の `main.c` 等は
   USER CODEセクションが保持されたままマージされる。
3. ビルド (`Project > Build`) → ST-Linkで書込み (`Run > Debug/Run`)。

### 代替 (iocから新規作成)
`File > New > STM32 Project from an Existing STM32CubeMX Configuration File (.ioc)`
で `HydroPaw.ioc` を選択しても良い。この場合 `.project/.cproject` が
再作成されるため、`App/Inc` のインクルードパスと `App/` ソースフォルダを
Project Propertiesで追加すること(本リポジトリの `.cproject` には設定済み)。

## 再生成ポリシー
- 設定変更は必ず `HydroPaw.ioc`(CubeMX)で行い、`MX_*_Init` の中身を
  直接編集しない。
- アプリコードは `App/`(CubeMX管理外)と、`Core/` 内のUSER CODE
  セクションのみに書く。
- `Drivers/` `Debug/` `Release/` スタートアップ・リンカスクリプトは
  生成物のためコミットしない(.gitignore済み)。

## 初回起動時の注意 (オプションバイト)
初回起動時、IWDGをStop/Standby中フリーズさせるオプションバイト
(IWDG_STOP/IWDG_STDBY=FREEZE)を自動書換えし、**一度だけ自動リセット**
する(`power_option_bytes_ensure()`)。これが無いとSTOP2でのSleep中に
IWDG(約8.2s)がリセットを発生させる。

## ホスト単体テスト
```
cd Tests && make test
```
HAL非依存モジュール (hpp / dgs2 / ring_buffer / ble_link / state_machine)
をgccでビルドし実行する(215アサーション)。

## 配線 (Leafonyバス)
| STM32 | 接続先 |
|---|---|
| PA9/PA10 (USART1) | DGS2 RX/TX (9600bps 8N1) |
| PA2/PA3 (USART2) | AC02 UART (115200bps) |
| PC1/PC0 (LPUART1) | デバッグログ (115200bps) |
| PA4 (ADC IN9) | 電池分圧(1/2) |
| PA8 | DGS2電源スイッチ(任意) |
| PB0 | 状態LED |

## DGS2プロトコル (データシート Rev 24a 準拠)
- コマンドは大文字/小文字を区別: `\r`=単発, `C`=連続トグル, `s`=Sleep,
  `Z`=ゼロ校正, `r`=リセット, `e`=EEPROMダンプ。
- 測定行は7フィールド: `SN[12], PPB, TEMP(℃×100), RH(%×100), ADC_G, ADC_T, ADC_H`。
- Sleep復帰は「任意の1バイトでWake→改めてコマンド送信」(Wakeバイトは
  コマンドとして解釈されない)。
