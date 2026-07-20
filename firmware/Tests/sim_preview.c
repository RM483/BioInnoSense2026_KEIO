/**
 * @file sim_preview.c
 * @brief HYDROPAW_SIM_SENSOR の合成呼気カーブを、実機と同じ state_machine+bap
 *        に流して「初期化→WARMUP→READY→BREATH→ANALYZE→VALIDATE→REPORT」まで
 *        到達し、EVT_RESULT(Q/C/peak/…)が生成されるかをホストで先行検証する。
 *
 *        これは実機に焼く前の妥当性チェック(ゴールデンではなくプレビュー)。
 *        main.c の sim_tick() と同じスクリプトを再現している。
 *
 *        ビルド: gcc -DHYDROPAW_SIM_SENSOR ...(Makefile sim_preview ターゲット)
 */
#include <stdio.h>
#include <string.h>
#include "state_machine.h"
#include "app_config.h"

/* ---- 送信捕捉 ---- */
static hpp_frame_t   g_frames[128];
static int           g_frame_count;
static hpp_decoder_t g_ble_dec;

static void ble_tx(const uint8_t *d, size_t n)
{
    hpp_frame_t f;
    for (size_t i = 0; i < n; i++) {
        if (hpp_decoder_feed(&g_ble_dec, d[i], &f) && g_frame_count < 128) {
            g_frames[g_frame_count++] = f;
        }
    }
}
static void sensor_tx(const uint8_t *d, size_t n) { (void)d; (void)n; }
static uint16_t batt_mv(void) { return 3700; }

static dgs2_t     g_sensor;
static ble_link_t g_link;
static sm_t       g_sm;

/* ---- 合成呼気カーブ (ベースラインからのΔ[ppb]) : main.c と一致させる ---- */
static const int32_t SIM_BREATH[] = {
    800, 1800, 3000, 4000, 4200, 4200, 4100, 4200, 4000, 3000, 1500, 700, 250, 100
};
#define SIM_BREATH_N (int)(sizeof(SIM_BREATH) / sizeof(SIM_BREATH[0]))
#define SIM_BASE_PPB    1000
#define SIM_TEMP_C100   2500
#define SIM_RH_BASE100  5000

static void make_line(char *out, size_t n, int32_t ppb, int rh100)
{
    snprintf(out, n, "SIM000000001, %ld, %d, %d, 32000, 26000, 20000",
             (long)ppb, SIM_TEMP_C100, rh100);
}

static const char *STATE_NAME(sm_state_t s)
{
    switch (s) {
    case SM_BOOT: return "BOOT";
    case SM_SENSOR_INIT: return "SENSOR_INIT";
    case SM_IDLE: return "IDLE";
    case SM_MEASURING: return "MEASURING";
    case SM_SLEEP: return "SLEEP";
    case SM_ERROR: return "ERROR";
    case SM_WARMUP: return "WARMUP";
    case SM_READY: return "READY";
    case SM_BREATH: return "BREATH";
    case SM_ANALYZE: return "ANALYZE";
    case SM_VALIDATE: return "VALIDATE";
    case SM_REPORT: return "REPORT";
    default: return "?";
    }
}

int main(void)
{
    hpp_decoder_init(&g_ble_dec);
    dgs2_init(&g_sensor, sensor_tx);
    ble_link_init(&g_link, ble_tx);

    uint32_t now = 1000;
    sm_init(&g_sm, &g_sensor, &g_link, batt_mv, now);

    char line[DGS2_LINE_MAX];
    /* 1) センサ初期化: 1行でSENSOR_INIT→IDLE */
    now += 500;
    make_line(line, sizeof line, SIM_BASE_PPB, SIM_RH_BASE100);
    sm_on_sensor_line(&g_sm, line, now);
    printf("t=%.1fs  init -> %s\n", now / 1000.0, STATE_NAME(g_sm.state));

    /* 2) CMD_BREATH注入 */
    hpp_frame_t f = {0};
    f.type = HPP_CMD_BREATH; f.len = 0;
    sm_on_frame(&g_sm, &f, now);
    printf("t=%.1fs  CMD_BREATH -> %s\n", now / 1000.0, STATE_NAME(g_sm.state));

    sm_state_t last = g_sm.state;
    int idx = 0;
    int ready_dwell = 0;
    int breath_started = 0;

    for (int step = 0; step < 60; step++) {
        now += 1000;

        /* READY遷移(初回/再測定)を検出したらカーブを頭出し */
        if (g_sm.state == SM_READY && last != SM_READY) {
            idx = 0; ready_dwell = 0; breath_started = 0;
        }
        last = g_sm.state;

        int rh = SIM_RH_BASE100;
        int32_t ppb = SIM_BASE_PPB;
        int feed = 1;

        if (g_sm.state == SM_WARMUP) {
            ppb = SIM_BASE_PPB + (((now / 1000) & 1) ? 20 : -20);
        } else if (g_sm.state == SM_READY || g_sm.state == SM_BREATH) {
            if (!breath_started) {
                if (ready_dwell < 2) {
                    ready_dwell++;
                    ppb = SIM_BASE_PPB;
                } else {
                    breath_started = 1;
                }
            }
            if (breath_started) {
                if (idx < SIM_BREATH_N) {
                    int32_t d = SIM_BREATH[idx++];
                    ppb = SIM_BASE_PPB + d;
                    if (d > 1000) rh = SIM_RH_BASE100 + 1200; /* 呼気で湿度上昇 */
                } else {
                    ppb = SIM_BASE_PPB + 50 + (((now / 1000) & 1) ? 10 : -10);
                }
            }
        } else {
            feed = 0; /* ANALYZE/VALIDATE/REPORT/IDLE: sm_tickが進める */
        }

        if (feed) {
            make_line(line, sizeof line, ppb, rh);
            sm_on_sensor_line(&g_sm, line, now);
        }
        sm_tick(&g_sm, now);

        if (g_sm.state != last) {
            printf("t=%.1fs  %s -> %s%s\n", now / 1000.0,
                   STATE_NAME(last), STATE_NAME(g_sm.state),
                   feed ? "" : " (tick)");
        }
        if (g_sm.state == SM_IDLE && last == SM_REPORT) {
            break; /* セッション完了 */
        }
    }

    /* 結果フレーム(EVT_RESULT=0x86)を探す */
    const hpp_frame_t *res = NULL;
    for (int i = g_frame_count - 1; i >= 0; i--) {
        if (g_frames[i].type == HPP_EVT_RESULT) { res = &g_frames[i]; break; }
    }
    printf("\n---- 結果 ----\n");
    if (!res) {
        printf("EVT_RESULT が生成されませんでした (NG)\n");
        return 1;
    }
    const uint8_t *p = res->payload;
    uint8_t q = p[1], c = p[2], flags = p[3];
    int32_t peak = (int32_t)hpp_get_u32(&p[8]);
    uint16_t rise = hpp_get_u16(&p[20]);
    uint16_t dur  = hpp_get_u16(&p[22]);
    int16_t rhd   = (int16_t)hpp_get_u16(&p[26]);
    printf("Quality=%u  Confidence=%u  flags=0x%02X\n", q, c, flags);
    printf("peak=%d ppb  rise=%.1fs  duration=%.1fs  rh_delta=%.1f%%\n",
           peak, rise / 10.0, dur / 10.0, rhd / 10.0);
    printf("RH裏付け(RF_RH_OK)=%s  再測定推奨(REMEASURE)=%s\n",
           (flags & BAP_RF_RH_OK) ? "yes" : "no",
           (flags & BAP_RF_REMEASURE) ? "yes" : "no");
    printf("\nOK: 一連の経路(初期化→呼気検出→解析→採点→BLE送信)が成立\n");
    return 0;
}
