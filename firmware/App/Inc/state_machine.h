/**
 * @file  state_machine.h
 * @brief HydroPaw中核ステートマシン。HAL非依存(時刻は引数、I/Oは注入済み
 *        dgs2/ble_link経由)のためホストで結合テスト可能。
 *        遷移図は docs/04_stm32_spec.md / docs/18 §3 参照。
 *
 * v2: 呼気セッション(BAP)の6状態を追加。
 *  - 既存のSTART_CONT/SINGLE(ラボモード: 生データ研究用)は完全互換で維持
 *  - CMD_BREATH(0x0A)で WARMUP→READY→BREATH→ANALYZE→VALIDATE→REPORT
 *    の呼気イベント測定を実行(製品モード)
 */
#ifndef STATE_MACHINE_H
#define STATE_MACHINE_H

#include <stdint.h>
#include <stdbool.h>
#include "dgs2.h"
#include "ble_link.h"
#include "bap.h"

typedef enum {
    SM_BOOT = 0,
    SM_SENSOR_INIT,
    SM_IDLE,
    SM_MEASURING,   /**< ラボモード(生値ストリーム) */
    SM_SLEEP,
    SM_ERROR,
    /* ---- v2: 呼気セッション (docs/18 §3) ---- */
    SM_WARMUP,      /**< センサ安定+ベースライン学習 */
    SM_READY,       /**< 呼気待ち(onset監視) */
    SM_BREATH,      /**< 呼気捕捉中 */
    SM_ANALYZE,     /**< 特徴量抽出(1tick) */
    SM_VALIDATE,    /**< 品質ゲート+自動再測定判定(1tick) */
    SM_REPORT,      /**< EVT_RESULT送信(ARQ投入, 1tick) */
} sm_state_t;

typedef enum {
    SM_MODE_NONE = 0,
    SM_MODE_CONTINUOUS,
    SM_MODE_SINGLE,
    SM_MODE_BREATH,  /**< v2: 呼気イベント測定 */
} sm_mode_t;

/** 測定セッション統計 (ラボモード用) */
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
    /* 連続モード実状態の確認・自己修復 (DGS2の'C'はトグルのため、
     * 期待状態と実受信の突き合わせで不一致を検出する) */
    uint32_t    stop_toggle_ms;   /**< 最後に停止トグルを送った時刻 */
    uint8_t     idle_line_count;  /**< IDLE中の予期しない測定行カウント */
    uint32_t    idle_first_line_ms;
    uint8_t     idle_stop_attempts;
    /* 低電池通知 (閾値を跨いだ時に一度だけEVT_ERROR(E_LOW_BATTERY)) */
    uint32_t    last_batt_check_ms;
    bool        low_batt_sent;
    /* ---- v2: 呼気セッション ---- */
    bap_t        bap;
    bap_result_t last_result;    /**< ANALYZEで確定した結果 */
    uint8_t      session_id;     /**< CMD_BREATHごとに+1 */
    uint32_t     session_start_ms;
    /* 計測器健全性の集計(bap_health_tへ供給) */
    uint16_t     ses_parse_errors;
    uint16_t     ses_samples;
    uint8_t      ses_stuck_events;
    uint8_t      ses_sensor_retries;
    bool         ses_temp_out;
    uint32_t     ses_crc_base;   /**< セッション開始時のdec.crc_errors */
} sm_t;

void sm_init(sm_t *sm, dgs2_t *sensor, ble_link_t *link,
             uint16_t (*read_battery_mv)(void), uint32_t now_ms);

/** BLEから受信したHPPフレームを処理する。 */
void sm_on_frame(sm_t *sm, const hpp_frame_t *f, uint32_t now_ms);

/** DGS2から受信した1行(CR/LF除去済み)を処理する。 */
void sm_on_sensor_line(sm_t *sm, const char *line, uint32_t now_ms);

/** メインループから毎回呼ぶ。タイムアウト・自動遷移・ARQ再送を処理する。 */
void sm_tick(sm_t *sm, uint32_t now_ms);

/** 呼気セッション中か(WARMUP..REPORT) */
bool sm_in_breath_session(const sm_t *sm);

#endif /* STATE_MACHINE_H */
