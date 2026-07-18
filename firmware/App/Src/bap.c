/**
 * @file bap.c
 * @brief Breath Analysis Pipeline 実装。設計根拠: docs/18_algorithm_design.md
 *
 * 実装原則:
 *  - 全整数演算(Q8固定小数)。float/FPU不使用 — ホストと実機でビット一致。
 *  - malloc不使用。最悪計算量はサンプル毎 O(w²)=O(25)。
 *  - 閾値はすべて app_config.h の CFG_BAP_*(PROVISIONAL — 実犬較正前)。
 */
#include <string.h>
#include "bap.h"
#include "app_config.h"

/* ---------- 小道具 ---------- */

static int32_t iabs32(int32_t v) { return (v < 0) ? -v : v; }

/** 5要素挿入ソート(昇順)。w=5固定なので最悪10スワップ。 */
static void sort5(int32_t *a, uint8_t n)
{
    for (uint8_t i = 1; i < n; i++) {
        int32_t key = a[i];
        int8_t  j = (int8_t)i - 1;
        while (j >= 0 && a[j] > key) {
            a[j + 1] = a[j];
            j--;
        }
        a[j + 1] = key;
    }
}

/* ---------- S1: Hampel (median/MAD) ---------- */

/**
 * 窓に生値を投入し、スパイクなら中央値へ置換した値を返す。
 * 窓が埋まるまでは素通し(判定材料がないため)。
 * MADスナップショットを *mad_out へ返す(ベースラインノイズ指標)。
 */
static int32_t hampel_push(bap_t *b, int32_t x, uint16_t *mad_out)
{
    b->win[b->win_i] = x;
    b->win_i = (uint8_t)((b->win_i + 1U) % BAP_HAMPEL_W);
    if (b->win_n < BAP_HAMPEL_W) {
        b->win_n++;
        *mad_out = 0;
        return x; /* 窓未充填: 素通し */
    }

    int32_t tmp[BAP_HAMPEL_W];
    memcpy(tmp, b->win, sizeof(tmp));
    sort5(tmp, BAP_HAMPEL_W);
    int32_t med = tmp[BAP_HAMPEL_W / 2U];

    int32_t dev[BAP_HAMPEL_W];
    for (uint8_t i = 0; i < BAP_HAMPEL_W; i++) {
        dev[i] = iabs32(b->win[i] - med);
    }
    sort5(dev, BAP_HAMPEL_W);
    int32_t mad = dev[BAP_HAMPEL_W / 2U];
    *mad_out = (mad > 0xFFFF) ? 0xFFFFU : (uint16_t)mad;

    /* |x-med| > k*MAD + floor でスパイク候補と判定 */
    if (iabs32(x - med) >
        (int32_t)CFG_BAP_HAMPEL_K * mad + (int32_t)CFG_BAP_HAMPEL_FLOOR_PPB) {
        int8_t sign = (x > med) ? 1 : -1;
        /* 持続性判定: 同方向2連続の逸脱は「本物のステップ」
         * (呼気立上り/回復)。置換せず受理し、直前の誤カウントも取り消す。
         * 孤立スパイクは1サンプルで終わるため従来通り置換される。 */
        if (b->prev_dev_sign == sign) {
            if (b->outliers > 0U) b->outliers--;
            b->prev_dev_sign = 0; /* ステップ確定 — 判定をリセット */
            return x;
        }
        b->prev_dev_sign = sign;
        if (b->outliers < 0xFFFFU) b->outliers++;
        return med;
    }
    b->prev_dev_sign = 0;
    return x;
}

/* ---------- S2: 適応EMA (Q8, innovation-gated) ---------- */

static int32_t ema_push(bap_t *b, int32_t x)
{
    int32_t x_q8 = x << 8;
    if (!b->y_init) {
        b->y_q8 = x_q8;
        b->y_init = true;
        return x;
    }
    int32_t innov = x_q8 - b->y_q8;
    /* イノベーション大 → α=1/2 (追従優先), 小 → α=1/8 (平滑優先) */
    uint8_t shift = (iabs32(innov >> 8) > (int32_t)CFG_BAP_FAST_PPB) ? 1U : 3U;
    b->y_q8 += innov >> shift;
    return b->y_q8 >> 8;
}

/* ---------- S3: quiet-window ベースライン学習 ---------- */

/** 窓のレンジ(max-min)を頑健な分散代理として静穏判定する。 */
static bool window_quiet(const bap_t *b)
{
    if (b->win_n < BAP_HAMPEL_W) return false;
    int32_t mn = b->win[0], mx = b->win[0];
    for (uint8_t i = 1; i < BAP_HAMPEL_W; i++) {
        if (b->win[i] < mn) mn = b->win[i];
        if (b->win[i] > mx) mx = b->win[i];
    }
    return (mx - mn) <= (int32_t)CFG_BAP_QUIET_PPB;
}

static bool baseline_update(bap_t *b, uint16_t mad, uint16_t rh10)
{
    if (!b->baseline_init) {
        b->baseline_q8 = b->y_q8;
        b->baseline_init = true;
        b->rh10_ambient = rh10;
        return false;
    }
    /* ゲート = 窓静穏 ∧ Δ小。プラトー(呼気維持相)は「静穏だが高い」ため
     * 静穏だけでは汚染される — Δ条件が必須(test_bapが捕捉した欠陥) */
    int32_t delta = (b->y_q8 - b->baseline_q8) >> 8;
    bool gate = window_quiet(b) &&
                delta < (int32_t)(CFG_BAP_ONSET_PPB / 2U);
    if (gate) {
        /* α=1/64 の遅い学習。呼気前接近・呼気中の汚染を防ぐ */
        b->baseline_q8 += (b->y_q8 - b->baseline_q8) >> 6;
        b->rh10_ambient = rh10;   /* RH基準は静穏時にだけ追従 */
        b->quiet_mad_ppb = mad;   /* 呼気前ノイズのスナップショット */
        if (b->quiet_run < 0xFFU) b->quiet_run++;
    } else {
        b->quiet_run = 0;
    }
    if (!b->baseline_locked && b->quiet_run >= CFG_BAP_QUIET_RUN_N) {
        b->baseline_locked = true;
        return true;
    }
    return false;
}

/* ---------- 公開API ---------- */

void bap_init(bap_t *b, uint8_t session_id, bool warmup_done)
{
    memset(b, 0, sizeof(*b));
    b->phase = BAP_PHASE_WARMING;
    b->session_id = session_id;
    b->warmup_done = warmup_done;
}

void bap_begin_retry(bap_t *b, uint32_t now_ms)
{
    (void)now_ms;
    /* フィルタ・ベースラインは学習済みのまま維持し、捕捉だけやり直す */
    b->phase = BAP_PHASE_READY;
    b->retries++;
    b->buf_n = 0;
    b->peak = 0;
    b->onset_run = 0;
    b->offset_run = 0;
    b->truncated = false;
    b->rh10_base = 0;
    b->rh10_max = 0;
    b->temp_sum_c10 = 0;
    b->breath_samples = 0;
}

int32_t bap_delta_ppb(const bap_t *b)
{
    if (!b->y_init || !b->baseline_init) return 0;
    int32_t d = (b->y_q8 - b->baseline_q8) >> 8;
    return (d < 0) ? 0 : d;
}

int32_t bap_baseline_ppb(const bap_t *b)
{
    return b->baseline_init ? (b->baseline_q8 >> 8) : 0;
}

/** 捕捉バッファへΔを積む。上限到達で打ち切り(truncated)を報告。 */
static bool capture_push(bap_t *b, int32_t delta, int16_t temp_c10,
                         uint16_t rh10)
{
    if (b->buf_n < BAP_BUF_MAX) {
        b->buf[b->buf_n++] = delta;
    } else {
        b->truncated = true;
        return true; /* 満杯 → offset強制 */
    }
    if (delta > b->peak) b->peak = delta;
    if (rh10 > b->rh10_max) b->rh10_max = rh10;
    b->temp_sum_c10 += temp_c10;
    b->breath_samples++;
    return false;
}

bap_evt_t bap_on_sample(bap_t *b, int32_t ppb, int16_t temp_c10,
                        uint16_t rh10, uint32_t now_ms)
{
    if (b->samples < 0xFFFFU) b->samples++;

    uint16_t mad = 0;
    int32_t v = hampel_push(b, ppb, &mad);
    (void)ema_push(b, v);

    switch (b->phase) {
    case BAP_PHASE_WARMING:
    case BAP_PHASE_READY: {
        bool locked_now = baseline_update(b, mad, rh10);
        if (b->phase == BAP_PHASE_WARMING) {
            /* WARMING→READYの昇格は状態機械が判断(warmup時間との論理積) */
            return locked_now ? BAP_EVT_BASELINE_LOCKED : BAP_EVT_NONE;
        }
        /* READY: onset監視。閾値以上がN回連続で呼気開始と判定 */
        int32_t delta = bap_delta_ppb(b);
        if (delta >= (int32_t)CFG_BAP_ONSET_PPB) {
            if (b->onset_run < BAP_HAMPEL_W) {
                b->pending[b->onset_run] = delta;
            }
            b->onset_run++;
            if (b->onset_run >= CFG_BAP_ONSET_N) {
                /* 呼気開始。判定に使ったNサンプルも呼気に含める */
                b->phase = BAP_PHASE_BREATH;
                b->onset_ms = now_ms - (uint32_t)(CFG_BAP_ONSET_N - 1U) * 1000U;
                /* 呼気前指標は「最後の静穏時」の値を使う。onset時点の窓は
                 * 既に呼気サンプルを含み、RHもフィルタ遅延のないぶん
                 * 先に上がっている(test_bapが捕捉した欠陥) */
                b->pre_mad_ppb = b->quiet_mad_ppb;
                b->rh10_base = b->rh10_ambient;
                b->rh10_max = rh10;
                b->offset_run = 0;
                for (uint8_t i = 0; i < CFG_BAP_ONSET_N && i < BAP_HAMPEL_W; i++) {
                    (void)capture_push(b, b->pending[i], temp_c10, rh10);
                }
                b->onset_run = 0;
                return BAP_EVT_ONSET;
            }
        } else {
            b->onset_run = 0;
        }
        return BAP_EVT_NONE;
    }

    case BAP_PHASE_BREATH: {
        int32_t delta = bap_delta_ppb(b);
        bool full = capture_push(b, delta, temp_c10, rh10);

        /* offset: Δがピークの CFG_BAP_OFFSET_PCT% 未満へ連続N回 */
        int32_t off_th = (b->peak * (int32_t)CFG_BAP_OFFSET_PCT) / 100;
        if (delta < off_th) {
            b->offset_run++;
        } else {
            b->offset_run = 0;
        }
        bool max_len = (b->buf_n >= (uint8_t)CFG_BAP_BREATH_MAX_S);
        if (full || max_len) b->truncated = b->truncated || max_len;

        if (b->offset_run >= CFG_BAP_OFFSET_N || full || max_len) {
            b->phase = BAP_PHASE_DONE;
            b->offset_ms = now_ms;
            return BAP_EVT_OFFSET;
        }
        return BAP_EVT_NONE;
    }

    case BAP_PHASE_DONE:
    default:
        return BAP_EVT_NONE;
    }
}

/* ---------- S5-S7: 特徴量とスコア ---------- */

static uint8_t clamp_score(int32_t s)
{
    if (s < 0) return 0;
    if (s > 100) return 100;
    return (uint8_t)s;
}

void bap_finalize(const bap_t *b, const bap_health_t *h, bap_result_t *out)
{
    memset(out, 0, sizeof(*out));
    out->session_id = b->session_id;
    out->baseline_ppb = bap_baseline_ppb(b);

    /* --- 特徴量 (docs/18 §S5) --- */
    int32_t peak = 0;
    for (uint8_t i = 0; i < b->buf_n; i++) {
        if (b->buf[i] > peak) peak = b->buf[i];
    }
    out->peak_ppb = peak;

    /* plateau: peak/2 以上のサンプル平均 */
    int64_t psum = 0;
    uint32_t pn = 0;
    uint32_t auc = 0;
    for (uint8_t i = 0; i < b->buf_n; i++) {
        int32_t d = b->buf[i];
        if (d > 0) auc += (uint32_t)d; /* 1Hz等間隔 → ΣΔ·1s */
        if (d >= peak / 2) {
            psum += d;
            pn++;
        }
    }
    out->plateau_ppb = (pn > 0U) ? (int32_t)(psum / pn) : 0;
    out->auc_ppb_s = auc;

    /* rise: 10%→90%到達時間 (1Hz → サンプル差×10 [0.1s]) */
    int32_t th10 = peak / 10, th90 = (peak * 9) / 10;
    int16_t i10 = -1, i90 = -1;
    for (uint8_t i = 0; i < b->buf_n; i++) {
        if (i10 < 0 && b->buf[i] >= th10) i10 = (int16_t)i;
        if (i90 < 0 && b->buf[i] >= th90) i90 = (int16_t)i;
    }
    out->rise_ds = (i10 >= 0 && i90 >= i10) ? (uint16_t)((i90 - i10) * 10) : 0;

    uint32_t dur_ms = (b->offset_ms > b->onset_ms)
                          ? (b->offset_ms - b->onset_ms) : 0;
    if (dur_ms > 655000U) dur_ms = 655000U;
    out->duration_ds = (uint16_t)(dur_ms / 100U);

    out->temp_c10_mean = (b->breath_samples > 0U)
        ? (int16_t)(b->temp_sum_c10 / (int32_t)b->breath_samples) : 0;
    int32_t rh_delta = (int32_t)b->rh10_max - (int32_t)b->rh10_base;
    out->rh10_delta = (int16_t)((rh_delta < 0) ? 0 : rh_delta);
    out->pre_mad_ppb = b->pre_mad_ppb;

    /* --- フラグ --- */
    bool rh_ok = (rh_delta >= (int32_t)CFG_BAP_RH_DELTA_MIN_10);
    if (rh_ok)          out->flags |= BAP_RF_RH_OK;
    if (b->truncated)   out->flags |= BAP_RF_TRUNCATED;
    if (b->retries > 0) out->flags |= BAP_RF_RETRIED;
    if (b->warmup_done) out->flags |= BAP_RF_WARMUP_OK;
    if (b->low_batt)    out->flags |= BAP_RF_LOW_BATT;

    /* --- S6: 品質Q (減点方式, docs/18の表と1:1) --- */
    int32_t q = 100;
    if (b->samples > 0U) {
        /* 外れ値率[%]の5%超過分 → −(超過×4), 最大30。
         * 立上り/回復の遷移サンプルはHampelに1-2個置換されうるため、
         * 「超過分」だけを罰する(全率だと正常な呼気まで減点される) */
        int32_t out_pct = (int32_t)b->outliers * 100 / (int32_t)b->samples;
        if (out_pct > 5) {
            int32_t d = (out_pct - 5) * 4;
            q -= (d > 30) ? 30 : d;
        }
    }
    /* サンプル欠落: 期待=呼気秒数(1Hz), 実=breath_samples */
    uint32_t expected = dur_ms / 1000U;
    if (expected > 0U && b->breath_samples < expected) {
        uint32_t miss_pct = (expected - b->breath_samples) * 100U / expected;
        if (miss_pct > 5U) {
            uint32_t d = miss_pct * 2U;
            q -= (int32_t)((d > 15U) ? 15U : d);
        }
    }
    if (b->pre_mad_ppb > CFG_BAP_PRE_MAD_MAX_PPB) q -= 15;
    if (!rh_ok)                                   q -= 20;
    if (out->duration_ds < CFG_BAP_BREATH_MIN_S * 10U) q -= 20;
    if (b->truncated)                             q -= 10;
    if (!b->warmup_done)                          q -= 25;
    out->quality = clamp_score(q);

    /* --- S7: 信頼度C (計測器健全性) --- */
    int32_t c = 100;
    if (h->samples_total > 0U) {
        int32_t pe_pct = (int32_t)h->parse_errors * 100
                         / (int32_t)(h->samples_total + h->parse_errors);
        if (pe_pct > 2) c -= 20;
    }
    if (h->stuck_events > 0U) c -= 40;
    if (h->sensor_retries > 0U) {
        int32_t d = 10 * (int32_t)h->sensor_retries;
        c -= (d > 30) ? 30 : d;
    }
    if (h->temp_out_of_comp) c -= 15;
    if (out->baseline_ppb > (int32_t)CFG_BAP_BASELINE_MAX_PPB) c -= 20;
    if (h->crc_errors > 0U) c -= 5;
    out->confidence = clamp_score(c);

    /* --- S8: 再測定推奨 (最終判断はアプリ/飼い主へ) --- */
    if (out->quality < CFG_BAP_RETRY_QUALITY) {
        out->flags |= BAP_RF_REMEASURE;
    }
}
