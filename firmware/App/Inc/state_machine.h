/**
 * @file  state_machine.h
 * @brief HydroPaw中核ステートマシン。HAL非依存(時刻は引数、I/Oは注入済み
 *        dgs2/ble_link経由)のためホストで結合テスト可能。
 *        遷移図は docs/04_stm32_spec.md 参照。
 */
#ifndef STATE_MACHINE_H
#define STATE_MACHINE_H

#include <stdint.h>
#include <stdbool.h>
#include "dgs2.h"
#include "ble_link.h"

typedef enum {
    SM_BOOT = 0,
    SM_SENSOR_INIT,
    SM_IDLE,
    SM_MEASURING,
    SM_SLEEP,
    SM_ERROR,
} sm_state_t;

typedef enum {
    SM_MODE_NONE = 0,
    SM_MODE_CONTINUOUS,
    SM_MODE_SINGLE,
} sm_mode_t;

/** 測定セッション統計 */
typedef struct {
    uint16_t n;
    int64_t  sum_ppb;
    int32_t  max_ppb;
    int32_t  min_ppb;
    uint32_t start_ms;
} sm_stats_t;

typedef struct {
    sm_state_t  state;
    sm_mode_t   mode;
    dgs2_t     *sensor;
    ble_link_t *link;
    uint16_t  (*read_battery_mv)(void);   /**< 注入: 電池電圧取得 */
    bool        sleep_requested;           /**< mainがSTOP2実行後にクリア */
    /* タイミング管理 (すべてms tick) */
    uint32_t    boot_ms;
    uint32_t    state_since_ms;
    uint32_t    last_ble_rx_ms;
    uint32_t    last_sensor_rx_ms;
    uint32_t    interval_s;
    uint8_t     retry_count;
    sm_stats_t  stats;
    char        sensor_sn[DGS2_SN_LEN + 1];
} sm_t;

void sm_init(sm_t *sm, dgs2_t *sensor, ble_link_t *link,
             uint16_t (*read_battery_mv)(void), uint32_t now_ms);

/** BLEから受信したHPPフレームを処理する。 */
void sm_on_frame(sm_t *sm, const hpp_frame_t *f, uint32_t now_ms);

/** DGS2から受信した1行(CR/LF除去済み)を処理する。 */
void sm_on_sensor_line(sm_t *sm, const char *line, uint32_t now_ms);

/** メインループから毎回呼ぶ。タイムアウト・自動遷移を処理する。 */
void sm_tick(sm_t *sm, uint32_t now_ms);

#endif /* STATE_MACHINE_H */
