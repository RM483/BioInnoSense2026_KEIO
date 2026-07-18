/**
 * @file  app_config.h
 * @brief HydroPaw ファームウェア定数(タイムアウト・閾値)。
 */
#ifndef APP_CONFIG_H
#define APP_CONFIG_H

#define FW_VERSION_MAJOR        1U
#define FW_VERSION_MINOR        0U

/* タイミング [ms] */
#define CFG_SENSOR_BOOT_TIMEOUT_MS   2000U  /* 起動時応答待ち */
#define CFG_SENSOR_DATA_TIMEOUT_MS   3000U  /* 連続測定中の無受信許容 */
#define CFG_SENSOR_CONFIRM_MS        1500U  /* 連続開始後の初回データ確認窓 */
#define CFG_STOP_CONFIRM_MS          1800U  /* 連続停止後もデータが続く場合の再トグル猶予 */
#define CFG_SENSOR_RETRY_MAX         3U
#define CFG_IDLE_TO_SLEEP_MS         10000U /* IDLE→自動Sleep */
#define CFG_BLE_INACTIVITY_MS        60000U /* 測定中の無通信→自動停止 */
#define CFG_ERROR_TO_SLEEP_MS        60000U /* ERROR滞在の上限→省電力Sleepへ */
#define CFG_WARMUP_MS                60000U /* ウォームアップ扱い期間 */
#define CFG_MEASURE_MAX_MS           1800000U /* 連続測定の上限30分 */

/* 電池 [mV] (VBAT = ADC×2 分圧) */
#define CFG_BATT_LOW_MV              3300U  /* これ未満でE_LOW_BATTERY通知 */
#define CFG_BATT_RECOVER_MV          3400U  /* これ以上へ回復で再警告を許可 */
#define CFG_BATT_CHECK_MS            60000U /* 電池チェック周期 */

/* ==== BAP (Breath Analysis Pipeline) — docs/18 ====
 * 注意: CFG_BAP_* の閾値はすべて PROVISIONAL(仮値)。
 * 実犬ベンチ較正(docs/13)で確定するまで設計根拠はdocs/18 §2を参照。 */
#define CFG_BAP_ONSET_PPB            500U   /* 呼気開始: Δ閾値 [ppb] */
#define CFG_BAP_ONSET_N              3U     /* 呼気開始: 連続回数 [サンプル] */
#define CFG_BAP_OFFSET_PCT           40U    /* 呼気終了: ピーク比 [%] */
#define CFG_BAP_OFFSET_N             3U     /* 呼気終了: 連続回数 */
#define CFG_BAP_BREATH_MAX_S         90U    /* 捕捉窓上限 [s] (≤BAP_BUF_MAX) */
#define CFG_BAP_BREATH_MIN_S         10U    /* 有効呼気の最短 [s] */
#define CFG_BAP_READY_TIMEOUT_MS     120000U/* READYで呼気なし→中止 */
#define CFG_BAP_QUIET_PPB            300U   /* 静穏判定: 窓レンジ上限 [ppb] */
#define CFG_BAP_QUIET_RUN_N          5U     /* ベースラインロック: 静穏連続数 */
#define CFG_BAP_HAMPEL_K             3      /* Hampel: k×MAD */
#define CFG_BAP_HAMPEL_FLOOR_PPB     100    /* Hampel: 閾値下限 [ppb] */
#define CFG_BAP_FAST_PPB             300U   /* 適応EMA: 高速α切替閾値 [ppb] */
#define CFG_BAP_RETRY_QUALITY        60U    /* Q<この値で自動再測定(1回) */
#define CFG_BAP_RH_DELTA_MIN_10      30     /* 呼気裏付け: ΔRH最小 [0.1%RH] */
#define CFG_BAP_PRE_MAD_MAX_PPB      200U   /* 呼気前ノイズ許容MAD [ppb] */
#define CFG_BAP_BASELINE_MAX_PPB     5000U  /* 周囲大気として妥当な上限 */

/* ==== BLE 選択的ARQ (docs/18 §4) ==== */
#define CFG_ARQ_DEPTH                4U     /* 再送キュー深さ */
#define CFG_ARQ_TIMEOUT_MS           1000U  /* 再送間隔 */
#define CFG_ARQ_MAX_ATTEMPTS         5U     /* 断念までの送信回数 */

#endif /* APP_CONFIG_H */
