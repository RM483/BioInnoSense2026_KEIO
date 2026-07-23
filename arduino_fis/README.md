# HydroPaw — 半導体式(FIS SB-19)+ Arduino Uno R4 WiFi 変種

電気化学式(DGS2 + STM32/Leafony)の**別案**。半導体式(MOS)水素センサ **FIS SB-19-00** を
**Arduino Uno R4 WiFi** で読み出し、既存 HydroPaw アプリと同じ **HPPプロトコル**を
**BLE(Nordic UART Service)** で流す。センサ層以外の思想(呼気解析BAP・品質採点・アプリ連携)は
本家と共通。

> 中間発表「読み出し回路」スライドと SB1900J データシートに準拠。

## 1. ハードウェア

### センサ FIS SB-19-00 (SnO2 半導体式・H2高選択)
| 項目 | 値 |
|---|---|
| ヒータ電圧 VH | 0.9 V ±5%（130 mA / **120 mW** 常時加熱） |
| 回路電圧 VC | ≤ 5 V |
| 負荷抵抗 RL | 標準 10 kΩ（>200 Ω 可変） |
| センサ抵抗 Rs | 0.2〜2 kΩ @ H2 100 ppm（**濃度上昇でRs減少**） |
| 動作温度 / 湿度 | −10〜50 ℃ / <95 %RH |

### 読み出し回路（スライド構成）
```
VC(5V) ─ Rs(SB19) ─┬─ VS節点 ─ RL(10k) ─ GND
                    └─→ MCP6022(電圧フォロワ,×1) ─ RC(1kΩ/1µF LPF) ─→ R4 A0 (14bit ADC)
ヒータ VH=0.9V ← LT3080 レギュレータ(常時) ＊要ヒートシンク
```
- `VS = VC · RL/(Rs+RL)`。Rsが下がる(H2↑)と VS が上がる。
- **ADC基準=VC(AVCC=5V) にすると VS/VC が比率になり電源変動がキャンセル**（ratiometric）。
  → `Rs = RL · (1/ratio − 1)`（`config.h: USE_RATIOMETRIC=1`）。

### R4 への配線
| 信号 | R4 ピン | 備考 |
|---|---|---|
| VS（フォロワ+RC後） | **A0** | センサ出力 |
| VC監視(任意) | A1 | ratiometric運用なら未使用可 |
| ヒータEN(任意) | 未使用(-1) | 省電力で間欠加熱したい時のみMOSFET |
| 状態LED | 内蔵LED | 接続中に点灯 |

> ⚠️ ヒータは 120 mW 常時。コイン電池運用は不向き（電気化学式より大喰い）。USB/ACか
> 大容量電池推奨。省電力化は別途パルス加熱の検討が要る。

## 2. ビルド & 書き込み

1. Arduino IDE（またはarduino-cli）で **ボードマネージャ → "Arduino UNO R4 Boards"** を導入。
2. **ライブラリマネージャ → "ArduinoBLE"** を導入。
3. この `arduino_fis/` フォルダを開く（`.ino` と同フォルダの `.h/.cpp` が一緒にコンパイルされる）。
4. ボード = **Arduino UNO R4 WiFi**、ポートを選び、書き込み。
5. シリアルモニタ 115200 で `Fuwan-R4 (FIS SB-19) boot / advertising` を確認。

arduino-cli 例:
```
arduino-cli core install arduino:renesas_uno
arduino-cli lib install ArduinoBLE
arduino-cli compile -b arduino:renesas_uno:unor4wifi arduino_fis
arduino-cli upload  -b arduino:renesas_uno:unor4wifi -p <PORT> arduino_fis
```

## 3. アプリ連携（既存 HydroPaw アプリがそのまま使える）

- BLE は **Nordic UART Service** を使用（`config.h`）。フレームは**本家と同じHPP**（同じCRC16-CCITT）。
- アプリ側は `feature/arduino-fis-variant` ブランチで以下に設定済み：
  - `app/lib/core/constants/ble_constants.dart`（Flutter）
  - `webapp/src/providers/BleProvider.ts`（Web）
  - Service `6e400001-…` / TX(notify) `6e400003-…` / RX(write) `6e400002-…` / namePrefix `Fuwan`
- スマホでスキャン → `Fuwan-R4` に接続 → notify で EVT_DATA/RESULT/PHASE が流れる。

## 4. 信号処理（bap_lite）

`response r = R0/Rs`（清浄大気で≈1、H2上昇でRs減→r増）を BAP-lite が処理：
EMA平滑 → quiet窓で **R0学習/ドリフト補償** → onset/offset → 特徴量(peak/AUC/rise/duration) →
**Q(測定)×C(計測器) 減点採点**。しきい値は `config.h` の `BAP_*`（**PROVISIONAL: 実犬較正前**）。

EVT_DATA/RESULT の ppb系フィールドは **相対H2指標**（`(r−1)×1000`）。絶対ppm化は
感度曲線αでの較正後に対応。

## 5. ホスト検証（Arduino不要）

```
make -C arduino_fis/test
```
→ HPP CRC が CCITT-FALSE(本家互換)であること、合成呼気カーブで READY→ONSET→OFFSET と
Q/C/peak が出ることを確認できる。

## 6. 本家(電気化学式)との違い

| | 電気化学式(DGS2+STM32) | 半導体式(SB-19+R4) ←本変種 |
|---|---|---|
| 選択性 | H2高選択 | H2選択だがVOC/湿度の影響大 |
| インターフェース | UART(デジタルCSV) | アナログ電圧→ADC |
| 消費電力 | µA〜mA（コイン電池可） | ヒータ120mW常時（電池不向き） |
| 定量 | ppmに近い絶対値 | 相対指標(較正で改善) |
| 共通 | HPP/BLE・BAP思想・アプリUI | 同左（そのまま流用） |
