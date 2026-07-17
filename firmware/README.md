# HydroPaw Firmware (Leafony AP03 / STM32L452RE)

## ビルド (STM32CubeIDE)
1. `HydroPaw.ioc` をCubeMX/CubeIDEで開きコード生成(HALドライバ・スタートアップが展開される)。
2. `Core/Src/main.c`, `Core/Src/stm32l4xx_it.c`, `Core/Inc/*` は本リポジトリ版で上書き
   (USER CODEセクション互換のため生成コードと共存可)。
3. プロジェクト設定 → C/C++ Build → Source Location に `App/` を追加、
   Include Path に `App/Inc` を追加。
4. ビルド → ST-Link で書込み。

## ホスト単体テスト
```
cd Tests && make test
```
HAL非依存モジュール (hpp / dgs2 / ring_buffer) を gcc でビルドし実行する。

## 配線 (Leafonyバス)
| STM32 | 接続先 |
|---|---|
| PA9/PA10 (USART1) | DGS2 RX/TX (9600bps) |
| PA2/PA3 (USART2) | AC02 UART (115200bps) |
| PA4 (ADC IN9) | 電池分圧(1/2) |
| PA8 | DGS2電源スイッチ(任意) |
| PB0 | 状態LED |
