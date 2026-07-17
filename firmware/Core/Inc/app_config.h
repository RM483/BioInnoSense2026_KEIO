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
#define CFG_SENSOR_RETRY_MAX         3U
#define CFG_IDLE_TO_SLEEP_MS         10000U /* IDLE→自動Sleep */
#define CFG_BLE_INACTIVITY_MS        60000U /* 測定中の無通信→自動停止 */
#define CFG_WARMUP_MS                60000U /* ウォームアップ扱い期間 */
#define CFG_MEASURE_MAX_MS           1800000U /* 連続測定の上限30分 */

/* 電池 [mV] (VBAT = ADC×2 分圧) */
#define CFG_BATT_LOW_MV              3300U

#endif /* APP_CONFIG_H */
