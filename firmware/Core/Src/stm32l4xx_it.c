/**
 * @file  stm32l4xx_it.c
 * @brief 割込みハンドラ。処理はHALへ委譲し、実務はコールバック(main.c)で行う。
 */
#include "main.h"

extern UART_HandleTypeDef huart1;
extern UART_HandleTypeDef huart2;

void NMI_Handler(void)        { while (1) {} }
void HardFault_Handler(void)  { NVIC_SystemReset(); }
void MemManage_Handler(void)  { NVIC_SystemReset(); }
void BusFault_Handler(void)   { NVIC_SystemReset(); }
void UsageFault_Handler(void) { NVIC_SystemReset(); }
void SVC_Handler(void)        {}
void DebugMon_Handler(void)   {}
void PendSV_Handler(void)     {}
void SysTick_Handler(void)    { HAL_IncTick(); }

void USART1_IRQHandler(void)  { HAL_UART_IRQHandler(&huart1); }
void USART2_IRQHandler(void)  { HAL_UART_IRQHandler(&huart2); }
