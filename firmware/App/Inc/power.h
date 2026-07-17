/**
 * @file  power.h
 * @brief 低消費電力制御(STOP2)と電池電圧測定。HAL依存モジュール。
 */
#ifndef POWER_H
#define POWER_H

#include <stdbool.h>
#include <stdint.h>

/**
 * IWDGをStop/Standby中にフリーズさせるオプションバイトを保証する。
 * 未設定なら書き換えてシステムリセットする(初回起動時に一度だけ発生)。
 * IWDG起動前(MX_IWDG_Init前)に呼ぶこと。
 */
void power_option_bytes_ensure(void);

/**
 * IWDGがStopモード中フリーズする設定になっているか(オプションバイト)。
 * falseのままSTOP2へ入ると約8.2秒毎にIWDGリセットが発生するため、
 * mainはこの関数がtrueの場合のみSTOP2を実行すること。
 */
bool power_iwdg_frozen_in_stop(void);

/** STOP2へ移行し、USART2 RX(スタートビット)で復帰後にクロックを再構成する。 */
void power_enter_stop2(void);

/** 電池電圧 [mV] を返す(ADC1 IN9, 外部1/2分圧)。 */
uint16_t power_read_battery_mv(void);

#endif /* POWER_H */
