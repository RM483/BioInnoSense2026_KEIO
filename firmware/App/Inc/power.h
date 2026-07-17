/**
 * @file  power.h
 * @brief 低消費電力制御(STOP2)と電池電圧測定。HAL依存モジュール。
 */
#ifndef POWER_H
#define POWER_H

#include <stdint.h>

/**
 * IWDGをStop/Standby中にフリーズさせるオプションバイトを保証する。
 * 未設定なら書き換えてシステムリセットする(初回起動時に一度だけ発生)。
 * IWDG起動前(MX_IWDG_Init前)に呼ぶこと。
 */
void power_option_bytes_ensure(void);

/** STOP2へ移行し、USART2 RX(スタートビット)で復帰後にクロックを再構成する。 */
void power_enter_stop2(void);

/** 電池電圧 [mV] を返す(ADC1 IN9, 外部1/2分圧)。 */
uint16_t power_read_battery_mv(void);

#endif /* POWER_H */
