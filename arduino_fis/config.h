/**
 * @file  config.h
 * @brief HydroPaw 半導体式(FIS SB-19)+ Arduino Uno R4 WiFi 変種の設定。
 *
 * 中間発表「読み出し回路」スライドと SB1900J データシートに基づく。
 *   VC=5V — SB19(Rs) — VS節点 — RL — GND の分圧を、
 *   MCP6022 電圧フォロワ + RC(1k/1uF) 経由で R4 の 14bit ADC が読む。
 *   ヒータ VH=0.9V/130mA/120mW は LT3080 で常時生成(MCUは制御しない)。
 *
 * すべての可変値をここに集約する(較正時はこのファイルだけ触る)。
 */
#ifndef HP_FIS_CONFIG_H
#define HP_FIS_CONFIG_H

/* ---------- ピン割り当て (Uno R4 WiFi) ---------- */
#define PIN_VS_ADC        A0    /* センサ分圧出力 VS (電圧フォロワ後) */
#define PIN_VREF_ADC      A1    /* 任意: VC監視用の分圧(未使用可) */
#define PIN_HEATER_EN     -1    /* 任意: ヒータON/OFF用MOSFETゲート。-1=常時ON(未使用) */
#define PIN_STATUS_LED    LED_BUILTIN

/* ---------- ADC ---------- */
#define ADC_BITS          14              /* R4は最大14bit */
#define ADC_MAX           16383.0f        /* 2^14 - 1 */
/* ADC基準電圧 = 回路電圧 VC と同一(AVCC=5V)にすると VS/VC が比率になり、
 * 電源変動がキャンセルされる(ratiometric)。スライドの「電源の揺れを補正」に相当。 */
#define USE_RATIOMETRIC   1               /* 1: VC非依存でRs算出 */

/* ---------- 読み出し回路 定数 ---------- */
#define VC_VOLT           5.0f            /* 回路電圧 (SB1900J: VC<=5V) */
#define RL_OHM            10000.0f        /* 負荷抵抗 (標準10k, >200Ω) */
/* SB-19 Rs 妥当レンジ(健全性判定用): 100ppm H2で0.2〜2kΩ。
 * 清浄大気〜低濃度まで含めて広めに許容する。 */
#define RS_MIN_OHM        50.0f
#define RS_MAX_OHM        2000000.0f      /* 2MΩ(清浄大気で高抵抗側) */

/* ---------- サンプリング ---------- */
#define SAMPLE_PERIOD_MS  100U            /* 10Hz。RCフィルタ後の平滑値を取る */
#define BLE_STREAM_DIV    5U              /* EVT_DATAは 10Hz/5 = 2Hz で送信 */

/* ---------- BAP-lite しきい値 (PROVISIONAL: 実犬較正前) ----------
 * 信号は response r = R0/Rs (清浄大気で ~1.0、H2上昇でRs減→r増)。 */
#define BAP_WARMUP_MS         120000U     /* 予熱扱い。実運用はもっと長い(データシート予備通電48h) */
#define BAP_QUIET_RUN_N       8U          /* R0ロック: 静穏連続サンプル数 */
#define BAP_QUIET_BAND        0.03f       /* 静穏判定: 窓内 r レンジ上限 */
#define BAP_ONSET_R           1.15f       /* 呼気開始: r 閾値 */
#define BAP_ONSET_N           4U          /* 連続サンプル数(=0.4s @10Hz) */
#define BAP_OFFSET_PCT        40          /* 呼気終了: ピーク比[%] */
#define BAP_OFFSET_N          6U          /* 連続サンプル数(=0.6s) */
#define BAP_EMA_ALPHA_FAST    0.5f        /* 追従(大きな変化時) */
#define BAP_EMA_ALPHA_SLOW    0.125f      /* 安定(静穏時) */
#define BAP_FAST_DELTA_R      0.05f       /* この innovation で fast/slow 切替 */
#define BAP_BREATH_MAX_S      30U         /* 呼気捕捉窓上限[s] */
#define BAP_READY_TIMEOUT_MS  120000U     /* READYで呼気なし→中止 */
#define BAP_RETRY_QUALITY     60U         /* Q<この値で1回だけ自動再測定 */

/* ---------- BLE (Nordic UART Service 準拠) ----------
 * 既存HydroPawアプリはHPPフレームをnotifyで解釈する。
 * このUUIDに合わせてアプリ側 ble_constants(Flutter)/BleProvider(Web) を設定する。 */
#define BLE_LOCAL_NAME    "Fuwan-R4"
#define NUS_SERVICE_UUID  "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
#define NUS_RX_UUID       "6e400002-b5a3-f393-e0a9-e50e24dcca9e" /* App→FW Write */
#define NUS_TX_UUID       "6e400003-b5a3-f393-e0a9-e50e24dcca9e" /* FW→App Notify */

/* ---------- FWバージョン ---------- */
#define FW_VERSION_MAJOR  2
#define FW_VERSION_MINOR  0   /* v2.0-fis (半導体式変種) */

#endif /* HP_FIS_CONFIG_H */
