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
    ASSERT_EQ(st->len, 12); /* 拡張ステータス(診断統計込み) */
    ASSERT_EQ(hpp_get_u16(&st->payload[1]), 3700); /* battery */
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
    return TEST_SUMMARY();
}
