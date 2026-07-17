/**
 * @file state_machine.c
 * @brief 状態遷移・測定統計・HPPイベント生成。
 *        設計方針: すべての遷移は enter_state() 経由(入口処理を一元化)。
 */
#include <string.h>
#include "state_machine.h"
#include "app_config.h"

/* ---------- 内部ヘルパ ---------- */

static void enter_state(sm_t *sm, sm_state_t next, uint32_t now)
{
    sm->state = next;
    sm->state_since_ms = now;
    sm->retry_count = 0;
}

static void stats_reset(sm_t *sm, uint32_t now)
{
    memset(&sm->stats, 0, sizeof(sm->stats));
    sm->stats.min_ppb = INT32_MAX;
    sm->stats.start_ms = now;
}

static void stats_add(sm_t *sm, int32_t ppb)
{
    sm_stats_t *st = &sm->stats;
    if (st->n < 0xFFFFU) {
        st->n++;
        st->sum_ppb += ppb;
        if (ppb > st->max_ppb) st->max_ppb = ppb;
        if (ppb < st->min_ppb) st->min_ppb = ppb;
    }
}

static void send_data_evt(sm_t *sm, const dgs2_sample_t *s,
                          uint8_t flags, uint32_t now)
{
    uint8_t p[13];
    hpp_put_u32(&p[0], now - sm->stats.start_ms); /* セッション相対時刻 */
    hpp_put_i32(&p[4], s->h2_ppb);
    hpp_put_i16(&p[8], s->temp_c10);
    hpp_put_u16(&p[10], s->rh10);
    p[12] = flags;
    ble_link_send(sm->link, HPP_EVT_DATA, p, sizeof(p));
}

static void send_summary(sm_t *sm, uint32_t now)
{
    const sm_stats_t *st = &sm->stats;
    uint8_t p[16];
    int32_t avg = (st->n > 0U) ? (int32_t)(st->sum_ppb / st->n) : 0;
    int32_t mn  = (st->n > 0U) ? st->min_ppb : 0;
    hpp_put_u16(&p[0], st->n);
    hpp_put_i32(&p[2], avg);
    hpp_put_i32(&p[6], st->max_ppb);
    hpp_put_i32(&p[10], mn);
    hpp_put_u16(&p[14], (uint16_t)((now - st->start_ms) / 1000U));
    ble_link_send(sm->link, HPP_EVT_SUMMARY, p, sizeof(p));
}

static void send_status(sm_t *sm, uint32_t now)
{
    uint8_t p[8];
    p[0] = (uint8_t)sm->state;
    hpp_put_u16(&p[1], sm->read_battery_mv());
    p[3] = (sm->state != SM_ERROR) ? 1U : 0U;
    hpp_put_u32(&p[4], (now - sm->boot_ms) / 1000U);
    ble_link_send(sm->link, HPP_EVT_STATUS, p, sizeof(p));
}

static void send_info(sm_t *sm)
{
    uint8_t p[2 + DGS2_SN_LEN];
    p[0] = FW_VERSION_MAJOR;
    p[1] = FW_VERSION_MINOR;
    memcpy(&p[2], sm->sensor_sn, DGS2_SN_LEN);
    ble_link_send(sm->link, HPP_EVT_INFO, p, sizeof(p));
}

/** 測定を停止しIDLEへ戻す(サマリ送信含む)。 */
static void stop_measurement(sm_t *sm, uint32_t now, bool send_sum)
{
    if (sm->mode == SM_MODE_CONTINUOUS && sm->sensor->continuous) {
        dgs2_cmd_continuous_toggle(sm->sensor); /* 連続停止 */
    }
    if (send_sum) {
        send_summary(sm, now);
    }
    sm->mode = SM_MODE_NONE;
    enter_state(sm, SM_IDLE, now);
}

static void enter_sleep(sm_t *sm, uint32_t now)
{
    dgs2_cmd_sleep(sm->sensor);
    sm->sleep_requested = true; /* mainループがSTOP2を実行 */
    enter_state(sm, SM_SLEEP, now);
}

/* ---------- 公開API ---------- */

void sm_init(sm_t *sm, dgs2_t *sensor, ble_link_t *link,
             uint16_t (*read_battery_mv)(void), uint32_t now)
{
    memset(sm, 0, sizeof(*sm));
    sm->sensor = sensor;
    sm->link = link;
    sm->read_battery_mv = read_battery_mv;
    sm->boot_ms = now;
    sm->last_ble_rx_ms = now;
    sm->interval_s = 1;
    stats_reset(sm, now);
    enter_state(sm, SM_SENSOR_INIT, now);
    dgs2_cmd_single(sm->sensor); /* Wake + 応答確認(SNはこの応答から取得) */
}

void sm_on_frame(sm_t *sm, const hpp_frame_t *f, uint32_t now)
{
    sm->last_ble_rx_ms = now;

    /* SLEEP中はUART RXで既にWake済み。コマンド処理前にIDLEへ復帰 */
    if (sm->state == SM_SLEEP) {
        dgs2_cmd_single(sm->sensor); /* DGS2 Wake */
        enter_state(sm, SM_IDLE, now);
    }

    switch (f->type) {
    case HPP_CMD_START_CONT: {
        if (sm->state != SM_IDLE) {
            ble_link_send_nak(sm->link, f->type, E_BUSY);
            return;
        }
        uint32_t iv = (f->len >= 1U) ? f->payload[0] : 1U;
        if (iv < 1U || iv > 60U) {
            ble_link_send_nak(sm->link, f->type, E_INVALID_PARAM);
            return;
        }
        sm->interval_s = iv;
        stats_reset(sm, now);
        sm->mode = SM_MODE_CONTINUOUS;
        sm->last_sensor_rx_ms = now;
        if (!sm->sensor->continuous) {
            dgs2_cmd_continuous_toggle(sm->sensor);
        }
        enter_state(sm, SM_MEASURING, now);
        ble_link_send_ack(sm->link, f->type);
        break;
    }
    case HPP_CMD_STOP:
        if (sm->state != SM_MEASURING) {
            ble_link_send_nak(sm->link, f->type, E_BUSY);
            return;
        }
        ble_link_send_ack(sm->link, f->type);
        stop_measurement(sm, now, true);
        break;

    case HPP_CMD_SINGLE:
        if (sm->state != SM_IDLE) {
            ble_link_send_nak(sm->link, f->type, E_BUSY);
            return;
        }
        stats_reset(sm, now);
        sm->mode = SM_MODE_SINGLE;
        sm->last_sensor_rx_ms = now;
        dgs2_cmd_single(sm->sensor);
        enter_state(sm, SM_MEASURING, now);
        ble_link_send_ack(sm->link, f->type);
        break;

    case HPP_CMD_SLEEP:
        if (sm->state == SM_MEASURING) {
            stop_measurement(sm, now, true);
        }
        ble_link_send_ack(sm->link, f->type);
        enter_sleep(sm, now);
        break;

    case HPP_CMD_WAKE:
        /* SLEEPからは冒頭で復帰済み。ERRORからの復帰試行を担う */
        if (sm->state == SM_ERROR) {
            enter_state(sm, SM_SENSOR_INIT, now);
            dgs2_cmd_single(sm->sensor);
        }
        ble_link_send_ack(sm->link, f->type);
        break;

    case HPP_CMD_GET_STATUS:
        ble_link_send_ack(sm->link, f->type);
        send_status(sm, now);
        break;

    case HPP_CMD_GET_INFO:
        ble_link_send_ack(sm->link, f->type);
        send_info(sm);
        break;

    default:
        ble_link_send_nak(sm->link, f->type, E_INVALID_CMD);
        break;
    }
}

void sm_on_sensor_line(sm_t *sm, const char *line, uint32_t now)
{
    dgs2_sample_t s;
    if (dgs2_parse_line(line, &s) != APP_OK) {
        /* パース失敗: 連続測定中はリトライ計上のみ(次サンプルで回復) */
        if (sm->state == SM_MEASURING &&
            ++sm->retry_count > CFG_SENSOR_RETRY_MAX) {
            ble_link_send_error(sm->link, E_SENSOR_PARSE, 0);
            stop_measurement(sm, now, true);
        }
        return;
    }
    sm->retry_count = 0;
    sm->last_sensor_rx_ms = now;

    switch (sm->state) {
    case SM_SENSOR_INIT:
        /* 初回応答 = センサ生存確認 + SN取得 */
        memcpy(sm->sensor_sn, s.sn, sizeof(sm->sensor_sn));
        enter_state(sm, SM_IDLE, now);
        break;

    case SM_MEASURING: {
        uint8_t flags = dgs2_validate(sm->sensor, &s);
        if (now - sm->stats.start_ms < CFG_WARMUP_MS) {
            flags |= HPP_FLAG_WARMUP;
        }
        /* 異常フラグなしのサンプルのみ統計へ算入 */
        if ((flags & (HPP_FLAG_OUT_OF_RANGE | HPP_FLAG_STUCK)) == 0U) {
            stats_add(sm, s.h2_ppb);
        }
        send_data_evt(sm, &s, flags, now);
        if (sm->mode == SM_MODE_SINGLE) {
            stop_measurement(sm, now, false); /* 単発はサマリ不要 */
        }
        break;
    }
    default:
        break; /* IDLE等での自発出力は無視 */
    }
}

void sm_tick(sm_t *sm, uint32_t now)
{
    switch (sm->state) {
    case SM_SENSOR_INIT:
        if (now - sm->state_since_ms > CFG_SENSOR_BOOT_TIMEOUT_MS) {
            if (++sm->retry_count > CFG_SENSOR_RETRY_MAX) {
                ble_link_send_error(sm->link, E_SENSOR_TIMEOUT, 0);
                enter_state(sm, SM_ERROR, now);
            } else {
                sm->state_since_ms = now;
                dgs2_cmd_single(sm->sensor); /* リトライ */
            }
        }
        break;

    case SM_IDLE:
        if (now - sm->last_ble_rx_ms > CFG_IDLE_TO_SLEEP_MS &&
            now - sm->state_since_ms > CFG_IDLE_TO_SLEEP_MS) {
            enter_sleep(sm, now); /* 省電力: 無通信で自動Sleep */
        }
        break;

    case SM_MEASURING:
        /* センサ無応答 */
        if (now - sm->last_sensor_rx_ms > CFG_SENSOR_DATA_TIMEOUT_MS) {
            if (++sm->retry_count > CFG_SENSOR_RETRY_MAX) {
                ble_link_send_error(sm->link, E_SENSOR_TIMEOUT, 1);
                stop_measurement(sm, now, true);
                enter_state(sm, SM_ERROR, now);
            } else {
                sm->last_sensor_rx_ms = now;
                if (sm->mode == SM_MODE_CONTINUOUS && !sm->sensor->continuous) {
                    dgs2_cmd_continuous_toggle(sm->sensor);
                } else {
                    dgs2_cmd_single(sm->sensor);
                }
            }
        }
        /* BLE無通信(切断相当)60s → 安全停止 */
        if (now - sm->last_ble_rx_ms > CFG_BLE_INACTIVITY_MS) {
            stop_measurement(sm, now, true);
            enter_sleep(sm, now);
        }
        /* セッション上限 */
        if (now - sm->stats.start_ms > CFG_MEASURE_MAX_MS) {
            stop_measurement(sm, now, true);
        }
        break;

    default:
        break;
    }
}
