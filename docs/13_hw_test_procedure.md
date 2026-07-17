# ⑬ 実機テスト手順書 (STM32ファームウェア)

対象: Leafony AP03 (STM32L452RETxP) + DGS2 970-001(H2) + AC02 BLE Sugar。
結果は **docs/14_hw_test_results.md** に記録する。
ホストテスト(218アサーション)で担保済みのロジックは対象外 —
ここは**実機でしか確認できない項目**のみ。

> 原則: 実測で確認できるまで「未確認」を維持する。
> コード修正は実機で再現した問題に対してのみ行う。

## 0. 優先順位

| 優先 | テスト | 理由 |
|---|---|---|
| **P0(前提)** | T0 書込みとオプションバイト | 全テストの前提。初回リセット挙動の確認 |
| **P1(最優先)** | T1 実配線・分圧比 / T2 DGS2実ロットCSV / T3 AC02実UUID / T4 実測値伝送 | これが通らないと製品として成立しない |
| **P2(次点)** | T5 切断・再接続 / T6 STOP2移行・復帰 / T6b 復帰直後のUART欠損 / T8 低電池警告 | 日常運用の信頼性 |
| **P3(最後)** | T7 ソーク+WDT / T6c 消費電流 / T9 異常復旧 / T10 Release動作 | 提出・公開前の品質実証 |

## 1. サマリーマトリクス

| ID | 確認目的 | 合格条件(要約) |
|---|---|---|
| T0 | オプションバイト自動書換えと再起動 | 初回のみOPTBYTEリセット1回、以後ループなし |
| T1 | Leafony実配線・ADC分圧比 | 全信号導通一致、4.00V入力→ログ電圧±5% |
| T2 | DGS2実ロットのCSV形式 | `cols=7 parse=OK`、TEMP/RHが×100スケール |
| T3 | AC02実UUIDとHPP往復 | UUID確定・ACK<100ms・EVT_DATA受信 |
| T4 | 実測値の end-to-end 伝送 | 呼気でアプリのppmが実応答(ダミーでない) |
| T5 | BLE切断・自動再接続 | 60s以内復帰で測定継続 / 超過で自動Sleep |
| T6 | STOP2移行・復帰 | 8.2s超スリープでリセットせずコマンド復帰 |
| T6b | STOP2復帰直後のUART欠損量 | 欠損バイト数を実測、アプリ再送で吸収 |
| T6c | 消費電流 | STOP2でMCU 10µA台(記録) |
| T7 | 一晩ソーク+IWDG | 8h後に応答、意図ハングで8.2sリセット |
| T8 | 低電池警告の実動作 | 3.3V割れ≦60sで1回通知、測定は継続 |
| T9 | 異常時復旧(抜去・ノイズ) | E_SENSOR_TIMEOUT→WAKEで復帰、CRC統計のみ増加 |
| T10 | Release(ログ無効)動作 | 全機能動作・電流比較記録 |

## 2. 詳細手順

### T0 書込みとオプションバイト 【P0】

| 項目 | 内容 |
|---|---|
| 目的 | IWDG凍結オプションバイトの自動書換えが1回で完了し、リセットループしないこと |
| 機材 | ST-Link, LPUART1→USB-UART(115200), CubeIDE, CubeProgrammer |
| 事前条件 | Debugビルド書込み直後(工場出荷OB状態) |
| 手順 | ①書込み ②LPUART1ログ観察 ③CubeProgrammerでOB確認 ④電源再投入×3 |
| 期待ログ | 初回: `boot`→`reset cause: OPTBYTE`→2回目`boot`→`optbytes: IWDG FROZEN in stop`。以後の起動: `reset cause: PIN`のみ |
| 合格条件 | OPTBYTEリセットは初回の1回のみ。`IWDG FROZEN` 表示。以後ループなし |
| 不合格時に疑う箇所 | `power_option_bytes_ensure()`(power.c) / FLASH書込み保護 / 電源品質。FWは`IWDG RUNNING(!)`でもSTOP2を自動スキップして動作継続する(T6で確認) |

### T1 Leafony実配線・分圧比 【P1】

| 項目 | 内容 |
|---|---|
| 目的 | .ioc/main.hのピン割当が実基板と一致し、電池電圧が正しく読めること |
| 機材 | テスター, 可変電源, Leafony回路図 |
| 事前条件 | 電源OFFで導通確認→その後通電 |
| 手順 | ①PA9/PA10↔DGS2(クロス: DGS2 TXD→PA10) ②PA2/PA3↔AC02 ③PC1/PC0↔デバッグUART ④PA4↔分圧点 ⑤PB0↔LED ⑥PA8↔電源SW(実装時) ⑦電池端子に4.00Vを給電しアプリorログで電圧確認 |
| 期待ログ/データ | nRF ConnectでGET_STATUS→battery_mv≈4000。`BLE tx type=83` |
| 合格条件 | 全導通一致。battery_mv = 入力±5%(3800〜4200) |
| 不合格時に疑う箇所 | ピン不一致→HydroPaw.ioc/main.h修正。電圧ずれ→分圧比(power.cの`*2`係数)・VREF実測値 |

### T2 DGS2実ロットのCSV形式 【P1】

| 項目 | 内容 |
|---|---|
| 目的 | 実ロットの出力が7列・×100スケールのデータシート形式であること |
| 機材 | (A)DGS2単体+USB-UART(9600 8N1, Tera Term) と (B)AP03経由ログ |
| 事前条件 | DGS2に通電1分以上 |
| 手順 | (A)`\r`送信→生CSV目視 (B)AP03接続でLPUART1の`DGS2 rx`行を観察。既知温湿度環境(室温計併用)で値を突合 |
| 期待ログ | `DGS2 rx cols=7 parse=OK` が連続。`sensor init OK sn=XXXXXXXXXXXX`(12桁) |
| 合格条件 | cols=7・parse=OK・TEMP/RHが×100(例: 24.4℃→2440前後)・SN12桁 |
| 不合格時に疑う箇所 | cols≠7→ロット差(dgs2.cのDGS2_FIELD_COUNT要調整)。parse=FAIL連発→ボーレート/配線/ロット書式。SN不正→'e'ダンプで確認 |

### T3 AC02実UUIDとHPP生フレーム往復 【P1】

| 項目 | 内容 |
|---|---|
| 目的 | AC02の仮想UARTサービスUUID確定と、HPPコマンド往復の成立 |
| 機材 | nRF Connect(スマホ), LPUART1ログ |
| 事前条件 | T2合格(IDLE到達) |
| 手順 | ①nRF Connectでスキャン→接続→サービス一覧をスクリーンショット ②UUIDを記録し `app/lib/core/constants/ble_constants.dart` と `webapp/src/providers/BleProvider.ts` を更新 ③RX特性へWrite: START=`A5 01 01 00 01 01 53 CC` ④TX特性をNotify購読 ⑤STOP/GET_STATUS/ZERO/未定義0x30を送信 |
| 期待ログ/データ | ログ: `BLE tx type=40(ACK)`→`type=81(EVT_DATA) seq=…`(1Hz, SEQ連番)。nRF側: 13B Notify連続、STOPで16B(0x82)、STATUSは12B(0x83)、0x30にNAK(code=05) |
| 合格条件 | ACK≦100ms・EVT_DATA 1Hz・SEQ欠番なし(至近距離)・NAK動作 |
| 不合格時に疑う箇所 | Notify来ない→UUID取り違え/AC02のUART設定(115200 8N1)。ACKなし→PA2/PA3クロス。CRC不一致→バイト落ち(T6b参照) |

### T4 実測値のend-to-end伝送 【P1】

| 項目 | 内容 |
|---|---|
| 目的 | アプリ表示値がダミーでなくセンサ実測であることの実証 |
| 機材 | 実機アプリ(`flutter run`, dart-defineなし), H2源(呼気可) |
| 事前条件 | T3合格・UUID反映済みビルド |
| 手順 | ①アプリでスキャン→接続→測定開始 ②静置30秒→呼気を10秒あてる→離す ③LPUART1の`DGS2 rx`とアプリ表示を同時観察 |
| 期待データ | 呼気に追従してppmが上昇→減衰。ログのPPBとアプリ表示が一致(×1000換算) |
| 合格条件 | 応答が物理刺激と同期し、Mockの規則的波形と明確に異なる |
| 不合格時に疑う箇所 | 不変値→dgs2_validateのSTUCKフラグ確認/センサ寿命。値ずれ→スケール解釈(T2) |

### T5 BLE切断・自動再接続 【P2】

| 項目 | 内容 |
|---|---|
| 目的 | 切断60s以内の自動復帰と、超過時の安全停止 |
| 機材 | 実機アプリ, LPUART1ログ |
| 手順 | ①測定中にスマホBluetooth OFF ②(a)30秒でON (b)別試行で90秒放置 |
| 期待ログ | (a)アプリ「再接続中…」→復帰、FWは`BLE tx type=81`継続。(b)60秒で`state 3 -> 2`→`state 2 -> 4`→`enter STOP2` |
| 合格条件 | (a)測定画面が保持され続きから記録 (b)自動STOP+サマリ送出+Sleep |
| 不合格時に疑う箇所 | 復帰しない→アプリBleControllerバックオフ/AC02の再アド動作。60s停止せず→keep-alive誤送信の有無 |

### T6 STOP2移行・復帰 【P2】

| 項目 | 内容 |
|---|---|
| 目的 | 8.2秒を超えるスリープでリセットが起きず、BLEで復帰すること |
| 機材 | LPUART1ログ, ストップウォッチ |
| 事前条件 | T0で`IWDG FROZEN` |
| 手順 | ①IDLEで10秒放置→`enter STOP2` ②60秒待つ ③nRF/アプリからGET_STATUS送信 |
| 期待ログ | `wake from STOP2`。**`reset cause: IWDG`が出ないこと** |
| 合格条件 | 60秒スリープ後も無リセットで復帰・以後正常動作 |
| 不合格時に疑う箇所 | IWDGリセット→OB未凍結(T0)/`power_iwdg_frozen_in_stop`。復帰しない→USART2カーネルクロック(HSI)設定・AC02からのRX配線 |

### T6b STOP2復帰直後のUART欠損 【P2】【未確認項目】

| 項目 | 内容 |
|---|---|
| 目的 | 復帰トリガの最初のフレームが何バイト欠けるかの実測 |
| 機材 | nRF Connect, LPUART1ログ(可能ならPA3をロジアナ) |
| 手順 | ①STOP2中にGET_STATUSを1回だけWrite ②応答有無を記録 ③×10回繰り返し統計 ④アプリ実装(自動再送300ms×2)での成功率を確認 |
| 期待データ | 1フレーム目は無応答(Wake消費)が発生し得る→再送で100%成功 |
| 合格条件 | アプリ経由の操作が体感上失敗しない(再送で吸収) |
| 不合格時に疑う箇所 | 3回とも不達→Wake時間が長い(AC02/クロック起動)。必要なら「Wake専用ダミーバイト送信→50ms→本コマンド」をアプリに追加(実測後にのみ実装) |

### T8 低電池警告 【P2】

| 項目 | 内容 |
|---|---|
| 目的 | 3.3V割れで1回だけ警告、測定が中断しないこと |
| 機材 | 可変電源(電池端子へ), 実機アプリ |
| 手順 | ①4.0Vで測定開始 ②3.2Vへ降圧 ③最大60秒待つ ④3.5Vへ戻し→再度3.2Vへ |
| 期待ログ | `BLE tx EVT_ERROR code=07 detail=20`(3.2V→32)が各低下につき1回 |
| 合格条件 | 通知1回/低下・アプリは電池アイコン表示のみで測定継続・回復後の再低下で再通知 |
| 不合格時に疑う箇所 | 通知なし→T1の分圧比。連発→CFG_BATT_RECOVER_MVヒステリシス |

### T7 一晩ソーク+IWDG 【P3】

| 項目 | 内容 |
|---|---|
| 手順 | ①夕方にIDLE放置(Sleep遷移確認) ②翌朝接続し測定1回 ③別途、`sm_tick`手前に`while(1);`を一時挿入したビルドで8.2sリセットを確認(確認後、必ず削除) |
| 期待ログ | 朝: 正常応答・`reset cause:`に夜間分のIWDG/BORが**無い**こと。ハング試験: `reset cause: IWDG` |
| 合格条件 | 8h+で無リセット生存・ハング時は自動復旧 |
| 不合格時に疑う箇所 | 夜間IWDG→未知のブロッキング(直前ログで特定)。BOR→電源 |

### T6c 消費電流 【P3】

| 項目 | 内容 |
|---|---|
| 手順 | MCU電源ラインに電流計を挿入し、Run(測定中)/IDLE/STOP2/Release版STOP2 の4点を記録 |
| 合格条件 | STOP2でMCU 10µA台(基板全体はAC02/DGS2 Sleep込みで別記録) |
| 不合格時に疑う箇所 | mA残留→STOP2未突入(ログ確認)/未使用GPIO/デバッグ接続のまま計測 |

### T9 異常時復旧 【P3】

| 項目 | 内容 |
|---|---|
| 手順 | ①測定中にDGS2ケーブル抜去→3s×3リトライ→ERROR→アプリのエラー画面確認→再接続しCMD_WAKE→復帰(`r`送信) ②起動時未接続→ERROR→60sでSleep ③UART線に指ノイズ→動作継続を確認 |
| 期待ログ | `BLE tx EVT_ERROR code=01`、WAKE後`sensor init OK`。ノイズ時はEVT_STATUSのcrc_errors/resyncs増加のみ |
| 合格条件 | 全シナリオで最終的に正常動作へ復帰 |
| 不合格時に疑う箇所 | 復帰不能→DGS2 'r'後の応答時間(ログの間隔)/電源再投入の要否を記録 |

### T10 Release動作 【P3】

| 項目 | 内容 |
|---|---|
| 手順 | Release構成(`HYDROPAW_LOG_DISABLE`)で書込み→T3〜T5相当を再走 |
| 合格条件 | ログ無しで全機能動作(ログ依存の副作用がない)・電流をDebugと比較記録 |

## 3. 診断ログリファレンス (Debugビルドのみ)

LPUART1 115200bps。Releaseでは`HYDROPAW_LOG_DISABLE`により全て消える。

| ログ行 | 意味 |
|---|---|
| `HydroPaw FW v1.x boot` | 起動 |
| `reset cause: IWDG/OPTBYTE/SOFT/BOR/PIN` | 起動理由(IWDG=ウォッチドッグリセット検知) |
| `optbytes: IWDG FROZEN/RUNNING(!) in stop` | オプションバイト状態(RUNNINGは要対処) |
| `sensor init OK sn=…` / `sensor init FAILED` | センサ初期化の成否 |
| `DGS2 rx cols=N parse=OK/FAIL` | 受信CSVの列数とパース結果 |
| `BLE tx type=XX seq=N len=L` | 送信フレーム種別/連番(81=DATA,82=SUMMARY,83=STATUS,40=ACK,41=NAK) |
| `BLE tx EVT_ERROR code=XX detail=YY` | エラー通知(07=低電池, detail=0.1V単位) |
| `state A -> B` | 状態遷移(0:BOOT 1:INIT 2:IDLE 3:MEASURING 4:SLEEP 5:ERROR) |
| `enter STOP2` / `wake from STOP2` | 低消費電力の移行/復帰 |
| `STOP2 skipped: IWDG option bytes not frozen` | 安全フォールバック発動(T0不合格の兆候) |
