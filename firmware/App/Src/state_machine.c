/**
 * @file state_machine.c
 * @brief 状態遷移・測定統計・HPPイベント生成。
 *        設計方針: すべての遷移は enter_state() 経由(入口処理を一元化)。
 *
 * DGS2の連続測定コマンド 'C' はトグルであり状態問い合わせ手段がないため、
 * 「期待状態と実際のデータ受信の突き合わせ」で不一致を検出し自己修復する:
 *  - 開始後 CFG_SENSOR_CONFIRM_MS 以内にデータが無ければ再試行
 *    (1回目は無害な'\r'プローブ → 2回目以降で'C'再トグル)
 *  - IDLE中に測定行が流れ続ける場合(前回リセット等での取り残し)は
 *    停止トグルを再送して止める
 *
 * v2 (docs/18): 呼気セッション WARMUP→READY→BREATH→ANALYZE→VALIDATE→REPORT。
 *  - BLE切断中も呼気セッションは継続し、結果はARQキュー経由で後送する
 *    (切断=データ喪失、を排除)。ラボモードは従来通り安全停止。
 */
#include <string.h>
#include "state_machine.h"
#include "app_config.h"

/* ---------- 内部ヘルパ ---------- */

static void send_phase(sm_t *sm, uint8_t phase, uint8_t detail)
{
    uint8_t p[2] = { phase, detail };
    ble_link_send(sm->link, HPP_EVT_PHASE, p, 2);
}

static void enter_state(sm_t *sm, sm_state_t next, uint32_t now)
{
    sm->state = next;
    sm->state_since_ms = now;
    sm->retry_count = 0;
    if (next == SM_IDLE) {
        sm->idle_line_count = 0;
        sm->idle_stop_attempts = 0;
    }
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
    /* サマリは測定1回の成果 → 信頼配送 (docs/18 §4) */
    ble_link_send_reliable(sm->link, HPP_EVT_SUMMARY, p, sizeof(p), now);
}

static void send_status(sm_t *sm, uint32_t now)
{
    /* 14B: state, battery_mv, sensor_ok, uptime_s, crc_errors, resyncs,
     *      arq_drops(v1.2追加)。旧アプリは先頭8B/12Bのみ読む後方互換。 */
    uint8_t p[14];
    p[0] = (uint8_t)sm->state;
    hpp_put_u16(&p[1], sm->read_battery_mv());
    p[3] = (sm->state != SM_ERROR) ? 1U : 0U;
    hpp_put_u32(&p[4], (now - sm->boot_ms) / 1000U);
    hpp_put_u16(&p[8],  (uint16_t)(sm->link->dec.crc_errors & 0xFFFFU));
    hpp_put_u16(&p[10], (uint16_t)(sm->link->dec.resyncs & 0xFFFFU));
    hpp_put_u16(&p[12], (uint16_t)(sm->link->arq_drops & 0xFFFFU));
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

/** EVT_RESULT (30B, docs/18 §4) を組み立てARQで送る。 */
static void send_result(sm_t *sm, uint32_t now)
{
    const bap_result_t *r = &sm->last_result;
    uint8_t p[30];
    p[0] = r->session_id;
    p[1] = r->quality;
    p[2] = r->confidence;
    p[3] = r->flags;
    hpp_put_i32(&p[4],  r->baseline_ppb);
    hpp_put_i32(&p[8],  r->peak_ppb);
    hpp_put_i32(&p[12], r->plateau_ppb);
    hpp_put_u32(&p[16], r->auc_ppb_s);
    hpp_put_u16(&p[20], r->rise_ds);
    hpp_put_u16(&p[22], r->duration_ds);
    hpp_put_i16(&p[24], r->temp_c10_mean);
    hpp_put_i16(&p[26], r->rh10_delta);
    hpp_put_u16(&p[28], r->pre_mad_ppb);
    ble_link_send_reliable(sm->link, HPP_EVT_RESULT, p, sizeof(p), now);
}

bool sm_in_breath_session(const sm_t *sm)
{
    switch (sm->state) {
    case SM_WARMUP:
    case SM_READY:
    case SM_BREATH:
    case SM_ANALYZE:
    case SM_VALIDATE:
    case SM_REPORT:
        return true;
    default:
        return false;
    }
}

/** 測定を停止しIDLEへ戻す(サマリ送信含む)。呼気セッションにも安全。 */
static void stop_measurement(sm_t *sm, uint32_t now, bool send_sum)
{
    if (sm->mode == SM_MODE_CONTINUOUS || sm->mode == SM_MODE_BREATH) {
        dgs2_cmd_continuous_toggle(sm->sensor); /* 連続停止 */
        sm->stop_toggle_ms = now;
    }
    if (send_sum && sm->mode != SM_MODE_BREATH) {
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

/** 低電池の監視。閾値を下回ったら一度だけEVT_ERROR(E_LOW_BATTERY)を送る。
 *  測定は中断しない(アプリ側は警告表示のみ)。回復したら再警告を許可。 */
static void check_battery(sm_t *sm, uint32_t now)
{
    if (now - sm->last_batt_check_ms < CFG_BATT_CHECK_MS) {
        return;
    }
    sm->last_batt_check_ms = now;
    uint16_t mv = sm->read_battery_mv();
    if (mv == 0U) {
        return; /* ADC読み取り失敗は判定しない */
    }
    if (mv < CFG_BATT_LOW_MV && !sm->low_batt_sent) {
        /* detail = 電圧[0.1V単位] (例: 32 = 3.2V) */
        ble_link_send_error(sm->link, E_LOW_BATTERY, (uint8_t)(mv / 100U));
        sm->low_batt_sent = true;
        sm->bap.low_batt = true; /* 結果フレームにも反映 */
    } else if (mv >= CFG_BATT_RECOVER_MV) {
        sm->low_batt_sent = false;
    }
}

/** 呼気セッションの開始(CMD_BREATH)。 */
static void start_breath_session(sm_t *sm, uint32_t now)
{
    sm->session_id++;
    stats_reset(sm, now); /* EVT_DATAの相対時刻基準にも使う */
    sm->mode = SM_MODE_BREATH;
    sm->last_sensor_rx_ms = now;
    sm->session_start_ms = now;
    sm->ses_parse_errors = 0;
    sm->ses_samples = 0;
    sm->ses_stuck_events = 0;
    sm->ses_sensor_retries = 0;
    sm->ses_temp_out = false;
    sm->ses_crc_base = sm->link->dec.crc_errors;
    /* ウォームアップはセンサ通電(=ブート)からの経過で判定。
     * DGS2のSleepはバイアス維持のため再ウォームアップ不要(データシート) */
    bool warm = (now - sm->boot_ms) >= CFG_WARMUP_MS;
    bap_init(&sm->bap, sm->session_id, warm);
    /* セッション開始前から低電池なら結果フラグへ引き継ぐ
     * (check_batteryは跨ぎ検出のため再通知されない — レビューF2) */
    sm->bap.low_batt = sm->low_batt_sent;
    dgs2_cmd_continuous_toggle(sm->sensor);
    enter_state(sm, SM_WARMUP, now);
    send_phase(sm, HPP_PHASE_WARMUP, 0);
}

/** 呼気セッションの中止(エラー/コマンド)。partialは破棄する。 */
static void abort_breath_session(sm_t *sm, uint32_t now, uint8_t err_code)
{
    if (err_code != APP_OK) {
        uint8_t p[2] = { err_code, 0 };
        /* 中止理由も測定1回ぶんの情報 → 信頼配送 */
        ble_link_send_reliable(sm->link, HPP_EVT_ERROR, p, 2, now);
        send_phase(sm, HPP_PHASE_ABORTED, err_code);
    }
    stop_measurement(sm, now, false);
}

/** 呼気状態群の健全性集計をbap_health_tへ写す。 */
static void fill_health(const sm_t *sm, bap_health_t *h)
{
    h->parse_errors   = sm->ses_parse_errors;
    h->samples_total  = sm->ses_samples;
    h->stuck_events   = sm->ses_stuck_events;
    h->sensor_retries = sm->ses_sensor_retries;
    h->temp_out_of_comp = sm->ses_temp_out;
    uint32_t crc = sm->link->dec.crc_errors - sm->ses_crc_base;
    h->crc_errors = (crc > 0xFFFFU) ? 0xFFFFU : (uint16_t)crc;
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
    sm->last_batt_check_ms = now;
    sm->interval_s = 1;
    stats_reset(sm, now);
    enter_state(sm, SM_SENSOR_INIT, now);
    /* 前回動作でSleepのまま残っている可能性があるためWakeバイトを先行送信。
     * (Sleep中の最初の1バイトはWake専用に消費される — データシート仕様) */
    dgs2_cmd_wake(sm->sensor);
    dgs2_cmd_single(sm->sensor); /* 応答確認 + SN取得 */
}

void sm_on_frame(sm_t *sm, const hpp_frame_t *f, uint32_t now)
{
    sm->last_ble_rx_ms = now;

    /* SLEEP中はUART RXで既にMCUはWake済み。DGS2をWakeしてIDLEへ復帰 */
    if (sm->state == SM_SLEEP) {
        dgs2_cmd_wake(sm->sensor);
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
        dgs2_cmd_continuous_toggle(sm->sensor);
        enter_state(sm, SM_MEASURING, now);
        ble_link_send_ack(sm->link, f->type);
        break;
    }
    case HPP_CMD_STOP:
        if (sm->state == SM_MEASURING) {
            ble_link_send_ack(sm->link, f->type);
            stop_measurement(sm, now, true);
        } else if (sm_in_breath_session(sm)) {
            /* 呼気セッションはどの状態からも安全に中止できる */
            ble_link_send_ack(sm->link, f->type);
            abort_breath_session(sm, now, APP_OK);
        } else {
            ble_link_send_nak(sm->link, f->type, E_BUSY);
        }
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

    case HPP_CMD_BREATH:
        /* v2: 呼気イベント測定 (docs/18)。IDLEからのみ */
        if (sm->state != SM_IDLE) {
            ble_link_send_nak(sm->link, f->type, E_BUSY);
            return;
        }
        ble_link_send_ack(sm->link, f->type);
        start_breath_session(sm, now);
        break;

    case HPP_CMD_ACK_EVT:
        /* 信頼配送イベントの受領通知。応答は返さない(ACK連鎖を防ぐ) */
        if (f->len >= 1U) {
            ble_link_on_ack_evt(sm->link, f->payload[0]);
        }
        break;

    case HPP_CMD_SLEEP:
        if (sm->state == SM_MEASURING) {
            stop_measurement(sm, now, true);
        } else if (sm_in_breath_session(sm)) {
            abort_breath_session(sm, now, APP_OK);
        }
        ble_link_send_ack(sm->link, f->type);
        enter_sleep(sm, now);
        break;

    case HPP_CMD_WAKE:
        /* SLEEPからは冒頭で復帰済み。ERRORからの復帰試行を担う */
        if (sm->state == SM_ERROR) {
            enter_state(sm, SM_SENSOR_INIT, now);
            dgs2_cmd_reset(sm->sensor); /* 'r': モジュールリセットで復旧試行 */
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

    case HPP_CMD_ZERO:
        /* ゼロ校正はクリーンエア・非測定中のみ許可 */
        if (sm->state != SM_IDLE) {
            ble_link_send_nak(sm->link, f->type, E_BUSY);
            return;
        }
        dgs2_cmd_zero(sm->sensor);
        ble_link_send_ack(sm->link, f->type);
        break;

    default:
        ble_link_send_nak(sm->link, f->type, E_INVALID_CMD);
        break;
    }
}

/** IDLE中に測定行が流れ続ける場合、連続モードの取り残しとして停止させる。 */
static void heal_unexpected_stream(sm_t *sm, uint32_t now)
{
    /* 停止トグル直後の1〜2行は残余として無視する */
    if (now - sm->stop_toggle_ms < CFG_STOP_CONFIRM_MS) {
        return;
    }
    if (sm->idle_line_count == 0U) {
        sm->idle_first_line_ms = now;
    }
    sm->idle_line_count++;
    /* 3秒以内に2行以上 → 連続モードが生きていると判断 */
    if (sm->idle_line_count >= 2U &&
        now - sm->idle_first_line_ms <= 3000U &&
        sm->idle_stop_attempts < CFG_SENSOR_RETRY_MAX) {
        dgs2_cmd_continuous_toggle(sm->sensor);
        sm->stop_toggle_ms = now;
        sm->idle_stop_attempts++;
        sm->idle_line_count = 0;
    } else if (now - sm->idle_first_line_ms > 3000U) {
        sm->idle_line_count = 1;
        sm->idle_first_line_ms = now;
    }
}

/** 呼気セッション中のサンプル処理(WARMUP/READY/BREATH)。 */
static void breath_on_sample(sm_t *sm, const dgs2_sample_t *s,
                             uint8_t flags, uint32_t now)
{
    if (sm->ses_samples < 0xFFFFU) sm->ses_samples++;
    if ((flags & HPP_FLAG_STUCK) != 0U && sm->ses_stuck_events < 0xFFU) {
        sm->ses_stuck_events++;
    }
    if (s->temp_c10 < DGS2_TEMP_MIN_C10 || s->temp_c10 > DGS2_TEMP_MAX_C10) {
        sm->ses_temp_out = true;
    }
    /* レンジ外・固着サンプルはパイプラインに入れない(既存方針と同じ) */
    if ((flags & (HPP_FLAG_OUT_OF_RANGE | HPP_FLAG_STUCK)) != 0U) {
        return;
    }

    bap_evt_t ev = bap_on_sample(&sm->bap, s->h2_ppb, s->temp_c10,
                                 s->rh10, now);
    switch (ev) {
    case BAP_EVT_BASELINE_LOCKED:
        /* READY昇格はウォームアップ時間との論理積 — sm_tick()で判断 */
        break;
    case BAP_EVT_ONSET:
        if (sm->state == SM_READY) {
            enter_state(sm, SM_BREATH, now);
            send_phase(sm, HPP_PHASE_BREATH, 0);
        }
        break;
    case BAP_EVT_OFFSET:
        if (sm->state == SM_BREATH) {
            enter_state(sm, SM_ANALYZE, now);
            send_phase(sm, HPP_PHASE_ANALYZE, 0);
        }
        break;
    default:
        break;
    }
}

void sm_on_sensor_line(sm_t *sm, const char *line, uint32_t now)
{
    dgs2_sample_t s;
    if (dgs2_parse_line(line, &s) != APP_OK) {
        if (sm_in_breath_session(sm)) {
            if (sm->ses_parse_errors < 0xFFFFU) sm->ses_parse_errors++;
            return; /* 次サンプルで回復。頻発は信頼度Cに反映される */
        }
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

    case SM_WARMUP:
    case SM_READY:
    case SM_BREATH: {
        uint8_t flags = dgs2_validate(sm->sensor, &s);
        if (!sm->bap.warmup_done) {
            flags |= HPP_FLAG_WARMUP;
        }
        /* ライブビュー用ストリームは呼気モードでも流す(ベストエフォート) */
        send_data_evt(sm, &s, flags, now);
        breath_on_sample(sm, &s, flags, now);
        break;
    }

    case SM_IDLE:
        heal_unexpected_stream(sm, now);
        break;

    default:
        break; /* SLEEP/ERROR/ANALYZE/VALIDATE/REPORT中の自発出力は無視 */
    }
}

/** 呼気状態群のセンサ無応答処理(MEASURINGと同じ自己修復方針)。 */
static void breath_sensor_watchdog(sm_t *sm, uint32_t now)
{
    uint32_t timeout = (sm->ses_samples == 0U) ? CFG_SENSOR_CONFIRM_MS
                                               : CFG_SENSOR_DATA_TIMEOUT_MS;
    if (now - sm->last_sensor_rx_ms <= timeout) {
        return;
    }
    if (++sm->retry_count > CFG_SENSOR_RETRY_MAX) {
        abort_breath_session(sm, now, E_SENSOR_TIMEOUT);
        enter_state(sm, SM_ERROR, now);
        return;
    }
    if (sm->ses_sensor_retries < 0xFFU) sm->ses_sensor_retries++;
    sm->last_sensor_rx_ms = now;
    if (sm->retry_count == 1U) {
        dgs2_cmd_wake(sm->sensor);
        dgs2_cmd_single(sm->sensor); /* 無害プローブ */
    } else {
        dgs2_cmd_continuous_toggle(sm->sensor); /* トグル不発対策 */
    }
}

void sm_tick(sm_t *sm, uint32_t now)
{
    /* ARQ再送はどの状態でも進める(切断中の送信もUART層は受け付ける) */
    ble_link_tick(sm->link, now);

    switch (sm->state) {
    case SM_SENSOR_INIT:
        if (now - sm->state_since_ms > CFG_SENSOR_BOOT_TIMEOUT_MS) {
            if (++sm->retry_count > CFG_SENSOR_RETRY_MAX) {
                ble_link_send_error(sm->link, E_SENSOR_TIMEOUT, 0);
                enter_state(sm, SM_ERROR, now);
            } else {
                sm->state_since_ms = now;
                dgs2_cmd_wake(sm->sensor);
                dgs2_cmd_single(sm->sensor); /* リトライ */
            }
        }
        break;

    case SM_IDLE:
        check_battery(sm, now);
        if (now - sm->last_ble_rx_ms > CFG_IDLE_TO_SLEEP_MS &&
            now - sm->state_since_ms > CFG_IDLE_TO_SLEEP_MS) {
            enter_sleep(sm, now); /* 省電力: 無通信で自動Sleep */
        }
        break;

    case SM_MEASURING: {
        check_battery(sm, now);
        /* センサ無応答。開始直後は短い確認窓(CFG_SENSOR_CONFIRM_MS)で
         * トグル不発を早期検出する。 */
        uint32_t timeout = (sm->stats.n == 0U && sm->mode == SM_MODE_CONTINUOUS)
                               ? CFG_SENSOR_CONFIRM_MS
                               : CFG_SENSOR_DATA_TIMEOUT_MS;
        if (now - sm->last_sensor_rx_ms > timeout) {
            if (++sm->retry_count > CFG_SENSOR_RETRY_MAX) {
                ble_link_send_error(sm->link, E_SENSOR_TIMEOUT, 1);
                stop_measurement(sm, now, true);
                enter_state(sm, SM_ERROR, now);
            } else {
                sm->last_sensor_rx_ms = now;
                if (sm->mode == SM_MODE_CONTINUOUS) {
                    /* 1回目: 無害な'\r'プローブ(Sleep解除も兼ねる)。
                     * 2回目以降: 'C'再トグル(トグル不発/desync対策)。 */
                    if (sm->retry_count == 1U) {
                        dgs2_cmd_wake(sm->sensor);
                        dgs2_cmd_single(sm->sensor);
                    } else {
                        dgs2_cmd_continuous_toggle(sm->sensor);
                    }
                } else {
                    dgs2_cmd_wake(sm->sensor);
                    dgs2_cmd_single(sm->sensor);
                }
            }
        }
        /* BLE無通信(切断相当)60s → 安全停止 (ラボモードのみ。
         * 呼気モードは切断中も継続しARQで後送する — docs/18 §3) */
        if (now - sm->last_ble_rx_ms > CFG_BLE_INACTIVITY_MS) {
            stop_measurement(sm, now, true);
            enter_sleep(sm, now);
        }
        /* セッション上限 */
        if (sm->state == SM_MEASURING &&
            now - sm->stats.start_ms > CFG_MEASURE_MAX_MS) {
            stop_measurement(sm, now, true);
        }
        break;
    }

    /* ---- v2: 呼気セッション ---- */
    case SM_WARMUP:
        check_battery(sm, now);
        breath_sensor_watchdog(sm, now);
        /* READY昇格 = ベースラインロック ∧ ウォームアップ時間経過 */
        if (sm->state == SM_WARMUP && sm->bap.baseline_locked &&
            (now - sm->boot_ms) >= CFG_WARMUP_MS) {
            sm->bap.warmup_done = true;
            sm->bap.phase = BAP_PHASE_READY;
            enter_state(sm, SM_READY, now);
            send_phase(sm, HPP_PHASE_READY, 0);
        }
        /* ウォームアップ+ベースラインが上限内に完了しない → 中止 */
        if (sm->state == SM_WARMUP &&
            now - sm->state_since_ms > CFG_BAP_READY_TIMEOUT_MS) {
            abort_breath_session(sm, now, E_SENSOR_TIMEOUT);
        }
        break;

    case SM_READY:
        check_battery(sm, now);
        breath_sensor_watchdog(sm, now);
        if (sm->state == SM_READY &&
            now - sm->state_since_ms > CFG_BAP_READY_TIMEOUT_MS) {
            /* 呼気が来ない: 電池を守るため中止(理由つき) */
            abort_breath_session(sm, now, E_NO_BREATH);
        }
        break;

    case SM_BREATH:
        check_battery(sm, now);
        breath_sensor_watchdog(sm, now);
        /* セッション全体の上限(安全弁): 打ち切って解析へ */
        if (sm->state == SM_BREATH &&
            now - sm->session_start_ms > CFG_MEASURE_MAX_MS) {
            sm->bap.truncated = true;
            sm->bap.phase = BAP_PHASE_DONE;
            sm->bap.offset_ms = now;
            enter_state(sm, SM_ANALYZE, now);
            send_phase(sm, HPP_PHASE_ANALYZE, 0);
        }
        break;

    case SM_ANALYZE: {
        /* 特徴量抽出+採点(1tick, docs/18 §S5-S7) */
        bap_health_t h;
        fill_health(sm, &h);
        bap_finalize(&sm->bap, &h, &sm->last_result);
        enter_state(sm, SM_VALIDATE, now);
        break;
    }

    case SM_VALIDATE:
        /* 品質ゲート: 低品質なら1回だけ自動再測定 (docs/18 §S8) */
        if (sm->last_result.quality < CFG_BAP_RETRY_QUALITY &&
            sm->bap.retries == 0U &&
            now - sm->session_start_ms < CFG_MEASURE_MAX_MS / 2U) {
            bap_begin_retry(&sm->bap, now);
            enter_state(sm, SM_READY, now);
            send_phase(sm, HPP_PHASE_RETRY, sm->last_result.quality);
        } else {
            enter_state(sm, SM_REPORT, now);
        }
        break;

    case SM_REPORT:
        /* 結果送信(ARQ投入)→センサ停止→IDLE。配送はARQ層が継続する */
        send_result(sm, now);
        send_phase(sm, HPP_PHASE_DONE, sm->last_result.quality);
        stop_measurement(sm, now, false);
        break;

    case SM_ERROR:
        /* ERRORのまま放置で電池を消耗しない: 一定時間後にSleepへ。
         * BLE経由のCMD_WAKEでいつでも復帰試行できる。 */
        if (now - sm->state_since_ms > CFG_ERROR_TO_SLEEP_MS) {
            enter_sleep(sm, now);
        }
        break;

    default:
        break;
    }
}
