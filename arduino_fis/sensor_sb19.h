/**
 * @file  sensor_sb19.h
 * @brief FIS SB-19-00 (SnO2 半導体式 H2 センサ) の読み出し変換。
 *        ADC生値 → 分圧比 → センサ抵抗 Rs[Ω]。純関数(ハード非依存)なので
 *        ホストPCでも検証できる。ヒータ(VH=0.9V)は外部LT3080が常時供給する。
 *
 * 回路: VC — Rs — (VS節点) — RL — GND。電圧フォロワ+RCを介してVSをADCへ。
 *   VS = VC * RL/(Rs+RL)  ⇒  Rs = RL * (VC/VS - 1)
 *   ADC基準=VC(AVCC)なら ratio=adc/ADC_MAX=VS/VC で VC がキャンセル(電源変動補正)。
 *   Rs = RL * (1/ratio - 1)
 * Rsは水素濃度の上昇とともに「減少」する(SB1900J ガス感度特性)。
 */
#ifndef HP_SENSOR_SB19_H
#define HP_SENSOR_SB19_H

#include <stdint.h>
#include <stdbool.h>
#include "config.h"

/** ADC生値(0..ADC_MAX)から比率(VS/VC)を返す。0/1近傍はクランプ。 */
static inline float sb19_ratio(uint16_t adc) {
    float r = (float)adc / ADC_MAX;
    if (r < 0.0005f) r = 0.0005f;   /* Rs→∞ 防止 */
    if (r > 0.9995f) r = 0.9995f;   /* Rs→0 防止 */
    return r;
}

/** ADC生値からセンサ抵抗 Rs[Ω] を算出(ratiometric)。 */
static inline float sb19_rs_ohm(uint16_t adc) {
#if USE_RATIOMETRIC
    float ratio = sb19_ratio(adc);
    return RL_OHM * (1.0f / ratio - 1.0f);
#else
    float vs = (float)adc / ADC_MAX * VC_VOLT;
    if (vs < 0.001f) vs = 0.001f;
    return RL_OHM * (VC_VOLT / vs - 1.0f);
#endif
}

/** Rs が健全レンジ内か(断線=∞側, 短絡/飽和=0側 を弾く)。 */
static inline bool sb19_rs_valid(float rs) {
    return (rs >= RS_MIN_OHM) && (rs <= RS_MAX_OHM);
}

#endif /* HP_SENSOR_SB19_H */
