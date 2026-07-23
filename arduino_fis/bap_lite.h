/**
 * @file  bap_lite.h
 * @brief 半導体式(MOS)向け 呼気解析パイプライン(軽量版)。
 *        STM32版 BAP の思想(平滑化/ベースライン学習/onset-offset/特徴量/採点)を
 *        MOSセンサの連続抵抗値 Rs 用に float で移植。ハード非依存＝ホスト検証可能。
 *
 * 入力: センサ抵抗 Rs[Ω] (1サンプル)。
 * 内部信号: response r = R0 / Rs (清浄大気で ~1.0、H2上昇でRs減 → r増)。
 *   MOSはRsが濃度上昇で減少するため、r を「立ち上がる呼気信号」として扱う。
 * パイプライン: EMA平滑 → quiet窓でR0学習/ドリフト補償 → onset/offset →
 *              特徴量(peak/AUC/rise/duration) → Q(測定)/C(計測器) 減点採点。
 */
#ifndef HP_BAP_LITE_H
#define HP_BAP_LITE_H

#include <stdint.h>
#include <stdbool.h>

typedef enum { BAPL_WARMING = 0, BAPL_READY, BAPL_BREATH, BAPL_DONE } bapl_phase_t;
typedef enum { BAPL_EVT_NONE = 0, BAPL_EVT_R0_LOCKED, BAPL_EVT_READY,
               BAPL_EVT_ONSET, BAPL_EVT_OFFSET } bapl_evt_t;

/* result flags (HPP EVT_RESULT と同じビット意味を踏襲) */
#define BAPL_RF_REMEASURE   0x01u
#define BAPL_RF_TRUNCATED   0x04u
#define BAPL_RF_WARMUP_OK   0x10u

typedef struct {
    uint8_t  session_id;
    uint8_t  quality;      /* 0-100 この測定は信頼できるか */
    uint8_t  confidence;   /* 0-100 この計測器は健全か */
    uint8_t  flags;        /* BAPL_RF_* */
    float    r0_ohm;       /* 清浄大気ベースライン Rs */
    float    peak_r;       /* ベースラインからの最大 response (>=1) */
    float    rs_min_ohm;   /* 呼気中の最小 Rs */
    float    auc;          /* Σ(r-1)·dt [·s] 総排出量に比例 */
    uint16_t rise_ds;      /* onset→peak [0.1s] */
    uint16_t duration_ds;  /* onset→offset [0.1s] */
} bapl_result_t;

typedef struct {
    bapl_phase_t phase;
    uint8_t  session_id;
    bool     already_warm;
    uint8_t  retries;

    /* 時刻 */
    uint32_t start_ms;
    uint32_t last_ms;

    /* EMA (Rsドメイン) */
    float    y_rs;
    bool     y_init;

    /* ベースライン R0 (清浄大気 Rs) */
    float    r0;
    bool     r0_locked;
    uint8_t  quiet_run;

    /* 静穏判定用の直近 r 窓 */
    float    win[8];
    uint8_t  win_n, win_i;

    /* セグメンテーション */
    uint8_t  onset_run, offset_run;
    uint32_t onset_ms, offset_ms, peak_ms;

    /* 呼気捕捉 */
    float    peak_r;
    float    rs_min;
    double   auc;
    uint16_t breath_samples;
    bool     truncated;

    /* 計測器健全性の集計 */
    uint16_t samples_total;
    uint16_t invalid_samples;
} bapl_t;

void       bapl_init(bapl_t *b, uint8_t session_id, uint32_t now_ms, bool already_warm);
void       bapl_begin_retry(bapl_t *b, uint32_t now_ms);
bapl_evt_t bapl_on_sample(bapl_t *b, float rs_ohm, bool valid, uint32_t now_ms);
float      bapl_response(const bapl_t *b);   /* 現在の r = R0 / EMA(Rs) */
float      bapl_baseline_rs(const bapl_t *b);
void       bapl_finalize(const bapl_t *b, bapl_result_t *out);

#endif /* HP_BAP_LITE_H */
