/** @file power.c
 *  @brief 低消費電力制御(STOP2)・オプションバイト・電池電圧測定。HAL依存。
 */
#include "stm32l4xx_hal.h"
#include "power.h"
#include "main.h"

extern ADC_HandleTypeDef hadc1;
extern UART_HandleTypeDef huart2;

void power_option_bytes_ensure(void)
{
    /* STM32L4のIWDGはオプションバイト既定値(IWDG_STOP/IWDG_STDBY=1)では
     * Stopモード中もカウントを続ける。SLEEP(STOP2)は数分に及ぶため、
     * そのままではIWDG(約8.2s)がSleep中にリセットを引き起こす。
     * → 初回起動時に一度だけ FREEZE へ書き換える(書換え後は自動リセット)。 */
    FLASH_OBProgramInitTypeDef ob = {0};
    HAL_FLASHEx_OBGetConfig(&ob);

    const uint32_t running_in_lp =
        ob.USERConfig & (FLASH_OPTR_IWDG_STOP | FLASH_OPTR_IWDG_STDBY);
    if (running_in_lp == 0U) {
        return; /* 既にFREEZE済み(通常パス) */
    }

    if (HAL_FLASH_Unlock() != HAL_OK) {
        return; /* 書換え不可でも動作は継続(Sleep中リセットのリスクは残る) */
    }
    if (HAL_FLASH_OB_Unlock() != HAL_OK) {
        HAL_FLASH_Lock();
        return;
    }

    FLASH_OBProgramInitTypeDef prog = {0};
    prog.OptionType = OPTIONBYTE_USER;
    prog.USERType   = OB_USER_IWDG_STOP | OB_USER_IWDG_STDBY;
    prog.USERConfig = OB_IWDG_STOP_FREEZE | OB_IWDG_STDBY_FREEZE;
    if (HAL_FLASHEx_OBProgram(&prog) == HAL_OK) {
        /* オプションバイト再ロード → システムリセット(ここから先へは戻らない) */
        HAL_FLASH_OB_Launch();
    }
    HAL_FLASH_OB_Lock();
    HAL_FLASH_Lock();
}

void power_enter_stop2(void)
{
    /* USART2をStop2からのWakeupソースに設定 (RXDスタートビットで復帰)。
     * USART2カーネルクロックはHSI16(SystemClock_Config/CubeMX設定)のため
     * Stop中も受信スタートビット検出でHSIが自動起動する。 */
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
    /* 12bit, VREF=3.3V(基板固定), 外部1/2分圧 → mV = raw*3300/4095*2 */
    return (uint16_t)((raw * 3300U * 2U) / 4095U);
}
