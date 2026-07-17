/**
 * @file  main.h
 * @brief CubeMX生成相当のメインヘッダ。
 */
#ifndef __MAIN_H
#define __MAIN_H

#ifdef __cplusplus
extern "C" {
#endif

#include "stm32l4xx_hal.h"

void Error_Handler(void);
void SystemClock_Config(void);

/* GPIO割当 (docs/04参照) */
#define LED_STATUS_Pin        GPIO_PIN_0
#define LED_STATUS_GPIO_Port  GPIOB
#define SENSOR_PWR_Pin        GPIO_PIN_8
#define SENSOR_PWR_GPIO_Port  GPIOA

#ifdef __cplusplus
}
#endif
#endif /* __MAIN_H */
