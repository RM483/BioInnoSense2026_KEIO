/**
 * @file  bap.h
 * @brief HydroPaw Breath Analysis Pipeline (BAP)。
 *        呼気イベントの検出・切り出し・特徴量抽出・採点をセンサノード上で
 *        完結させるエッジ処理系。設計根拠は docs/18_algorithm_design.md。
 *
 *        HAL非依存・全整数演算(Q8固定小数)・malloc不使用。
 *        ホストPCでゴールデンベクタ検証可能 (Tests/test_bap.c)。
 *
 * パイプライン:
 *   [S1] Hampel(median/MAD, w=5)  スパイク除去
 *   [S2] 適応EMA(innovation-gated) 平滑化と追従の両立
 *   [S3] quiet-windowベースライン学習  ドリフト補償
 *   [S4] onset/offset呼気セグメンテーション
 *   [S5] 特徴量: peak/plateau/AUC/rise/duration
 *   [S6] 品質Q(この測定) / [S7] 信頼度C(この計測器) — 減点方式
 */
#ifndef BAP_H
#define BAP_H

#include <stdint.h>
#include <stdbool.h>

/** 呼気捕捉バッファ長 [サンプル≒秒]。CFG_BAP_BREATH_MAX_S 以上であること */
#define BAP_BUF_MAX      96U
#define BAP_HAMPEL_W     5U

/** パイプラインのフェーズ */
typedef enum {
    BAP_PHASE_WARMING = 0, /**< ベースライン学習中(ウォームアップ含む) */
    BAP_PHASE_READY   = 1, /**< 呼気待ち(onset監視) */
    BAP_PHASE_BREATH  = 2, /**< 呼気捕捉中 */
    BAP_PHASE_DONE    = 3, /**< offset確定(finalize待ち) */
} bap_phase_t;

/** bap_on_sample() が報告するイベント */
typedef enum {
    BAP_EVT_NONE = 0,
    BAP_EVT_BASELINE_LOCKED, /**< ベースライン安定(READY遷移可) */
    BAP_EVT_ONSET,           /**< 呼気開始を検出 */
    BAP_EVT_OFFSET,          /**< 呼気終了を検出(結果はbap_finalizeで) */
} bap_evt_t;

/* ---- EVT_RESULT flags ---- */
#define BAP_RF_REMEASURE   0x01U /**< 低品質 — 再測定を推奨 */
#define BAP_RF_RH_OK       0x02U /**< 湿度上昇による呼気裏付けあり */
#define BAP_RF_TRUNCATED   0x04U /**< 捕捉窓上限で打ち切り */
#define BAP_RF_RETRIED     0x08U /**< 自動再測定を実施済み */
#define BAP_RF_WARMUP_OK   0x10U /**< ウォームアップ完了後の測定 */
#define BAP_RF_LOW_BATT    0x20U /**< 測定中に低電池 */

/** 呼気1回の解析結果 (HPP EVT_RESULT 0x86 と1:1) */
typedef struct {
    uint8_t  session_id;
    uint8_t  quality;      /**< Q: 0-100 この測定は信頼できるか */
    uint8_t  confidence;   /**< C: 0-100 この計測器は健全か */
    uint8_t  flags;        /**< BAP_RF_* */
    int32_t  baseline_ppb;
    int32_t  peak_ppb;     /**< ベースラインからの最大上昇 */
    int32_t  plateau_ppb;  /**< peak/2以上のサンプル平均(外乱に強い代表値) */
    uint32_t auc_ppb_s;    /**< ΣΔ·1s — 総排出量に比例 */
    uint16_t rise_ds;      /**< 10%→90%立上り [0.1s] */
    uint16_t duration_ds;  /**< onset→offset [0.1s] */
    int16_t  temp_c10_mean;/**< 呼気中平均温度 [0.1℃] */
    int16_t  rh10_delta;   /**< 呼気中の湿度上昇 [0.1%RH] */
    uint16_t pre_mad_ppb;  /**< 呼気直前のベースラインMAD(ノイズ指標) */
} bap_result_t;

/** 計測器健全性の入力(状態機械がセッション中に集計して渡す) */
typedef struct {
    uint16_t parse_errors;   /**< CSVパース失敗回数 */
    uint16_t samples_total;  /**< 受理サンプル総数 */
    uint8_t  stuck_events;   /**< 固着フラグ発生回数 */
    uint8_t  sensor_retries; /**< センサ無応答での再試行回数 */
    bool     temp_out_of_comp; /**< 温度補償範囲(-20〜40℃)逸脱があった */
    uint16_t crc_errors;     /**< セッション中のHPP CRCエラー */
} bap_health_t;

typedef struct {
    bap_phase_t phase;
    uint8_t  session_id;
    bool     warmup_done;    /**< 呼気開始時点のウォームアップ完了状態 */
    bool     low_batt;
    uint8_t  retries;        /**< 自動再測定回数(最大1) */

    /* S1: Hampel窓 + 持続性判定
     * (同方向2連続の逸脱=本物のステップ → 置換せず受理する) */
    int32_t  win[BAP_HAMPEL_W];
    uint8_t  win_n, win_i;
    int8_t   prev_dev_sign;  /**< 直前サンプルの逸脱方向(0=逸脱なし) */
    uint16_t outliers;       /**< Hampel置換回数(セッション累計) */
    uint16_t samples;        /**< 供給サンプル数(セッション累計) */

    /* S2: 適応EMA (Q8) */
    int32_t  y_q8;
    bool     y_init;

    /* S3: ベースライン (Q8)。
     * 更新ゲート = 窓が静穏 ∧ Δがonset閾値の半分未満。
     * (プラトーは「静穏だが高い」ため、静穏だけでは汚染される) */
    int32_t  baseline_q8;
    bool     baseline_init;
    bool     baseline_locked;
    uint8_t  quiet_run;
    uint16_t rh10_ambient;   /**< 静穏時のRH(呼気RH上昇の基準) */
    uint16_t quiet_mad_ppb;  /**< 静穏時の窓MAD(呼気前ノイズ指標) */

    /* S4: セグメンテーション */
    uint8_t  onset_run, offset_run;
    int32_t  pending[BAP_HAMPEL_W]; /**< onset判定中のΔ(呼気先頭に含める) */
    uint32_t onset_ms, offset_ms;
    uint16_t pre_mad_ppb;    /**< onset時点の窓MADスナップショット */

    /* S5: 呼気捕捉 */
    int32_t  buf[BAP_BUF_MAX]; /**< Δ[ppb] 1Hz */
    uint8_t  buf_n;
    int32_t  peak;
    bool     truncated;
    uint16_t rh10_base, rh10_max;
    int32_t  temp_sum_c10;
    uint16_t breath_samples;
} bap_t;

/** セッション開始。warmup_done = センサ通電からCFG_WARMUP_MS経過済みか */
void bap_init(bap_t *b, uint8_t session_id, bool warmup_done);

/** 低品質による自動再測定: 捕捉のみリセット(フィルタ/ベースラインは維持) */
void bap_begin_retry(bap_t *b, uint32_t now_ms);

/**
 * @brief 検証済みサンプルを1つ供給する(1Hz想定)。
 * @return フェーズ遷移イベント(なければ BAP_EVT_NONE)
 */
bap_evt_t bap_on_sample(bap_t *b, int32_t ppb, int16_t temp_c10,
                        uint16_t rh10, uint32_t now_ms);

/** 現在のフィルタ済みΔ [ppb](ライブ表示・ストリーミング用, 負は0) */
int32_t bap_delta_ppb(const bap_t *b);

/** 現在のベースライン [ppb] */
int32_t bap_baseline_ppb(const bap_t *b);

/**
 * @brief OFFSET後に呼ぶ。特徴量抽出+Q/C採点し結果を返す(純関数的)。
 *        docs/18 §S5-S7 の定義と減点表に厳密に従う。
 */
void bap_finalize(const bap_t *b, const bap_health_t *h, bap_result_t *out);

#endif /* BAP_H */
