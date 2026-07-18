# HydroPaw Web — デバッグ用ダッシュボード

実機(DGS2 + Leafony)が届く前に、STM32がBLEで送るデータを受信したと
仮定してUI・データ表示を検証するためのローカルWebアプリ。

```
npm install
npm run dev        # http://localhost:5173 (Mockデータ, 1Hz)
```

## Provider構成

UIは `DataProvider` インターフェースのみに依存する。

| Provider | 用途 | 起動方法 |
|---|---|---|
| `MockProvider` | 開発(既定)。FWの挙動を模した1Hzデータを生成 | `npm run dev` |
| `BleProvider` | 実機。Web Bluetooth + HPP (Chrome系のみ) | `VITE_PROVIDER=ble npm run dev` |

切替は `src/providers/index.ts` の1箇所。`BleProvider` は
`docs/03_ble_spec.md` のHPPプロトコル(TS実装: `src/providers/hpp.ts`,
C/Dartと同一テストベクタ CRC=0x53CC)を実装済みで、実機到着後は
UUIDの実機確認のみで動く想定。

## 機能

- リアルタイム水素濃度 (ppm, 高値20ppm閾値で色分け)
- 温度・湿度・電池・デバイス状態
- 測定開始/停止 (停止時サマリはFW値、喪失時はローカル統計で代替)
- SVGチャート(依存ゼロ)・閾値ライン・ウォームアップ表示
- 履歴 (localStorageに最大50件)
- 犬プロフィール表示 / 接続状態表示
- ライト/ダーク自動 (prefers-color-scheme)

## 画面構成 (IA v2 — docs/21, Flutter版と同一)

- タブは **ホーム / 愛犬 / 設定** の3つだけ
- ホーム = 測定の入口(見守りリング/CTAから測定イベントへ)
- 日誌(測定+健康日誌)はホームの「履歴を見る」から (`#/history`)。カレンダーは右上で切替
- 「きょうの記録」で散歩/食欲/排便/薬/体調/メモを3タップ記録 (localStorage, 構造化+自由記述)
- 愛犬はカードを左右スワイプで多頭切替 (`hydropaw.dogs.v1`)

検証: `npx tsc` / `npx vitest run` / `npm run build`
