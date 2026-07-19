# ⑮ Leafonyピン対応監査 — 公式資料 vs 本リポジトリ

実施日: 2026-07-18 / 方法: 公式一次資料の取得・突合(実機不使用)

## 0. 参照した一次資料

| 資料 | 取得元 | 確認内容 |
|---|---|---|
| Leaf-pinassign.xlsx (AP03/AC02/AV0xシート) | github.com/Leafony/Documents | バスNO⇔ポート対応 |
| AP03仕様書 JA (PDF) | github.com/Leafony/HW-Design-Files | MCU型番・電源・LED/SW |
| AC02仕様書 JA (PDF) | 同上 | モジュール型番・ピン・BGLib API・省電力 |
| 公式サンプル STM32_4-Sensors_BLE.ino | github.com/Leafony/Sample-Sketches | 実際のUART/ボーレート/BGAPI使用法 |
| WebBluetooth_for_Leafony_app (leafony.js) | github.com/Leafony | 標準ファームのGATT UUID |
| docs.leafony.com AP03/AC02/Leafonyバス | 公式docs | 上記の裏取り |

## 1. 公式確定事項 (Leafonyバス ⇔ AP03 STM32)

Leaf-pinassign.xlsx「AP03 STM32 MCU」シートより:

| Bus NO | Bus名 | STM32ポート | 公式機能 |
|---|---|---|---|
| F6 | A0 | **PA4** | ADC1_IN9 |
| F8 | A1 | **PA0** | ADC1_IN5 / **UART TXD** (=UART4_TX) |
| F10 | A2 | **PA1** | ADC1_IN6 / **UART RXD** (=UART4_RX) |
| F12 | A3 | PB0 | ADC1_IN15 |
| F14 | A4 | PC1 | I2C **SDA** |
| F16 | A5 | PC0 | I2C **SCL** |
| F18 | D0 | PA3 | **UART for debug RXD** (=USART2_RX) |
| F20 | D1 | PA2 | **UART for debug TXD** (=USART2_TX) |
| F7 | D6 | PA8 | PWM |
| F9 | D7 | PB12 | (AC02のWAKEUP線と対向) |
| F11 | D8 | PA9 | UART TXD (=USART1_TX) |
| F13 | D9 | PA10 | UART RXD (=USART1_RX) |
| F15 | D10 | PB6 | SPI SS |
| F2 | Res1 | PA13 | SWDIO |

AC02仕様書 2.5節 + サンプルコードより:

| 項目 | 公式値 |
|---|---|
| AC02モジュール | **Silicon Labs BGM11S22F256GA-V2** (EFR32BG1, BT4.2) |
| AC02 UART | **A2=TXD / A1=RXD**(既定)。チップ抵抗付替えでD9/D8へ変更可 |
| AC02 D7 | **WAKEUP入力(H=Wake)** — MCU側からAC02を起こす線 (AP03側=PB12) |
| MCU⇔AC02の公式接続 | **UART4 (PA0=TX, PA1=RX) @ 9600bps** (サンプル `Serialble.begin(9600)`) |
| 制御プロトコル | **BGLib(BGAPI)** — 透過UARTではない |
| 標準ファームGATT | Service `442f1570-8a00-9a28-cbe1-e1d4212d53eb` / Notify(Read) `442f1571-…` / Write `442f1572-…`、notifyハンドル `0x000C` |
| AP03 MCU | **STM32L452REI6 (64pin BGA)** |

## 2. 分類結果

### A. 公式資料とコードが一致

| # | 項目 | 根拠 |
|---|---|---|
| A1 | 電池ADC入力 PA4 = ADC1_IN9 (Bus A0) | pinassign F6一致。.ioc/main.c/power.cと一致 |
| A2 | DGS2用 USART1 = PA9/PA10 は Bus D8/D9 として物理的に存在 | AC02が既定位置(A1/A2)であれば衝突しない |
| A3 | PA8 (Bus D6) は使用可能なGPIO/PWM | SENSOR_PWR用途はバス仕様上問題なし |
| A4 | SWD (PA13等) | デバッグ構成一致 |

### B. 不一致 (公式資料が正、コード側の修正が必要)

| # | 項目 | 公式 | 現コード | 影響 |
|---|---|---|---|---|
| B1 | **MCU型番/パッケージ** | STM32L452**REI6** (UFBGA64) | .ioc: STM32L452**RETxP** (LQFP64/P系) | CubeMX再生成の整合・ピン表示。ポート名は同一のためHALコードへの実害は小 |
| B2 | **AC02接続UART** | **UART4 (PA0/PA1, Bus A1/A2)** | USART2 (PA2/PA3) | **致命的**: 現配置ではAC02と物理的に繋がらない |
| B3 | **デバッグUART** | USART2 (PA2/PA3, Bus D0/D1) | LPUART1 (PC0/PC1) | PC0/PC1はバス上I2C(SCL/SDA)線 — I2Cリーフ併用時に衝突。デバッグはUSART2へ移すべき |
| B4 | **AC02プロトコル** | **BGAPI(BGLib) @9600bps** | 透過UART+HPP直接 @115200bps | **アーキテクチャ不一致**: ble_linkの下位にBGAPIトランスポート層が必要。HPPはnotifyペイロードとして温存可能 |
| B5 | **GATT UUID** | 442f1570/71/72-… (notifyハンドル0x000C) | 仮UUID 0179bbd0-… | app/web/FW docsの更新が必要 |
| B6 | AC02 Wake線 (D7=PB12) | MCU→AC02のWAKEUP出力(BGM11S sleep管理) | 未使用 | AC02省電力(2.8µA)活用に必須 |
| B7 | docs/01,03の「Lapis MK71511」 | 実体はSilicon Labs BGM11S | 記述誤り | docs修正 |

### C. 外部配線情報が不足 (自作リーフ・実装に依存 — 設計者の確認が必要)

| # | 項目 | 備考 |
|---|---|---|
| C1 | **電池分圧回路の所在と分圧比** | AV0x BATリーフはバスへアナログ電圧を出さない(pinassignに記載なし)。分圧は自作29pinリーフ側に実装する前提か、AP03上のAnalog Switch(TS3A4751)経由の実装かを回路図で確認 |
| C2 | DGS2の物理接続先 (D8/D9パッドへの配線方法) | 29pinリーフ(AX02/AX08)の配線図が必要 |
| C3 | SENSOR_PWR(PA8/D6)→DGS2電源SWの実配線 | 同上 |
| C4 | PB0(Bus A3)をLEDに使う場合のLED実装場所 | AP03オンボードLED(DS780)は書込み表示専用でユーザー制御不可 |
| C5 | AP03のAnalog Switch TS3A4751の接続 | 回路図PDF(図面ページ)の目視確認が必要(テキスト抽出不可) |

### D. 実機導通確認のみ必要

| # | 項目 |
|---|---|
| D1 | はんだ・バスコネクタ接触・個体差 |
| D2 | **AC02のチップ抵抗位置が既定(A1/A2)のままか** — D8/D9へ付替え済みの個体ならUSART1(DGS2)と衝突するため最優先で目視 |
| D3 | 分圧比の実測(C1確定後) |

## 3. 設計へ波及する必要変更 (コード凍結中 — 承認後に実施)

1. `.ioc`: MCUを**STM32L452REIx**へ変更、AC02用に**UART4(PA0/PA1)@9600**を追加、
   デバッグUARTを**USART2(PA2/PA3)**へ移設(LPUART1/PC0-PC1は廃止しI2C用に温存)、
   PB12をAC02 WAKEUP出力に。
2. FW: `ble_link`の下位に**BGAPIトランスポート**(BGLib相当の最小実装:
   gatt_server_send_characteristic_notification / attribute_valueイベント受信)を追加。
   HPPフレームはnotify/write値のペイロードとして維持(最大20B/notifyに分割)。
3. STOP2復帰: **UART4のStopモードwakeup対応可否は未確認(UNKNOWN)** —
   RM0394で確認。非対応の場合は PA1(UART4_RX) をEXTI立下りで復帰→UART再開、
   またはAC02→MCU方向の通知線を自作リーフで確保。
4. アプリ/web: UUIDを公式値`442f1570/71/72-…`へ差替え(1箇所ずつ)。
   Write特性はWrite(応答あり)の可能性 — nRF Connectでプロパティ確認(T3)。
5. docs/01・03・04の該当記述修正(MK71511→BGM11S、透過→BGAPI、9600bps)。

## 4. docs/14 クリティカル未確認レジスタへの反映

- AC02 UUID: **公式標準ファーム値が判明**(上表) — 実機T3で「その個体の
  ファームが標準GATTのままか」の確認のみ残る。
- Leafony実ピン: バス⇔ポート対応は**公式確定**。残るのはC1〜C5(外部配線)と
  D1〜D3(物理)のみ。
- 分圧比: 「外部配線情報が不足」へ再分類(実機のみの問題ではない)。

---

## 追補 (専用基板の実配線確定 — KiCad回路図より)

- 専用リーフ: DGS2 TXD→A1 / RXD→A2、V+=3.3V直結(電源ゲートなし)。
- 公式バリアント定義(leafony/platformio-LEAFONY_AP03)で **A1=PA0, A2=PA1** を確定。
  PA0=UART4_TX/PA1=UART4_RXのため配線は電気的に逆 → **CR2.SWAPで救済**。
- FW対応: UART4をUSER CODEで手動初期化(9600 8N1+SWAP+NVIC)。CubeMX管理外に
  した理由: SWAP込み構成を再生成で失わないため(main.c sensor_uart4_init)。
- USART1(PA9/PA10)はセンサから解放し予備へ。SENSOR_PWR(PA8)は実配線なし —
  電源制御はDGS2の's'コマンドのみ(結線されれば従来通り機能する)。
- AC02の実装位置は未確認(A1/A2取り合いの可能性) — 写真待ち。
- TBGLib(leafony公式のBlue Geckoライブラリ)の存在によりAC02=BGAPI説を再確認。


---

## 追補 (専用基板の実配線確定 — KiCad回路図より)

- 専用リーフ: DGS2 TXD→A1 / RXD→A2、V+=3.3V直結(電源ゲートなし)。
- 公式バリアント定義(leafony/platformio-LEAFONY_AP03)で A1=PA0, A2=PA1 を確定。
  PA0=UART4_TX/PA1=UART4_RXのため配線は電気的に逆 → CR2.SWAPで救済。
- FW対応: UART4をUSER CODEで手動初期化(9600 8N1+SWAP+NVIC)。CubeMX管理外に
  した理由: SWAP込み構成を再生成で失わないため(main.c sensor_uart4_init)。
- USART1(PA9/PA10)はセンサから解放し予備へ。SENSOR_PWR(PA8)は実配線なし —
  電源制御はDGS2の's'コマンドのみ。
- AC02の実装位置は未確認(A1/A2取り合いの可能性) — 写真待ち。
- TBGLib(leafony公式のBlue Geckoライブラリ)の存在によりAC02=BGAPI説を再確認。
