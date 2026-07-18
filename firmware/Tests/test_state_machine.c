/**
 * @file test_state_machine.c
 * @brief ステートマシンのホスト結合テスト。
 *        dgs2/ble_linkの送信を捕捉し、時刻を進めながら遷移と
 *        HPPイベント生成を検証する(HAL非依存設計の実証)。
 */
#include "test_util.h"
#include "state_machine.h"
#include "app_config.h"

/* ---- センサ側送信の捕捉 ---- */
static char   g_sensor_tx[256];
static size_t g_sensor_tx_len;

static void sensor_tx(const uint8_t *d, size_t n)
{
    for (size_t i = 0; i < n && g_sensor_tx_len < sizeof(g_sensor_tx) - 1; i++) {
        g_sensor_tx[g_sensor_tx_len++] = (char)d[i];
    }
    g_sensor_tx[g_sensor_tx_len] = '\0';
}

/* ---- BLE側送信の捕捉 (HPPフレームへデコードして保持) ---- */
#define MAX_FRAMES 64
static hpp_frame_t g_frames[MAX_FRAMES];
static int         g_frame_count;
static hpp_decoder_t g_ble_dec;

static void ble_tx(const uint8_t *d, size_t n)
{
    hpp_frame_t f;
    for (size_t i = 0; i < n; i++) {
        if (hpp_decoder_feed(&g_ble_dec, d[i], &f) &&
            g_frame_count < MAX_FRAMES) {
            g_frames[g_frame_count++] = f;
        }
    }
}

static uint16_t g_batt_mv = 3700;
static uint16_t fake_battery_mv(void) { return g_batt_mv; }

/* ---- テストフィクスチャ ---- */
static dgs2_t     g_sensor;
static ble_link_t g_link;
static sm_t       g_sm;

static void reset_capture(void)
{
    g_sensor_tx_len = 0;
    g_sensor_tx[0] = '\0';
    g_frame_count = 0;
}

/** 現在の捕捉分から type/payload[0] 一致のフレーム数を数える */
static int count_errors_of(uint8_t code)
{
    int n = 0;
    for (int i = 0; i < g_frame_count; i++) {
        if (g_frames[i].type == HPP_EVT_ERROR &&
            g_frames[i].payload[0] == code) {
            n++;
        }
    }
    return n;
}

static void setup(uint32_t now)
{
    reset_capture();
    g_batt_mv = 3700;
    hpp_decoder_init(&g_ble_dec);
    dgs2_init(&g_sensor, sensor_tx);
    ble_link_init(&g_link, ble_tx);
    sm_init(&g_sm, &g_sensor, &g_link, fake_battery_mv, now);
}

/** アプリからのコマンド受信を模擬 */
static void inject_cmd(uint8_t type, const uint8_t *payload, uint8_t len,
                       uint32_t now)
{
    hpp_frame_t f = {0};
    f.type = type;
    f.len = len;
    if (len > 0) memcpy(f.payload, payload, len);
    sm_on_frame(&g_sm, &f, now);
}

/** 直近フレームからtype一致の最後のものを返す(なければNULL) */
static const hpp_frame_t *last_frame_of(uint8_t type)
{
    for (int i = g_frame_count - 1; i >= 0; i--) {
        if (g_frames[i].type == type) return &g_frames[i];
    }
    return NULL;
}

static const char *VALID_LINE =
    "032122030234, 1588, 2436, 3278, 32291, 26636, 20390";

/* ================= テスト ================= */

static void test_boot_sends_wake_and_single(void)
{
    setup(1000);
    ASSERT_EQ(g_sm.state, SM_SENSOR_INIT);
    /* Sleep残留対策のWake('\n') + 単発測定('\r') */
    ASSERT_STREQ(g_sensor_tx, "\n\r");
}

static void test_sensor_init_to_idle_captures_sn(void)
{
    setup(1000);
    sm_on_sensor_line(&g_sm, VALID_LINE, 1100);
    ASSERT_EQ(g_sm.state, SM_IDLE);
    ASSERT_STREQ(g_sm.sensor_sn, "032122030234");
}

static void test_sensor_init_timeout_to_error(void)
{
    setup(0);
    uint32_t now = 0;
    /* リトライ3回 + 超過でERROR */
    for (int i = 0; i < 4; i++) {
        now += CFG_SENSOR_BOOT_TIMEOUT_MS + 1;
        sm_tick(&g_sm, now);
    }
    ASSERT_EQ(g_sm.state, SM_ERROR);
    const hpp_frame_t *err = last_frame_of(HPP_EVT_ERROR);
    ASSERT_TRUE(err != NULL);
    ASSERT_EQ(err->payload[0], E_SENSOR_TIMEOUT);
}

static void test_start_continuous_sends_C_and_acks(void)
{
    setup(0);
    sm_on_sensor_line(&g_sm, VALID_LINE, 100); /* → IDLE */
    reset_capture();

    uint8_t iv = 1;
    inject_cmd(HPP_CMD_START_CONT, &iv, 1, 200);
    ASSERT_EQ(g_sm.state, SM_MEASURING);
    ASSERT_STREQ(g_sensor_tx, "C"); /* 大文字C */
    ASSERT_TRUE(last_frame_of(HPP_ACK) != NULL);
}

static void test_start_rejected_when_not_idle(void)
{
    setup(0);
    /* SENSOR_INIT中は開始不可 */
    uint8_t iv = 1;
    inject_cmd(HPP_CMD_START_CONT, &iv, 1, 100);
    const hpp_frame_t *nak = last_frame_of(HPP_NAK);
    ASSERT_TRUE(nak != NULL);
    ASSERT_EQ(nak->payload[1], E_BUSY);
}

static void test_invalid_interval_rejected(void)
{
    setup(0);
    sm_on_sensor_line(&g_sm, VALID_LINE, 100);
    uint8_t iv = 61;
    inject_cmd(HPP_CMD_START_CONT, &iv, 1, 200);
    const hpp_frame_t *nak = last_frame_of(HPP_NAK);
    ASSERT_TRUE(nak != NULL);
    ASSERT_EQ(nak->payload[1], E_INVALID_PARAM);
    ASSERT_EQ(g_sm.state, SM_IDLE);
}

static void test_measuring_emits_data_and_summary(void)
{
    setup(0);
    sm_on_sensor_line(&g_sm, VALID_LINE, 100);
    uint8_t iv = 1;
    inject_cmd(HPP_CMD_START_CONT, &iv, 1, 200);
    reset_capture();

    /* 3サンプル受信 (ウォームアップ期間中) */
    sm_on_sensor_line(&g_sm, "032122030234, 1000, 2436, 3278, 1, 2, 3", 1200);
    sm_on_sensor_line(&g_sm, "032122030234, 2000, 2436, 3278, 1, 2, 3", 2200);
    sm_on_sensor_line(&g_sm, "032122030234, 3000, 2436, 3278, 1, 2, 3", 3200);

    const hpp_frame_t *data = last_frame_of(HPP_EVT_DATA);
    ASSERT_TRUE(data != NULL);
    ASSERT_EQ(data->len, 13);
    ASSERT_EQ((int32_t)hpp_get_u32(&data->payload[4]), 3000); /* h2_ppb */
    ASSERT_TRUE(data->payload[12] & HPP_FLAG_WARMUP);

    /* 停止 → 'C'再送 + サマリ */
    reset_capture();
    inject_cmd(HPP_CMD_STOP, NULL, 0, 4000);
    ASSERT_EQ(g_sm.state, SM_IDLE);
    ASSERT_STREQ(g_sensor_tx, "C");
    const hpp_frame_t *sum = last_frame_of(HPP_EVT_SUMMARY);
    ASSERT_TRUE(sum != NULL);
    ASSERT_EQ(hpp_get_u16(&sum->payload[0]), 3);              /* n */
    ASSERT_EQ((int32_t)hpp_get_u32(&sum->payload[2]), 2000);  /* avg */
    ASSERT_EQ((int32_t)hpp_get_u32(&sum->payload[6]), 3000);  /* max */
    ASSERT_EQ((int32_t)hpp_get_u32(&sum->payload[10]), 1000); /* min */
}

static void test_start_confirm_retry_ladder(void)
{
    /* 'C'トグル不発時: '\r'プローブ → 'C'再トグル → 超過でERROR */
    setup(0);
    sm_on_sensor_line(&g_sm, VALID_LINE, 100);
    uint8_t iv = 1;
    inject_cmd(HPP_CMD_START_CONT, &iv, 1, 200);
    reset_capture();

    uint32_t now = 200;
    now += CFG_SENSOR_CONFIRM_MS + 1;
    sm_tick(&g_sm, now); /* retry1: wake+'\r' */
    ASSERT_STREQ(g_sensor_tx, "\n\r");

    now += CFG_SENSOR_CONFIRM_MS + 1;
    sm_tick(&g_sm, now); /* retry2: 'C' */
    ASSERT_STREQ(g_sensor_tx, "\n\rC");

    now += CFG_SENSOR_CONFIRM_MS + 1;
    sm_tick(&g_sm, now); /* retry3: 'C' */
    now += CFG_SENSOR_CONFIRM_MS + 1;
    sm_tick(&g_sm, now); /* 超過 → ERROR */
    ASSERT_EQ(g_sm.state, SM_ERROR);
    const hpp_frame_t *err = last_frame_of(HPP_EVT_ERROR);
    ASSERT_TRUE(err != NULL);
    ASSERT_EQ(err->payload[0], E_SENSOR_TIMEOUT);
}

static void test_ble_inactivity_stops_and_sleeps(void)
{
    setup(0);
    sm_on_sensor_line(&g_sm, VALID_LINE, 100);
    uint8_t iv = 1;
    inject_cmd(HPP_CMD_START_CONT, &iv, 1, 200);

    /* センサデータは来続けるがBLEは無通信 */
    uint32_t now = 200;
    while (now < 200 + CFG_BLE_INACTIVITY_MS + 2000) {
        now += 1000;
        sm_on_sensor_line(&g_sm, VALID_LINE, now);
        sm_tick(&g_sm, now);
    }
    ASSERT_EQ(g_sm.state, SM_SLEEP);
    ASSERT_TRUE(g_sm.sleep_requested);
    ASSERT_TRUE(last_frame_of(HPP_EVT_SUMMARY) != NULL);
    /* DGS2にもSleep('s')が送られている */
    ASSERT_TRUE(g_sensor_tx[g_sensor_tx_len - 1] == 's');
}

static void test_session_cap_30min(void)
{
    setup(0);
    sm_on_sensor_line(&g_sm, VALID_LINE, 100);
    uint8_t iv = 1;
    inject_cmd(HPP_CMD_START_CONT, &iv, 1, 200);

    uint32_t now = 200;
    while (now < CFG_MEASURE_MAX_MS + 5000 && g_sm.state == SM_MEASURING) {
        now += 1000;
        reset_capture(); /* 長時間ループでの捕捉バッファ溢れを防ぐ */
        sm_on_sensor_line(&g_sm, VALID_LINE, now);
        inject_cmd(HPP_CMD_GET_STATUS, NULL, 0, now); /* keep-alive */
        sm_tick(&g_sm, now);
    }
    ASSERT_EQ(g_sm.state, SM_IDLE);
    ASSERT_TRUE(last_frame_of(HPP_EVT_SUMMARY) != NULL);
}

static void test_sleep_wake_via_frame(void)
{
    setup(0);
    sm_on_sensor_line(&g_sm, VALID_LINE, 100);
    inject_cmd(HPP_CMD_SLEEP, NULL, 0, 200);
    ASSERT_EQ(g_sm.state, SM_SLEEP);
    reset_capture();

    inject_cmd(HPP_CMD_GET_STATUS, NULL, 0, 5000);
    ASSERT_EQ(g_sm.state, SM_IDLE);
    ASSERT_EQ(g_sensor_tx[0], '\n'); /* DGS2 Wakeバイト */
    const hpp_frame_t *st = last_frame_of(HPP_EVT_STATUS);
    ASSERT_TRUE(st != NULL);
    ASSERT_EQ(st->len, 14); /* 拡張ステータス(診断統計+arq_drops込み) */
    ASSERT_EQ(hpp_get_u16(&st->payload[1]), 3700); /* battery */
    ASSERT_EQ(hpp_get_u16(&st->payload[12]), 0);   /* arq_drops */
}

static void test_idle_auto_sleep(void)
{
    setup(0);
    sm_on_sensor_line(&g_sm, VALID_LINE, 100);
    sm_tick(&g_sm, 100 + CFG_IDLE_TO_SLEEP_MS + 1);
    ASSERT_EQ(g_sm.state, SM_SLEEP);
    ASSERT_TRUE(g_sm.sleep_requested);
}

static void test_error_auto_sleep(void)
{
    setup(0);
    uint32_t now = 0;
    for (int i = 0; i < 4; i++) {
        now += CFG_SENSOR_BOOT_TIMEOUT_MS + 1;
        sm_tick(&g_sm, now);
    }
    ASSERT_EQ(g_sm.state, SM_ERROR);
    sm_tick(&g_sm, now + CFG_ERROR_TO_SLEEP_MS + 1);
    ASSERT_EQ(g_sm.state, SM_SLEEP); /* 電池保護 */
}

static void test_error_recovery_via_wake_sends_reset(void)
{
    setup(0);
    uint32_t now = 0;
    for (int i = 0; i < 4; i++) {
        now += CFG_SENSOR_BOOT_TIMEOUT_MS + 1;
        sm_tick(&g_sm, now);
    }
    ASSERT_EQ(g_sm.state, SM_ERROR);
    reset_capture();

    inject_cmd(HPP_CMD_WAKE, NULL, 0, now + 100);
    ASSERT_EQ(g_sm.state, SM_SENSOR_INIT);
    ASSERT_STREQ(g_sensor_tx, "r"); /* モジュールリセットで復旧試行 */
    /* リセット後の応答で復帰 */
    sm_on_sensor_line(&g_sm, VALID_LINE, now + 2000);
    ASSERT_EQ(g_sm.state, SM_IDLE);
}

static void test_idle_heals_unexpected_stream(void)
{
    /* MCUのみリセットされDGS2が連続モードのまま → IDLEで検知し停止 */
    setup(0);
    sm_on_sensor_line(&g_sm, VALID_LINE, 100); /* → IDLE */
    reset_capture();

    /* 停止トグル猶予(CFG_STOP_CONFIRM_MS)を超えた後もストリームが継続 */
    uint32_t t0 = 100 + CFG_STOP_CONFIRM_MS + 100;
    sm_on_sensor_line(&g_sm, VALID_LINE, t0);
    sm_on_sensor_line(&g_sm, VALID_LINE, t0 + 1000);
    ASSERT_STREQ(g_sensor_tx, "C"); /* 停止トグルを自動送信 */
}

static void test_zero_calibration_only_in_idle(void)
{
    setup(0);
    sm_on_sensor_line(&g_sm, VALID_LINE, 100);
    reset_capture();

    inject_cmd(HPP_CMD_ZERO, NULL, 0, 200);
    ASSERT_STREQ(g_sensor_tx, "Z");
    ASSERT_TRUE(last_frame_of(HPP_ACK) != NULL);

    /* 測定中はNAK(E_BUSY) */
    uint8_t iv = 1;
    inject_cmd(HPP_CMD_START_CONT, &iv, 1, 300);
    reset_capture();
    inject_cmd(HPP_CMD_ZERO, NULL, 0, 400);
    const hpp_frame_t *nak = last_frame_of(HPP_NAK);
    ASSERT_TRUE(nak != NULL);
    ASSERT_EQ(nak->payload[0], HPP_CMD_ZERO);
    ASSERT_EQ(nak->payload[1], E_BUSY);
}

static void test_low_battery_notified_once_without_aborting(void)
{
    setup(0);
    sm_on_sensor_line(&g_sm, VALID_LINE, 100);
    uint8_t iv = 1;
    inject_cmd(HPP_CMD_START_CONT, &iv, 1, 200);

    g_batt_mv = 3100; /* 閾値(3300)未満へ低下 */
    uint32_t now = 200;
    int low_batt_events = 0;

    /* 2分間測定を継続(データ+keep-aliveを1Hzで供給) */
    while (now < 200 + 2U * CFG_BATT_CHECK_MS + 5000U) {
        now += 1000;
        reset_capture();
        sm_on_sensor_line(&g_sm, VALID_LINE, now);
        inject_cmd(HPP_CMD_GET_STATUS, NULL, 0, now);
        sm_tick(&g_sm, now);
        low_batt_events += count_errors_of(E_LOW_BATTERY);
    }

    ASSERT_EQ(low_batt_events, 1);          /* 一度だけ通知 */
    ASSERT_EQ(g_sm.state, SM_MEASURING);    /* 測定は中断しない */

    /* 回復(充電)後に再び低下すれば、もう一度だけ通知される */
    g_batt_mv = 3600;
    now += CFG_BATT_CHECK_MS + 1000;
    sm_on_sensor_line(&g_sm, VALID_LINE, now);
    inject_cmd(HPP_CMD_GET_STATUS, NULL, 0, now);
    sm_tick(&g_sm, now);

    g_batt_mv = 3100;
    low_batt_events = 0;
    uint32_t end = now + 2U * CFG_BATT_CHECK_MS + 5000U;
    while (now < end) {
        now += 1000;
        reset_capture();
        sm_on_sensor_line(&g_sm, VALID_LINE, now);
        inject_cmd(HPP_CMD_GET_STATUS, NULL, 0, now);
        sm_tick(&g_sm, now);
        low_batt_events += count_errors_of(E_LOW_BATTERY);
    }
    ASSERT_EQ(low_batt_events, 1);
}

static void test_parse_failure_storm_stops_measurement(void)
{
    setup(0);
    sm_on_sensor_line(&g_sm, VALID_LINE, 100);
    uint8_t iv = 1;
    inject_cmd(HPP_CMD_START_CONT, &iv, 1, 200);
    reset_capture();

    for (int i = 0; i <= (int)CFG_SENSOR_RETRY_MAX; i++) {
        sm_on_sensor_line(&g_sm, "garbage,line", 300 + (uint32_t)i * 100);
    }
    ASSERT_EQ(g_sm.state, SM_IDLE);
    const hpp_frame_t *err = last_frame_of(HPP_EVT_ERROR);
    ASSERT_TRUE(err != NULL);
    ASSERT_EQ(err->payload[0], E_SENSOR_PARSE);
}

/* ================= v2: 呼気セッション (docs/18 §3) ================= */

static uint32_t g_t; /* 進行時刻 */

/** 可変ppb/RHのセンサ行を1秒進めて注入し、tickも回す */
static void feed_line(int32_t ppb, int rh_x100)
{
    char buf[128];
    snprintf(buf, sizeof(buf), "032122030234, %ld, 2500, %d, 32291, 26636, 20390",
             (long)ppb, rh_x100);
    g_t += 1000;
    sm_on_sensor_line(&g_sm, buf, g_t);
    sm_tick(&g_sm, g_t);
}

/** 静穏サンプル(±40ppbの揺らぎ — 固着検出も回避) */
static void feed_quiet(int n, int32_t base)
{
    for (int i = 0; i < n; i++) {
        feed_line(base + ((i & 1) ? 40 : -40), 4000);
    }
}

static int count_of(uint8_t type)
{
    int n = 0;
    for (int i = 0; i < g_frame_count; i++) {
        if (g_frames[i].type == type) n++;
    }
    return n;
}

/** boot後ウォームアップ済みの状態で呼気セッションをREADYまで進める */
static void breath_session_to_ready(void)
{
    setup(0);
    sm_on_sensor_line(&g_sm, VALID_LINE, 100);
    ASSERT_EQ(g_sm.state, SM_IDLE);
    g_t = CFG_WARMUP_MS + 10000U; /* ウォームアップ経過済み */
    inject_cmd(HPP_CMD_BREATH, NULL, 0, g_t);
    ASSERT_EQ(g_sm.state, SM_WARMUP);
    ASSERT_TRUE(last_frame_of(HPP_ACK) != NULL);
    feed_quiet(12, 800); /* ベースライン学習→ロック→READY昇格 */
    ASSERT_EQ(g_sm.state, SM_READY);
}

static void test_breath_full_flow_emits_result(void)
{
    breath_session_to_ready();
    reset_capture();

    /* 呼気: 立上り→プラトー(RH+6%)→回復 */
    int32_t rise[] = {2300, 3400, 4600, 5600, 6400, 6800};
    for (int i = 0; i < 6; i++) feed_line(rise[i], 4600);
    ASSERT_EQ(g_sm.state, SM_BREATH);
    for (int i = 0; i < 12; i++) feed_line(6800 + ((i & 1) ? 100 : -100), 4600);
    for (int i = 0; i < 12 && g_sm.state == SM_BREATH; i++) {
        feed_line(850, 4600);
    }
    /* ANALYZE→VALIDATE→REPORT→IDLE (各1tick) */
    for (int i = 0; i < 4; i++) sm_tick(&g_sm, ++g_t);
    ASSERT_EQ(g_sm.state, SM_IDLE);

    const hpp_frame_t *r = last_frame_of(HPP_EVT_RESULT);
    ASSERT_TRUE(r != NULL);
    ASSERT_EQ(r->len, 30);
    ASSERT_TRUE(r->payload[1] >= 90);                 /* quality */
    ASSERT_EQ(r->payload[2], 100);                    /* confidence */
    ASSERT_TRUE((r->payload[3] & 0x02) != 0);         /* RH_OK */
    ASSERT_TRUE((r->payload[3] & 0x10) != 0);         /* WARMUP_OK */
    ASSERT_TRUE((int32_t)hpp_get_u32(&r->payload[8]) > 4000); /* peak */
    /* フェーズ実況が届いている(BREATH/ANALYZE/DONE) */
    ASSERT_TRUE(count_of(HPP_EVT_PHASE) >= 3);
    /* センサは停止トグル済み(開始1回+停止1回の'C') */
    int c_count = 0;
    for (size_t i = 0; i < g_sensor_tx_len; i++) {
        if (g_sensor_tx[i] == 'C') c_count++;
    }
    ASSERT_TRUE(c_count >= 1); /* 停止トグル(開始分はreset_capture前) */
}

static void test_breath_ready_timeout_aborts_with_reason(void)
{
    breath_session_to_ready();
    /* 呼気が来ないままREADYタイムアウト。EVT_DATAが1Hzで流れ続けるため
     * 捕捉バッファ溢れを避けて毎秒リセットし、逐次カウントする */
    int no_breath = 0, aborted_phase = 0;
    uint32_t deadline = g_t + CFG_BAP_READY_TIMEOUT_MS + 2000U;
    while (g_t < deadline && g_sm.state == SM_READY) {
        reset_capture();
        feed_quiet(1, 800);
        no_breath += count_errors_of(E_NO_BREATH);
        const hpp_frame_t *ph = last_frame_of(HPP_EVT_PHASE);
        if (ph != NULL && ph->payload[0] == HPP_PHASE_ABORTED) {
            aborted_phase++;
        }
    }
    ASSERT_EQ(g_sm.state, SM_IDLE);
    ASSERT_EQ(no_breath, 1);
    ASSERT_EQ(aborted_phase, 1);
}

static void test_breath_low_quality_auto_retry_once(void)
{
    breath_session_to_ready();
    reset_capture();

    /* 低品質呼気: RH上昇なし + 孤立スパイク4発(外れ値率超過) */
    int32_t rise[] = {2300, 3400, 4600, 5600, 6400, 6800};
    for (int i = 0; i < 6; i++) feed_line(rise[i], 4010);
    ASSERT_EQ(g_sm.state, SM_BREATH);
    for (int i = 0; i < 4; i++) {
        feed_line(25000, 4010);           /* 孤立スパイク */
        feed_line(6800, 4010);
        feed_line(6750, 4010);
    }
    for (int i = 0; i < 12 && g_sm.state == SM_BREATH; i++) {
        feed_line(850, 4010);
    }
    sm_tick(&g_sm, ++g_t); /* ANALYZE */
    sm_tick(&g_sm, ++g_t); /* VALIDATE → 自動再測定 */
    ASSERT_EQ(g_sm.state, SM_READY);
    ASSERT_EQ(g_sm.bap.retries, 1);
    const hpp_frame_t *ph = last_frame_of(HPP_EVT_PHASE);
    ASSERT_TRUE(ph != NULL);
    ASSERT_EQ(ph->payload[0], HPP_PHASE_RETRY);

    /* 2回目も低品質 → 再々測定はせず、推奨フラグ付きで報告 */
    reset_capture();
    for (int i = 0; i < 6; i++) feed_line(rise[i], 4010);
    for (int i = 0; i < 4; i++) {
        feed_line(25000, 4010);
        feed_line(6800, 4010);
        feed_line(6750, 4010);
    }
    for (int i = 0; i < 12 && g_sm.state == SM_BREATH; i++) {
        feed_line(850, 4010);
    }
    for (int i = 0; i < 4; i++) sm_tick(&g_sm, ++g_t);
    ASSERT_EQ(g_sm.state, SM_IDLE);
    const hpp_frame_t *r = last_frame_of(HPP_EVT_RESULT);
    ASSERT_TRUE(r != NULL);
    ASSERT_TRUE((r->payload[3] & 0x01) != 0); /* REMEASURE */
    ASSERT_TRUE((r->payload[3] & 0x08) != 0); /* RETRIED */
}

static void test_result_arq_redelivers_until_acked(void)
{
    breath_session_to_ready();

    int32_t rise[] = {2300, 3400, 4600, 5600, 6400, 6800};
    for (int i = 0; i < 6; i++) feed_line(rise[i], 4600);
    for (int i = 0; i < 12; i++) feed_line(6800 + ((i & 1) ? 100 : -100), 4600);
    for (int i = 0; i < 12 && g_sm.state == SM_BREATH; i++) {
        feed_line(850, 4600);
    }
    reset_capture();
    for (int i = 0; i < 4; i++) sm_tick(&g_sm, ++g_t);
    ASSERT_EQ(count_of(HPP_EVT_RESULT), 1); /* 初回送信 */
    const hpp_frame_t *r1 = last_frame_of(HPP_EVT_RESULT);
    uint8_t seq = r1->seq;

    /* ACKが来ない(切断相当) → 同一SEQで再送される */
    sm_tick(&g_sm, g_t + CFG_ARQ_TIMEOUT_MS + 10U);
    ASSERT_EQ(count_of(HPP_EVT_RESULT), 2);
    const hpp_frame_t *r2 = last_frame_of(HPP_EVT_RESULT);
    ASSERT_EQ(r2->seq, seq);

    /* アプリがACK_EVT → 以後再送されない */
    uint8_t ack_seq = seq;
    inject_cmd(HPP_CMD_ACK_EVT, &ack_seq, 1, g_t + CFG_ARQ_TIMEOUT_MS + 20U);
    sm_tick(&g_sm, g_t + 5U * CFG_ARQ_TIMEOUT_MS);
    ASSERT_EQ(count_of(HPP_EVT_RESULT), 2);
}

static void test_breath_stop_command_aborts_safely(void)
{
    breath_session_to_ready();
    reset_capture();
    inject_cmd(HPP_CMD_STOP, NULL, 0, g_t + 100U);
    ASSERT_EQ(g_sm.state, SM_IDLE);
    ASSERT_TRUE(last_frame_of(HPP_ACK) != NULL);
    /* 部分結果は送らない(破棄) */
    ASSERT_EQ(count_of(HPP_EVT_RESULT), 0);
    /* センサの連続測定は停止トグル済み */
    ASSERT_TRUE(strchr(g_sensor_tx, 'C') != NULL);
}

static void test_breath_rejected_when_busy(void)
{
    setup(0);
    sm_on_sensor_line(&g_sm, VALID_LINE, 100);
    uint8_t iv = 1;
    inject_cmd(HPP_CMD_START_CONT, &iv, 1, 200); /* ラボモード実行中 */
    reset_capture();
    inject_cmd(HPP_CMD_BREATH, NULL, 0, 300);
    const hpp_frame_t *nak = last_frame_of(HPP_NAK);
    ASSERT_TRUE(nak != NULL);
    ASSERT_EQ(nak->payload[1], E_BUSY);
}

int main(void)
{
    printf("test_state_machine\n");
    test_boot_sends_wake_and_single();
    test_sensor_init_to_idle_captures_sn();
    test_sensor_init_timeout_to_error();
    test_start_continuous_sends_C_and_acks();
    test_start_rejected_when_not_idle();
    test_invalid_interval_rejected();
    test_measuring_emits_data_and_summary();
    test_start_confirm_retry_ladder();
    test_ble_inactivity_stops_and_sleeps();
    test_session_cap_30min();
    test_sleep_wake_via_frame();
    test_idle_auto_sleep();
    test_error_auto_sleep();
    test_error_recovery_via_wake_sends_reset();
    test_idle_heals_unexpected_stream();
    test_zero_calibration_only_in_idle();
    test_low_battery_notified_once_without_aborting();
    test_parse_failure_storm_stops_measurement();
    /* v2: 呼気セッション */
    test_breath_full_flow_emits_result();
    test_breath_ready_timeout_aborts_with_reason();
    test_breath_low_quality_auto_retry_once();
    test_result_arq_redelivers_until_acked();
    test_breath_stop_command_aborts_safely();
    test_breath_rejected_when_busy();
    return TEST_SUMMARY();
}
