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

#endif /* APP_CONFIG_H */
