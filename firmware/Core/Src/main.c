/**
 ******************************************************************************
 * @file    main.c
 * @brief   HydroPaw ファームウェア エントリポイント。
 *          CubeMX生成の初期化 + USER CODEセクションでアプリ層を駆動する。
 *
 *          データフロー:
 *            USART1 RX ISR → rb_sensor → dgs2_feed → sm_on_sensor_line
 *            USART2 RX ISR → rb_ble    → ble_link_feed → sm_on_frame
 *            main loop     → sm_tick / IWDG refresh / STOP2移行
 ******************************************************************************
 */
/* USER CODE BEGIN Header */
/* USER CODE END Header */

#include "main.h"
#include "app_config.h"
#include "ring_buffer.h"
#include "dgs2.h"
#include "ble_link.h"
#include "state_machine.h"
#include "power.h"

/* ---- ペリフェラルハンドル (CubeMX生成) ---- */
UART_HandleTypeDef huart1;   /* DGS2   9600bps  */
UART_HandleTypeDef huart2;   /* AC02 115200bps  */
ADC_HandleTypeDef  hadc1;    /* 電池電圧        */
IWDG_HandleTypeDef hiwdg;

/* ---- USER CODE: アプリ層 ---- */
static uint8_t       sensor_storage[256];
static uint8_t       ble_storage[256];
static ring_buffer_t rb_sensor;
static ring_buffer_t rb_ble;
static uint8_t       rx_byte_sensor;
static uint8_t       rx_byte_ble;

static dgs2_t     g_sensor;
static ble_link_t g_link;
static sm_t       g_sm;

/* ---- CubeMX生成関数プロトタイプ ---- */
static void MX_GPIO_Init(void);
static void MX_USART1_UART_Init(void);
static void MX_USART2_UART_Init(void);
static void MX_ADC1_Init(void);
static void MX_IWDG_Init(void);

/* ---- 注入コールバック ---- */
static void sensor_uart_tx(const uint8_t *data, size_t len)
{
    HAL_UART_Transmit(&huart1, (uint8_t *)data, (uint16_t)len, 100);
}

static void ble_uart_tx(const uint8_t *data, size_t len)
{
    HAL_UART_Transmit(&huart2, (uint8_t *)data, (uint16_t)len, 100);
}

int main(void)
{
    HAL_Init();
    SystemClock_Config();
    MX_GPIO_Init();
    MX_USART1_UART_Init();
    MX_USART2_UART_Init();
    MX_ADC1_Init();
    MX_IWDG_Init();

    /* USER CODE BEGIN 2 */
    rb_init(&rb_sensor, sensor_storage, sizeof(sensor_storage));
    rb_init(&rb_ble, ble_storage, sizeof(ble_storage));

    HAL_GPIO_WritePin(SENSOR_PWR_GPIO_Port, SENSOR_PWR_Pin, GPIO_PIN_SET);
    HAL_Delay(100); /* DGS2電源安定待ち */

    dgs2_init(&g_sensor, sensor_uart_tx);
    ble_link_init(&g_link, ble_uart_tx);
    sm_init(&g_sm, &g_sensor, &g_link, power_read_battery_mv, HAL_GetTick());

    /* 1バイト割込み受信を開始 (RxCpltCallbackで再アーム) */
    HAL_UART_Receive_IT(&huart1, &rx_byte_sensor, 1);
    HAL_UART_Receive_IT(&huart2, &rx_byte_ble, 1);
    /* USER CODE END 2 */

    while (1) {
        /* USER CODE BEGIN WHILE */
        uint32_t now = HAL_GetTick();
        uint8_t  b;

        /* センサ受信処理 */
        char line[DGS2_LINE_MAX];
        while (rb_pop(&rb_sensor, &b)) {
            if (dgs2_feed(&g_sensor, b, line, sizeof(line))) {
                sm_on_sensor_line(&g_sm, line, now);
            }
        }

        /* BLE受信処理 */
        hpp_frame_t frame;
        while (rb_pop(&rb_ble, &b)) {
            if (ble_link_feed(&g_link, b, &frame)) {
                sm_on_frame(&g_sm, &frame, now);
            }
        }

        sm_tick(&g_sm, now);
        HAL_IWDG_Refresh(&hiwdg);

        /* 状態LED: MEASURING=点灯, ERROR=点滅, その他=消灯 */
        if (g_sm.state == SM_MEASURING) {
            HAL_GPIO_WritePin(LED_STATUS_GPIO_Port, LED_STATUS_Pin, GPIO_PIN_SET);
        } else if (g_sm.state == SM_ERROR) {
            HAL_GPIO_WritePin(LED_STATUS_GPIO_Port, LED_STATUS_Pin,
                              ((now / 250U) & 1U) ? GPIO_PIN_SET : GPIO_PIN_RESET);
        } else {
            HAL_GPIO_WritePin(LED_STATUS_GPIO_Port, LED_STATUS_Pin, GPIO_PIN_RESET);
        }

        /* SLEEP要求: 送信完了を待ってSTOP2へ */
        if (g_sm.sleep_requested) {
            g_sm.sleep_requested = false;
            while (HAL_UART_GetState(&huart2) == HAL_UART_STATE_BUSY_TX) { }
            power_enter_stop2();
            /* ここに来た時点でUSART2 RXにより復帰済み。受信ISRは継続動作 */
        }
        /* USER CODE END WHILE */
    }
}

/**
 * @brief UART受信完了コールバック。ISRコンテキスト — バッファ格納と再アームのみ。
 */
void HAL_UART_RxCpltCallback(UART_HandleTypeDef *huart)
{
    if (huart->Instance == USART1) {
        (void)rb_push(&rb_sensor, rx_byte_sensor);
        HAL_UART_Receive_IT(&huart1, &rx_byte_sensor, 1);
    } else if (huart->Instance == USART2) {
        (void)rb_push(&rb_ble, rx_byte_ble);
        HAL_UART_Receive_IT(&huart2, &rx_byte_ble, 1);
    }
}

/** UARTエラー(オーバーラン等)からの自動復旧 */
void HAL_UART_ErrorCallback(UART_HandleTypeDef *huart)
{
    if (huart->Instance == USART1) {
        HAL_UART_Receive_IT(&huart1, &rx_byte_sensor, 1);
    } else if (huart->Instance == USART2) {
        HAL_UART_Receive_IT(&huart2, &rx_byte_ble, 1);
    }
}

/**
 * @brief システムクロック: HSI16 → SYSCLK 16MHz (低消費電力構成)
 */
void SystemClock_Config(void)
{
    RCC_OscInitTypeDef osc = {0};
    RCC_ClkInitTypeDef clk = {0};

    osc.OscillatorType      = RCC_OSCILLATORTYPE_HSI | RCC_OSCILLATORTYPE_LSE;
    osc.HSIState            = RCC_HSI_ON;
    osc.HSICalibrationValue = RCC_HSICALIBRATION_DEFAULT;
    osc.LSEState            = RCC_LSE_ON;
    osc.PLL.PLLState        = RCC_PLL_NONE;
    if (HAL_RCC_OscConfig(&osc) != HAL_OK) {
        Error_Handler();
    }

    clk.ClockType      = RCC_CLOCKTYPE_HCLK | RCC_CLOCKTYPE_SYSCLK
                       | RCC_CLOCKTYPE_PCLK1 | RCC_CLOCKTYPE_PCLK2;
    clk.SYSCLKSource   = RCC_SYSCLKSOURCE_HSI;
    clk.AHBCLKDivider  = RCC_SYSCLK_DIV1;
    clk.APB1CLKDivider = RCC_HCLK_DIV1;
    clk.APB2CLKDivider = RCC_HCLK_DIV1;
    if (HAL_RCC_ClockConfig(&clk, FLASH_LATENCY_0) != HAL_OK) {
        Error_Handler();
    }
}

static void MX_USART1_UART_Init(void)
{
    huart1.Instance          = USART1;
    huart1.Init.BaudRate     = 9600;
    huart1.Init.WordLength   = UART_WORDLENGTH_8B;
    huart1.Init.StopBits     = UART_STOPBITS_1;
    huart1.Init.Parity       = UART_PARITY_NONE;
    huart1.Init.Mode         = UART_MODE_TX_RX;
    huart1.Init.HwFlowCtl    = UART_HWCONTROL_NONE;
    huart1.Init.OverSampling = UART_OVERSAMPLING_16;
    if (HAL_UART_Init(&huart1) != HAL_OK) {
        Error_Handler();
    }
}

static void MX_USART2_UART_Init(void)
{
    huart2.Instance          = USART2;
    huart2.Init.BaudRate     = 115200;
    huart2.Init.WordLength   = UART_WORDLENGTH_8B;
    huart2.Init.StopBits     = UART_STOPBITS_1;
    huart2.Init.Parity       = UART_PARITY_NONE;
    huart2.Init.Mode         = UART_MODE_TX_RX;
    huart2.Init.HwFlowCtl    = UART_HWCONTROL_NONE;
    huart2.Init.OverSampling = UART_OVERSAMPLING_16;
    /* Stop2復帰のためHSIをカーネルクロックに (CubeMXで設定済み) */
    if (HAL_UART_Init(&huart2) != HAL_OK) {
        Error_Handler();
    }
}

static void MX_ADC1_Init(void)
{
    ADC_ChannelConfTypeDef ch = {0};

    hadc1.Instance                   = ADC1;
    hadc1.Init.ClockPrescaler        = ADC_CLOCK_ASYNC_DIV1;
    hadc1.Init.Resolution            = ADC_RESOLUTION_12B;
    hadc1.Init.DataAlign             = ADC_DATAALIGN_RIGHT;
    hadc1.Init.ScanConvMode          = ADC_SCAN_DISABLE;
    hadc1.Init.ContinuousConvMode    = DISABLE;
    hadc1.Init.NbrOfConversion       = 1;
    hadc1.Init.ExternalTrigConv      = ADC_SOFTWARE_START;
    if (HAL_ADC_Init(&hadc1) != HAL_OK) {
        Error_Handler();
    }
    ch.Channel      = ADC_CHANNEL_9; /* PA4 */
    ch.Rank         = ADC_REGULAR_RANK_1;
    ch.SamplingTime = ADC_SAMPLETIME_92CYCLES_5;
    if (HAL_ADC_ConfigChannel(&hadc1, &ch) != HAL_OK) {
        Error_Handler();
    }
}

static void MX_IWDG_Init(void)
{
    hiwdg.Instance       = IWDG;
    hiwdg.Init.Prescaler = IWDG_PRESCALER_64;   /* 32kHz/64 = 500Hz */
    hiwdg.Init.Window    = IWDG_WINDOW_DISABLE;
    hiwdg.Init.Reload    = 4095;                /* ≈8.2s */
    if (HAL_IWDG_Init(&hiwdg) != HAL_OK) {
        Error_Handler();
    }
}

static void MX_GPIO_Init(void)
{
    GPIO_InitTypeDef g = {0};
    __HAL_RCC_GPIOA_CLK_ENABLE();
    __HAL_RCC_GPIOB_CLK_ENABLE();
    __HAL_RCC_GPIOC_CLK_ENABLE();

    g.Pin   = LED_STATUS_Pin;
    g.Mode  = GPIO_MODE_OUTPUT_PP;
    g.Pull  = GPIO_NOPULL;
    g.Speed = GPIO_SPEED_FREQ_LOW;
    HAL_GPIO_Init(LED_STATUS_GPIO_Port, &g);

    g.Pin = SENSOR_PWR_Pin;
    HAL_GPIO_Init(SENSOR_PWR_GPIO_Port, &g);
}

void Error_Handler(void)
{
    __disable_irq();
    while (1) {
        /* IWDGによる自動リセットを待つ */
    }
}
