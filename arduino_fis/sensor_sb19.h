/**
 * @file  sensor_sb19.h
 * @brief FIS SB-19-00 (SnO2 半導体式 H2 センサ) の読み出し変換。
 *        ADC生値 → 分圧比 → センサ抵抗 Rs[Ω]。純関数(ハード非依存)なので
 *        ホストPCでも検証できる。ヒータ(VH=0.9V)は外部LT3080が常時供給する。
 *
 * 回路(config.h の RL_HIGH_SIDE で切替):
 *  [RL_HIGH_SIDE=1] 実機: VC — RL — (VS節点) — Rs — ≈VMID(ヒーター中点)。
 *      VS = VMID + (VC−VMID)·Rs/(Rs+RL)
 *      ⇒ Rs = RL·(ratio − VMID/VC)/(1 − ratio),  ratio = VS/VC
 *      H2↑(Rs↓)で VS は下がる。
 *  [RL_HIGH_SIDE=0] 旧図: VC — Rs — (VS節点) — RL — GND。
 *      Rs = RL·(1/ratio − 1)。H2↑で VS は上がる。
 * いずれも ADC基準=VC(AVCC) なら ratio=adc/ADC_MAX で VC がキャンセル(ratiometric)。
 * Rsは水素濃度の上昇とともに「減少」する(SB1900J ガス感度特性)。
 */
#ifndef HP_SENSOR_SB19_H
#define HP_SENSOR_SB19_H

#include <stdint.h>
#include <stdbool.h>
#include <math.h>
#include "config.h"

/** ADC生値(0..ADC_MAX)から比率(VS/VC)を返す。0/1近傍はクランプ。 */
static inline float sb19_ratio(uint16_t adc) {
    float r = (float)adc / ADC_MAX;
    if (r < 0.0005f) r = 0.0005f;   /* Rs→∞ 防止 */
    if (r > 0.9995f) r = 0.9995f;   /* Rs→0 防止 */
    return r;
}

/** ADC生値からセンサ抵抗 Rs[Ω] を算出。 */
static inline float sb19_rs_ohm(uint16_t adc) {
#if USE_RATIOMETRIC
    float ratio = sb19_ratio(adc);
#else
    float vs = (float)adc / ADC_MAX * VC_VOLT;
    float ratio = vs / VC_VOLT;
    if (ratio < 0.0005f) ratio = 0.0005f;
    if (ratio > 0.9995f) ratio = 0.9995f;
#endif
#if RL_HIGH_SIDE
    /* 実機: RLが5V側。Rs = RL·(ratio − vm)/(1 − ratio), vm=VMID/VC */
    float num = ratio - (VMID_VOLT / VC_VOLT);
    if (num < 0.0005f) num = 0.0005f;    /* Rs→0 側クランプ */
    return RL_OHM * num / (1.0f - ratio);
#else
    /* 旧図: Rsが5V側。 */
    return RL_OHM * (1.0f / ratio - 1.0f);
#endif
}

/** Rs が健全レンジ内か(断線=∞側, 短絡/飽和=0側 を弾く)。 */
static inline bool sb19_rs_valid(float rs) {
    return (rs >= RS_MIN_OHM) && (rs <= RS_MAX_OHM);
}

#if SB19_PPM_ENABLE
/** Rs[Ω] → 水素濃度[ppm]。
 *  データシート(SB1900J)の「両対数で直線」モデルに基づく:
 *      C = 100 × (Rs / Rs100)^(−1/α)
 *  精度は config.h の SB19_RS100_OHM / SB19_ALPHA に依存する。
 *  典型値仮置き(PROVISIONAL)の間は±数倍の目安値であることに注意。 */
static inline float sb19_ppm(float rs) {
    if (rs < 1.0f) rs = 1.0f;   /* powfの発散防止 */
    return 100.0f * powf(rs / SB19_RS100_OHM, -1.0f / SB19_ALPHA);
}
#endif

#endif /* HP_SENSOR_SB19_H */
