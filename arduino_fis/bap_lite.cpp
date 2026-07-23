/**
 * @file bap_lite.cpp
 * @brief bap_lite 実装。閾値は config.h の BAP_* (PROVISIONAL — 実犬較正前)。
 */
#include <math.h>
#include <string.h>
#include "bap_lite.h"
#include "config.h"

static float win_range_over_mean(const bapl_t *b) {
    if (b->win_n == 0u) return 1e9f;
    float mn = b->win[0], mx = b->win[0], sum = 0.0f;
    for (uint8_t i = 0; i < b->win_n; i++) {
        float v = b->win[i];
        if (v < mn) mn = v;
        if (v > mx) mx = v;
        sum += v;
    }
    float mean = sum / (float)b->win_n;
    if (mean <= 0.0001f) mean = 0.0001f;
    return (mx - mn) / mean;
}

void bapl_init(bapl_t *b, uint8_t session_id, uint32_t now_ms, bool already_warm) {
    memset(b, 0, sizeof(*b));
    b->phase = BAPL_WARMING;
    b->session_id = session_id;
    b->already_warm = already_warm;
    b->start_ms = now_ms;
    b->last_ms = now_ms;
    b->peak_r = 1.0f;
    b->rs_min = 1e12f;
}

/** 低品質による自動再測定: 捕捉のみリセット。EMA/ベースラインは維持。 */
void bapl_begin_retry(bapl_t *b, uint32_t now_ms) {
    b->phase = BAPL_READY;
    b->retries++;
    b->onset_run = b->offset_run = 0;
    b->onset_ms = b->offset_ms = b->peak_ms = 0;
    b->peak_r = 1.0f;
    b->rs_min = 1e12f;
    b->auc = 0.0;
    b->breath_samples = 0;
    b->truncated = false;
    b->last_ms = now_ms;
}

float bapl_baseline_rs(const bapl_t *b) { return b->r0_locked ? b->r0 : b->y_rs; }

float bapl_response(const bapl_t *b) {
    float base = bapl_baseline_rs(b);
    if (b->y_rs <= 0.1f) return 1.0f;
    float r = base / b->y_rs;
    return (r < 0.0f) ? 0.0f : r;
}

bapl_evt_t bapl_on_sample(bapl_t *b, float rs_ohm, bool valid, uint32_t now_ms) {
    if (b->samples_total < 0xFFFFu) b->samples_total++;
    if (!valid) {
        if (b->invalid_samples < 0xFFFFu) b->invalid_samples++;
        return BAPL_EVT_NONE; /* レンジ外は捨てる(次サンプルで回復) */
    }

    /* --- EMA平滑 (innovation-gated): 相対変化が大きい時は速く追従 --- */
    if (!b->y_init) {
        b->y_rs = rs_ohm;
        b->y_init = true;
    } else {
        float rel = fabsf(rs_ohm - b->y_rs) / (b->y_rs > 1.0f ? b->y_rs : 1.0f);
        float a = (rel > BAP_FAST_DELTA_R) ? BAP_EMA_ALPHA_FAST : BAP_EMA_ALPHA_SLOW;
        b->y_rs += a * (rs_ohm - b->y_rs);
    }

    float r = bapl_response(b);

    /* 直近 r 窓を更新(静穏判定用) */
    b->win[b->win_i] = r;
    b->win_i = (uint8_t)((b->win_i + 1u) % 8u);
    if (b->win_n < 8u) b->win_n++;

    float dt = (float)(now_ms - b->last_ms) / 1000.0f;
    if (dt < 0.0f || dt > 5.0f) dt = (float)SAMPLE_PERIOD_MS / 1000.0f;
    b->last_ms = now_ms;

    bool quiet = (win_range_over_mean(b) <= BAP_QUIET_BAND);
    bool warm  = b->already_warm || (now_ms - b->start_ms >= BAP_WARMUP_MS);

    /* --- ベースライン R0 学習 / ドリフト補償 --- */
    if (!b->r0_locked) {
        if (quiet) {
            if (b->quiet_run < 0xFFu) b->quiet_run++;
        } else {
            b->quiet_run = 0;
        }
        if (b->quiet_run >= BAP_QUIET_RUN_N) {
            b->r0 = b->y_rs;      /* 清浄大気 Rs を確定 */
            b->r0_locked = true;
        }
    } else if (quiet && fabsf(r - 1.0f) < (BAP_ONSET_R - 1.0f) * 0.5f) {
        /* 静穏かつ呼気でない時だけ、ゆっくりドリフト補償 */
        b->r0 += 0.02f * (b->y_rs - b->r0);
    }

    /* --- フェーズ遷移 --- */
    switch (b->phase) {
    case BAPL_WARMING:
        if (b->r0_locked && warm) {
            b->phase = BAPL_READY;
            return BAPL_EVT_READY;
        }
        return b->r0_locked ? BAPL_EVT_R0_LOCKED : BAPL_EVT_NONE;

    case BAPL_READY:
        if (r >= BAP_ONSET_R) {
            if (++b->onset_run >= BAP_ONSET_N) {
                b->onset_ms = now_ms;
                b->peak_ms = now_ms;
                b->peak_r = r;
                b->rs_min = b->y_rs;
                b->auc = 0.0;
                b->breath_samples = 0;
                b->onset_run = 0;
                b->phase = BAPL_BREATH;
                return BAPL_EVT_ONSET;
            }
        } else {
            b->onset_run = 0;
        }
        return BAPL_EVT_NONE;

    case BAPL_BREATH: {
        if (b->breath_samples < 0xFFFFu) b->breath_samples++;
        if (r > b->peak_r) { b->peak_r = r; b->peak_ms = now_ms; }
        if (b->y_rs < b->rs_min) b->rs_min = b->y_rs;
        if (r > 1.0f) b->auc += (double)(r - 1.0f) * (double)dt;

        float off_th = 1.0f + (b->peak_r - 1.0f) * (float)BAP_OFFSET_PCT / 100.0f;
        bool max_len = (now_ms - b->onset_ms) >= (uint32_t)BAP_BREATH_MAX_S * 1000u;
        if (r < off_th) {
            if (++b->offset_run >= BAP_OFFSET_N || max_len) {
                b->offset_ms = now_ms;
                if (max_len) b->truncated = true;
                b->phase = BAPL_DONE;
                return BAPL_EVT_OFFSET;
            }
        } else {
            b->offset_run = 0;
            if (max_len) {
                b->offset_ms = now_ms;
                b->truncated = true;
                b->phase = BAPL_DONE;
                return BAPL_EVT_OFFSET;
            }
        }
        return BAPL_EVT_NONE;
    }
    default:
        return BAPL_EVT_NONE;
    }
}

static uint8_t clamp_u8(int v) { return (uint8_t)(v < 0 ? 0 : (v > 100 ? 100 : v)); }

void bapl_finalize(const bapl_t *b, bapl_result_t *out) {
    memset(out, 0, sizeof(*out));
    out->session_id = b->session_id;
    out->r0_ohm     = b->r0;
    out->peak_r     = b->peak_r;
    out->rs_min_ohm = (b->rs_min < 1e11f) ? b->rs_min : 0.0f;
    out->auc        = (float)b->auc;

    uint32_t dur_ms  = (b->offset_ms > b->onset_ms) ? (b->offset_ms - b->onset_ms) : 0;
    uint32_t rise_ms = (b->peak_ms  > b->onset_ms) ? (b->peak_ms  - b->onset_ms) : 0;
    out->duration_ds = (uint16_t)(dur_ms / 100u);
    out->rise_ds     = (uint16_t)(rise_ms / 100u);

    /* --- 品質 Q: この測定はうまくいったか --- */
    int q = 100;
    if (out->duration_ds < 10u) q -= 40;             /* 呼気<1s: 短すぎ */
    if (!(b->already_warm || (b->last_ms - b->start_ms >= BAP_WARMUP_MS))) q -= 20;
    if (b->peak_r < BAP_ONSET_R + 0.10f) q -= 20;     /* ピークが弱い */
    if (b->truncated) q -= 10;
    out->quality = clamp_u8(q);

    /* --- 信頼度 C: この計測器は健全か --- */
    int c = 100;
    if (b->samples_total > 0u) {
        int bad = (int)(100u * b->invalid_samples / b->samples_total);
        c -= bad; /* レンジ外サンプル率をそのまま減点 */
    }
    if (b->r0 < RS_MIN_OHM * 2.0f || b->r0 > RS_MAX_OHM * 0.5f) c -= 20; /* 清浄大気Rsが異常 */
    out->confidence = clamp_u8(c);

    /* --- flags --- */
    out->flags = 0;
    if (b->already_warm || (b->last_ms - b->start_ms >= BAP_WARMUP_MS)) out->flags |= BAPL_RF_WARMUP_OK;
    if (b->truncated) out->flags |= BAPL_RF_TRUNCATED;
    if (out->quality < BAP_RETRY_QUALITY) out->flags |= BAPL_RF_REMEASURE;
}
