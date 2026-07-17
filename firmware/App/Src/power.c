/** @file power.c */
#include "stm32l4xx_hal.h"
#include "power.h"
#include "main.h"

extern ADC_HandleTypeDef hadc1;
extern UART_HandleTypeDef huart2;

void power_enter_stop2(void)
{
    /* USART2をStop2からのWakeupソースに設定 (RXD立ち上がりで復帰) */
    UART_WakeUpTypeDef wake = { .WakeUpEvent = UART_WAKEUP_ON_STARTBIT };
    HAL_UARTEx_StopModeWakeUpSourceConfig(&huart2, wake);
    HAL_UARTEx_EnableStopMode(&huart2);

    HAL_SuspendTick();
    HAL_PWREx_EnterSTOP2Mode(PWR_STOPENTRY_WFI);

    /* ---- ここから復帰後 ---- */
    SystemClock_Config();  /* main.c定義。HSI16を再選択 */
    HAL_ResumeTick();
    HAL_UARTEx_DisableStopMode(&huart2);
}

uint16_t power_read_battery_mv(void)
{
    if (HAL_ADC_Start(&hadc1) != HAL_OK) {
        return 0;
    }
    if (HAL_ADC_PollForConversion(&hadc1, 10) != HAL_OK) {
        HAL_ADC_Stop(&hadc1);
        return 0;
    }
    uint32_t raw = HAL_ADC_GetValue(&hadc1);
    HAL_ADC_Stop(&hadc1);
    /* 12bit, VREF=3.3V, 外部1/2分圧 → mV = raw*3300/4095*2 */
    return (uint16_t)((raw * 3300U * 2U) / 4095U);
}
