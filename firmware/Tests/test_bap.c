/**
 * @file test_bap.c
 * @brief Breath Analysis Pipeline のゴールデンベクタ検証 (docs/18 §7)。
 *        合成呼気波形(立上り→プラトー→回復)にスパイク・ドリフト・
 *        湿度上昇を注入し、S1〜S8の数値挙動を固定する。
 */
#include "test_util.h"
#include "bap.h"
#include "app_config.h"

/* ---- 合成波形ヘルパ ----
 * ベースライン800ppb、呼気で+6000ppbまで指数的に立上り、
 * プラトー維持後に回復する「もっともらしい」電気化学応答。 */

static uint32_t g_now;

static bap_evt_t feed(bap_t *b, int32_t ppb, uint16_t rh10)
{
    g_now += 1000U; /* 1Hz */
    return bap_on_sample(b, ppb, 250 /*25.0℃*/, rh10, g_now);
}

/** ベースライン学習が完了するまで静穏サンプルを流す */
static void settle(bap_t *b, int32_t base_ppb)
{
    for (int i = 0; i < 15 && !b->baseline_locked; i++) {
        (void)feed(b, base_ppb + ((i & 1) ? 40 : -40), 4000);
    }
}

/* ================= S1: Hampel ================= */

static void test_hampel_removes_spike(void)
{
    bap_t b;
    g_now = 0;
    bap_init(&b, 1, true);
    /* 安定値の中に1つだけ+20000ppbのスパイク */
    int32_t seq[] = {800, 820, 790, 810, 800, 21000, 805, 795, 810, 800};
    for (int i = 0; i < 10; i++) (void)feed(&b, seq[i], 4000);
    ASSERT_EQ(b.outliers, 1);          /* スパイクは1回だけ置換 */
    /* スパイクがEMAへ漏れていない(Δがonset閾値を超えない) */
    ASSERT_TRUE(bap_delta_ppb(&b) < (int32_t)CFG_BAP_ONSET_PPB);
}

static void test_hampel_passes_legitimate_rise(void)
{
    bap_t b;
    g_now = 0;
    bap_init(&b, 1, true);
    settle(&b, 800);
    /* 本物の呼気立上り(持続する)は置換されない */
    uint16_t before = b.outliers;
    (void)feed(&b, 2000, 4000);
    (void)feed(&b, 3500, 4000);
    (void)feed(&b, 5000, 4000);
    (void)feed(&b, 6000, 4000);
    /* 立上り初回はスパイクと区別できず置換されうるが、
     * 持続入力では窓中央値が追従し置換は最初の1-2回で止まる */
    ASSERT_TRUE(b.outliers - before <= 2);
    ASSERT_TRUE(bap_delta_ppb(&b) > 1000);
}

/* ================= S3: ベースライン ================= */

static void test_baseline_locks_when_quiet(void)
{
    bap_t b;
    g_now = 0;
    bap_init(&b, 1, true);
    ASSERT_TRUE(!b.baseline_locked);
    settle(&b, 800);
    ASSERT_TRUE(b.baseline_locked);
    /* 学習されたベースラインは真値±100ppb以内 */
    int32_t bl = bap_baseline_ppb(&b);
    ASSERT_TRUE(bl > 700 && bl < 900);
}

static void test_baseline_not_polluted_by_pre_breath_rise(void)
{
    bap_t b;
    g_now = 0;
    bap_init(&b, 1, true);
    settle(&b, 800);
    int32_t bl_before = bap_baseline_ppb(&b);
    /* 犬が近づいて値が上がり始める(静穏でない) → 学習停止 */
    (void)feed(&b, 1400, 4000);
    (void)feed(&b, 2200, 4000);
    (void)feed(&b, 3200, 4000);
    int32_t bl_after = bap_baseline_ppb(&b);
    ASSERT_TRUE(bl_after - bl_before < 100); /* 汚染されていない */
}

/* ================= S4-S8: 呼気E2E ================= */

/** 完全な合成呼気: settle→立上り→プラトー→回復。RH上昇つき。 */
static bap_evt_t run_breath(bap_t *b, bap_result_t *out, bool humid)
{
    settle(b, 800);
    b->phase = BAP_PHASE_READY; /* 状態機械の昇格を模擬 */
    uint16_t rh_breath = humid ? 4600 : 4010; /* +6.0%RH / +0.1%RH */

    bap_evt_t ev = BAP_EVT_NONE;
    /* 立上り(6サンプル) */
    int32_t rise[] = {1500, 2600, 3800, 4800, 5600, 6000};
    for (int i = 0; i < 6; i++) {
        ev = feed(b, 800 + rise[i], rh_breath);
        if (ev == BAP_EVT_ONSET) break;
    }
    /* プラトー(12サンプル @6000±100) */
    for (int i = 0; i < 12; i++) {
        ev = feed(b, 6800 + ((i & 1) ? 100 : -100), rh_breath);
    }
    /* 回復(offset検出まで) */
    int32_t rec[] = {4000, 2500, 1500, 1000, 900, 850, 820, 810};
    for (int i = 0; i < 8; i++) {
        ev = feed(b, 800 + rec[i] - 800, rh_breath);
        if (ev == BAP_EVT_OFFSET) break;
    }
    if (b->phase == BAP_PHASE_DONE && out != NULL) {
        bap_health_t h = {0};
        h.samples_total = b->samples;
        bap_finalize(b, &h, out);
    }
    return ev;
}

static void test_breath_onset_offset_detected(void)
{
    bap_t b;
    bap_result_t r;
    g_now = 0;
    bap_init(&b, 7, true);
    bap_evt_t ev = run_breath(&b, &r, true);
    ASSERT_EQ(ev, BAP_EVT_OFFSET);
    ASSERT_EQ(b.phase, BAP_PHASE_DONE);
    ASSERT_EQ(r.session_id, 7);
    /* 特徴量の妥当域(合成波形から) */
    ASSERT_TRUE(r.peak_ppb > 4500 && r.peak_ppb < 7000);
    ASSERT_TRUE(r.plateau_ppb > 3000 && r.plateau_ppb <= r.peak_ppb);
    ASSERT_TRUE(r.auc_ppb_s > 40000U);
    ASSERT_TRUE(r.duration_ds >= 100U); /* ≥10s */
    ASSERT_TRUE(r.rise_ds > 0U);
}

static void test_quality_high_for_clean_humid_breath(void)
{
    bap_t b;
    bap_result_t r;
    g_now = 0;
    bap_init(&b, 1, true);
    (void)run_breath(&b, &r, true);
    ASSERT_TRUE((r.flags & BAP_RF_RH_OK) != 0);
    ASSERT_TRUE((r.flags & BAP_RF_WARMUP_OK) != 0);
    ASSERT_TRUE(r.quality >= 90);
    ASSERT_TRUE((r.flags & BAP_RF_REMEASURE) == 0);
    ASSERT_EQ(r.confidence, 100);
}

static void test_quality_penalized_without_rh_evidence(void)
{
    bap_t b;
    bap_result_t r;
    g_now = 0;
    bap_init(&b, 1, true);
    (void)run_breath(&b, &r, false); /* 湿度が上がらない=呼気の裏付けなし */
    ASSERT_TRUE((r.flags & BAP_RF_RH_OK) == 0);
    ASSERT_TRUE(r.quality <= 80); /* −20 */
}

static void test_quality_penalized_during_warmup(void)
{
    bap_t b;
    bap_result_t r;
    g_now = 0;
    bap_init(&b, 1, false); /* ウォームアップ未了 */
    (void)run_breath(&b, &r, true);
    ASSERT_TRUE((r.flags & BAP_RF_WARMUP_OK) == 0);
    ASSERT_TRUE(r.quality <= 75); /* −25 */
}

static void test_confidence_penalized_by_instrument_health(void)
{
    bap_t b;
    bap_result_t r;
    g_now = 0;
    bap_init(&b, 1, true);
    settle(&b, 800);
    b.phase = BAP_PHASE_READY;
    /* 短い呼気を作る(回復はフィルタ遅延ぶん長めに流す) */
    for (int i = 0; i < 5; i++) (void)feed(&b, 6000, 4600);
    for (int i = 0; i < 10 && b.phase != BAP_PHASE_DONE; i++) {
        (void)feed(&b, 900, 4600);
    }
    ASSERT_EQ(b.phase, BAP_PHASE_DONE);

    bap_health_t h = {0};
    h.samples_total = b.samples;
    h.stuck_events = 1;      /* −40 */
    h.sensor_retries = 2;    /* −20 */
    h.crc_errors = 1;        /* −5 */
    bap_finalize(&b, &h, &r);
    ASSERT_EQ(r.confidence, 35);
}

static void test_low_quality_breath_advises_remeasure(void)
{
    /* 現実的な失敗シナリオ: ウォームアップ未了のまま短い呼気、
     * しかも湿度上昇の裏付けなし(マスクが正しく当たっていない疑い) */
    bap_t b;
    bap_result_t r;
    g_now = 0;
    bap_init(&b, 1, false); /* ウォームアップ未了 −25 */
    settle(&b, 800);
    b.phase = BAP_PHASE_READY;
    for (int i = 0; i < 4; i++) (void)feed(&b, 6000, 4010); /* RHなし −20 */
    for (int i = 0; i < 12 && b.phase != BAP_PHASE_DONE; i++) {
        (void)feed(&b, 900, 4010);
    }
    ASSERT_EQ(b.phase, BAP_PHASE_DONE);
    bap_health_t h = {0};
    h.samples_total = b.samples;
    bap_finalize(&b, &h, &r);
    ASSERT_TRUE(r.quality < CFG_BAP_RETRY_QUALITY);
    ASSERT_TRUE((r.flags & BAP_RF_REMEASURE) != 0);
}

static void test_truncation_at_window_limit(void)
{
    bap_t b;
    bap_result_t r;
    g_now = 0;
    bap_init(&b, 1, true);
    settle(&b, 800);
    b.phase = BAP_PHASE_READY;
    /* 終わらない呼気: 窓上限で打ち切られること */
    bap_evt_t ev = BAP_EVT_NONE;
    for (int i = 0; i < (int)CFG_BAP_BREATH_MAX_S + 20; i++) {
        ev = feed(&b, 6800, 4600);
        if (ev == BAP_EVT_OFFSET) break;
    }
    ASSERT_EQ(ev, BAP_EVT_OFFSET);
    bap_health_t h = {0};
    h.samples_total = b.samples;
    bap_finalize(&b, &h, &r);
    ASSERT_TRUE((r.flags & BAP_RF_TRUNCATED) != 0);
}

static void test_retry_keeps_baseline(void)
{
    bap_t b;
    g_now = 0;
    bap_init(&b, 1, true);
    settle(&b, 800);
    b.phase = BAP_PHASE_READY;
    int32_t bl = bap_baseline_ppb(&b);
    for (int i = 0; i < 5; i++) (void)feed(&b, 6000, 4010);
    for (int i = 0; i < 10 && b.phase != BAP_PHASE_DONE; i++) {
        (void)feed(&b, 900, 4010);
    }
    ASSERT_EQ(b.phase, BAP_PHASE_DONE);
    bap_begin_retry(&b, g_now);
    ASSERT_EQ(b.phase, BAP_PHASE_READY);
    ASSERT_EQ(b.retries, 1);
    ASSERT_EQ(bap_baseline_ppb(&b), bl); /* 学習済み資産は維持 */
    ASSERT_EQ(b.buf_n, 0);               /* 捕捉はリセット */
}

static void test_no_onset_below_threshold(void)
{
    bap_t b;
    g_now = 0;
    bap_init(&b, 1, true);
    settle(&b, 800);
    b.phase = BAP_PHASE_READY;
    /* 閾値未満の揺らぎではonsetしない */
    for (int i = 0; i < 30; i++) {
        bap_evt_t ev = feed(&b, 800 + ((i % 3) * 150), 4000);
        ASSERT_TRUE(ev != BAP_EVT_ONSET);
    }
    ASSERT_EQ(b.phase, BAP_PHASE_READY);
}

int main(void)
{
    printf("test_bap\n");
    test_hampel_removes_spike();
    test_hampel_passes_legitimate_rise();
    test_baseline_locks_when_quiet();
    test_baseline_not_polluted_by_pre_breath_rise();
    test_breath_onset_offset_detected();
    test_quality_high_for_clean_humid_breath();
    test_quality_penalized_without_rh_evidence();
    test_quality_penalized_during_warmup();
    test_confidence_penalized_by_instrument_health();
    test_low_quality_breath_advises_remeasure();
    test_truncation_at_window_limit();
    test_retry_keeps_baseline();
    test_no_onset_below_threshold();
    return TEST_SUMMARY();
}
