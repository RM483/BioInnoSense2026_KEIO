/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file           : main.c
  * @brief          : Main program body
  ******************************************************************************
  * HydroPaw ファームウェア エントリポイント。
  * CubeMX生成の初期化 + USER CODEセクションでアプリ層(App/)を駆動する。
  *
  * データフロー:
  *   USART1 RX ISR → rb_sensor → dgs2_feed → sm_on_sensor_line
  *   USART2 RX ISR → rb_ble    → ble_link_feed → sm_on_frame
  *   main loop     → sm_tick / IWDG refresh / STOP2移行
  *
  * CubeMXで再生成しても、アプリコードはすべてUSER CODEセクション内に
  * あるため保持される(Project Manager: Keep User Code = Yes)。
  ******************************************************************************
  */
/* USER CODE END Header */
/* Includes ------------------------------------------------------------------*/
#include "main.h"

/* Private includes ----------------------------------------------------------*/
/* USER CODE BEGIN Includes */
#include "app_config.h"
#include "ring_buffer.h"
#include "dgs2.h"
#include "ble_link.h"
#include "state_machine.h"
#include "power.h"
#include "log.h"
/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/
/* USER CODE BEGIN PTD */

/* USER CODE END PTD */

/* Private define ------------------------------------------------------------*/
/* USER CODE BEGIN PD */

/* USER CODE END PD */

/* Private macro -------------------------------------------------------------*/
/* USER CODE BEGIN PM */

/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/
ADC_HandleTypeDef hadc1;

IWDG_HandleTypeDef hiwdg;

UART_HandleTypeDef hlpuart1;
UART_HandleTypeDef huart1;
UART_HandleTypeDef huart2;

/* USER CODE BEGIN PV */
static uint8_t       sensor_storage[256];
static uint8_t       ble_storage[256];
static ring_buffer_t rb_sensor;
static ring_buffer_t rb_ble;
static uint8_t       rx_byte_sensor;
static uint8_t       rx_byte_ble;

static dgs2_t     g_sensor;
static ble_link_t g_link;
static sm_t       g_sm;
/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/
void SystemClock_Config(void);
static void MX_GPIO_Init(void);
static void MX_USART1_UART_Init(void);
static void MX_USART2_UART_Init(void);
static void MX_ADC1_Init(void);
static void MX_IWDG_Init(void);
static void MX_LPUART1_UART_Init(void);

/* USER CODE BEGIN PFP */
static void sensor_uart_tx(const uint8_t *data, size_t len);
static void ble_uart_tx(const uint8_t *data, size_t len);
static void debug_uart_tx(const uint8_t *data, size_t len);
/* USER CODE END PFP */

/* Private user code ---------------------------------------------------------*/
/* USER CODE BEGIN 0 */
/* ---- 注入コールバック (App層はHAL非依存のまま保つ) ---- */
static void sensor_uart_tx(const uint8_t *data, size_t len)
{
    HAL_UART_Transmit(&huart1, (uint8_t *)data, (uint16_t)len, 100);
}

static void ble_uart_tx(const uint8_t *data, size_t len)
{
    HAL_UART_Transmit(&huart2, (uint8_t *)data, (uint16_t)len, 100);
}

static void debug_uart_tx(const uint8_t *data, size_t len)
{
    HAL_UART_Transmit(&hlpuart1, (uint8_t *)data, (uint16_t)len, 20);
}
/* USER CODE END 0 */

/**
  * @brief  The application entry point.
  * @retval int
  */
int main(void)
{
  /* USER CODE BEGIN 1 */

  /* USER CODE END 1 */

  /* MCU Configuration--------------------------------------------------------*/

  /* Reset of all peripherals, Initializes the Flash interface and the Systick. */
  HAL_Init();

  /* USER CODE BEGIN Init */

  /* USER CODE END Init */

  /* Configure the system clock */
  SystemClock_Config();

  /* USER CODE BEGIN SysInit */
  /* IWDGはStop/Standby中フリーズさせる(オプションバイト)。未設定なら
   * ここで書き換えてリセットするため、必ずIWDG起動前に実行する。 */
  power_option_bytes_ensure();
  /* USART2カーネルクロック=HSI16 (STOP2からのスタートビットWakeに必須)。
   * .iocにも設定済みだが、生成物(hal_msp)に依存しないよう明示する。 */
  __HAL_RCC_USART2_CONFIG(RCC_USART2CLKSOURCE_HSI);
  /* USER CODE END SysInit */

  /* Initialize all configured peripherals */
  MX_GPIO_Init();
  MX_USART1_UART_Init();
  MX_USART2_UART_Init();
  MX_ADC1_Init();
  MX_IWDG_Init();
  MX_LPUART1_UART_Init();

  /* USER CODE BEGIN 2 */
  log_init(debug_uart_tx);
  LOG("HydroPaw FW v%u.%u boot", FW_VERSION_MAJOR, FW_VERSION_MINOR);

  /* ADCは初回変換前にキャリブレーション必須(L4リファレンスマニュアル) */
  if (HAL_ADCEx_Calibration_Start(&hadc1, ADC_SINGLE_ENDED) != HAL_OK) {
      LOG("ADC calibration failed");
  }

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

  sm_state_t logged_state = g_sm.state;
  /* USER CODE END 2 */

  /* Infinite loop */
  /* USER CODE BEGIN WHILE */
  while (1)
  {
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

    /* 状態遷移ログ (デバッグ用, LPUART1) */
    if (g_sm.state != logged_state) {
        LOG("state %d -> %d", (int)logged_state, (int)g_sm.state);
        logged_state = g_sm.state;
    }

    /* 状態LED: MEASURING=点灯, ERROR=点滅, その他=消灯 */
    if (g_sm.state == SM_MEASURING) {
        HAL_GPIO_WritePin(LED_STATUS_GPIO_Port, LED_STATUS_Pin, GPIO_PIN_SET);
    } else if (g_sm.state == SM_ERROR) {
        HAL_GPIO_WritePin(LED_STATUS_GPIO_Port, LED_STATUS_Pin,
                          ((now / 250U) & 1U) ? GPIO_PIN_SET : GPIO_PIN_RESET);
    } else {
        HAL_GPIO_WritePin(LED_STATUS_GPIO_Port, LED_STATUS_Pin, GPIO_PIN_RESET);
    }

    /* SLEEP要求: IWDGがStop中フリーズ設定の時だけSTOP2へ。
     * 未設定のままSTOP2に入ると約8.2秒毎にIWDGリセットが発生するため、
     * その場合はRunのまま待機する(消費は増えるが誤動作しない)。
     * どちらの場合もUSART2 RX(BLEコマンド)で通常動作へ復帰する。 */
    if (g_sm.sleep_requested) {
        g_sm.sleep_requested = false;
        if (power_iwdg_frozen_in_stop()) {
            LOG("enter STOP2");
            power_enter_stop2();
            /* ここに来た時点でUSART2 RXにより復帰済み。受信ISRは継続動作。
             * IWDGはStop中停止していたため即リフレッシュして再開する。 */
            HAL_IWDG_Refresh(&hiwdg);
            LOG("wake from STOP2");
        } else {
            LOG("STOP2 skipped: IWDG option bytes not frozen");
        }
    }
    /* USER CODE END WHILE */

    /* USER CODE BEGIN 3 */
  }
  /* USER CODE END 3 */
}

/**
  * @brief System Clock Configuration
  * @retval None
  */
void SystemClock_Config(void)
{
  RCC_OscInitTypeDef RCC_OscInitStruct = {0};
  RCC_ClkInitTypeDef RCC_ClkInitStruct = {0};

  /** Initializes the RCC Oscillators according to the specified parameters
  * in the RCC_OscInitTypeDef structure.
  */
  RCC_OscInitStruct.OscillatorType = RCC_OSCILLATORTYPE_HSI | RCC_OSCILLATORTYPE_LSE;
  RCC_OscInitStruct.HSIState = RCC_HSI_ON;
  RCC_OscInitStruct.HSICalibrationValue = RCC_HSICALIBRATION_DEFAULT;
  RCC_OscInitStruct.LSEState = RCC_LSE_ON;
  RCC_OscInitStruct.PLL.PLLState = RCC_PLL_NONE;
  if (HAL_RCC_OscConfig(&RCC_OscInitStruct) != HAL_OK)
  {
    Error_Handler();
  }

  /** Initializes the CPU, AHB and APB buses clocks
  */
  RCC_ClkInitStruct.ClockType = RCC_CLOCKTYPE_HCLK | RCC_CLOCKTYPE_SYSCLK
                              | RCC_CLOCKTYPE_PCLK1 | RCC_CLOCKTYPE_PCLK2;
  RCC_ClkInitStruct.SYSCLKSource = RCC_SYSCLKSOURCE_HSI;
  RCC_ClkInitStruct.AHBCLKDivider = RCC_SYSCLK_DIV1;
  RCC_ClkInitStruct.APB1CLKDivider = RCC_HCLK_DIV1;
  RCC_ClkInitStruct.APB2CLKDivider = RCC_HCLK_DIV1;
  if (HAL_RCC_ClockConfig(&RCC_ClkInitStruct, FLASH_LATENCY_0) != HAL_OK)
  {
    Error_Handler();
  }
}

/**
  * @brief ADC1 Initialization Function
  * @param None
  * @retval None
  */
static void MX_ADC1_Init(void)
{

  /* USER CODE BEGIN ADC1_Init 0 */

  /* USER CODE END ADC1_Init 0 */

  ADC_ChannelConfTypeDef sConfig = {0};

  /* USER CODE BEGIN ADC1_Init 1 */

  /* USER CODE END ADC1_Init 1 */

  /** Common config
  */
  hadc1.Instance = ADC1;
  /* 同期クロック(HCLK/2)を使用: CCIPRのADC非同期ソース設定に依存しない */
  hadc1.Init.ClockPrescaler = ADC_CLOCK_SYNC_PCLK_DIV2;
  hadc1.Init.Resolution = ADC_RESOLUTION_12B;
  hadc1.Init.DataAlign = ADC_DATAALIGN_RIGHT;
  hadc1.Init.ScanConvMode = ADC_SCAN_DISABLE;
  hadc1.Init.ContinuousConvMode = DISABLE;
  hadc1.Init.NbrOfConversion = 1;
  hadc1.Init.ExternalTrigConv = ADC_SOFTWARE_START;
  if (HAL_ADC_Init(&hadc1) != HAL_OK)
  {
    Error_Handler();
  }

  /** Configure Regular Channel
  */
  sConfig.Channel = ADC_CHANNEL_9; /* PA4 */
  sConfig.Rank = ADC_REGULAR_RANK_1;
  sConfig.SamplingTime = ADC_SAMPLETIME_92CYCLES_5;
  if (HAL_ADC_ConfigChannel(&hadc1, &sConfig) != HAL_OK)
  {
    Error_Handler();
  }

  /* USER CODE BEGIN ADC1_Init 2 */

  /* USER CODE END ADC1_Init 2 */

}

/**
  * @brief IWDG Initialization Function
  * @param None
  * @retval None
  */
static void MX_IWDG_Init(void)
{

  /* USER CODE BEGIN IWDG_Init 0 */

  /* USER CODE END IWDG_Init 0 */

  /* USER CODE BEGIN IWDG_Init 1 */

  /* USER CODE END IWDG_Init 1 */
  hiwdg.Instance = IWDG;
  hiwdg.Init.Prescaler = IWDG_PRESCALER_64;   /* 32kHz/64 = 500Hz */
  hiwdg.Init.Window = IWDG_WINDOW_DISABLE;
  hiwdg.Init.Reload = 4095;                   /* ≈8.2s */
  if (HAL_IWDG_Init(&hiwdg) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN IWDG_Init 2 */

  /* USER CODE END IWDG_Init 2 */

}

/**
  * @brief LPUART1 Initialization Function
  * @param None
  * @retval None
  */
static void MX_LPUART1_UART_Init(void)
{

  /* USER CODE BEGIN LPUART1_Init 0 */

  /* USER CODE END LPUART1_Init 0 */

  /* USER CODE BEGIN LPUART1_Init 1 */

  /* USER CODE END LPUART1_Init 1 */
  hlpuart1.Instance = LPUART1;
  hlpuart1.Init.BaudRate = 115200;
  hlpuart1.Init.WordLength = UART_WORDLENGTH_8B;
  hlpuart1.Init.StopBits = UART_STOPBITS_1;
  hlpuart1.Init.Parity = UART_PARITY_NONE;
  hlpuart1.Init.Mode = UART_MODE_TX_RX;
  hlpuart1.Init.HwFlowCtl = UART_HWCONTROL_NONE;
  hlpuart1.Init.OneBitSampling = UART_ONE_BIT_SAMPLE_DISABLE;
  if (HAL_UART_Init(&hlpuart1) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN LPUART1_Init 2 */

  /* USER CODE END LPUART1_Init 2 */

}

/**
  * @brief USART1 Initialization Function
  * @param None
  * @retval None
  */
static void MX_USART1_UART_Init(void)
{

  /* USER CODE BEGIN USART1_Init 0 */

  /* USER CODE END USART1_Init 0 */

  /* USER CODE BEGIN USART1_Init 1 */

  /* USER CODE END USART1_Init 1 */
  huart1.Instance = USART1;
  huart1.Init.BaudRate = 9600;
  huart1.Init.WordLength = UART_WORDLENGTH_8B;
  huart1.Init.StopBits = UART_STOPBITS_1;
  huart1.Init.Parity = UART_PARITY_NONE;
  huart1.Init.Mode = UART_MODE_TX_RX;
  huart1.Init.HwFlowCtl = UART_HWCONTROL_NONE;
  huart1.Init.OverSampling = UART_OVERSAMPLING_16;
  if (HAL_UART_Init(&huart1) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN USART1_Init 2 */

  /* USER CODE END USART1_Init 2 */

}

/**
  * @brief USART2 Initialization Function
  * @param None
  * @retval None
  */
static void MX_USART2_UART_Init(void)
{

  /* USER CODE BEGIN USART2_Init 0 */

  /* USER CODE END USART2_Init 0 */

  /* USER CODE BEGIN USART2_Init 1 */

  /* USER CODE END USART2_Init 1 */
  huart2.Instance = USART2;
  huart2.Init.BaudRate = 115200;
  huart2.Init.WordLength = UART_WORDLENGTH_8B;
  huart2.Init.StopBits = UART_STOPBITS_1;
  huart2.Init.Parity = UART_PARITY_NONE;
  huart2.Init.Mode = UART_MODE_TX_RX;
  huart2.Init.HwFlowCtl = UART_HWCONTROL_NONE;
  huart2.Init.OverSampling = UART_OVERSAMPLING_16;
  if (HAL_UART_Init(&huart2) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN USART2_Init 2 */

  /* USER CODE END USART2_Init 2 */

}

/**
  * @brief GPIO Initialization Function
  * @param None
  * @retval None
  */
static void MX_GPIO_Init(void)
{
  GPIO_InitTypeDef GPIO_InitStruct = {0};

  /* GPIO Ports Clock Enable */
  __HAL_RCC_GPIOC_CLK_ENABLE();
  __HAL_RCC_GPIOA_CLK_ENABLE();
  __HAL_RCC_GPIOB_CLK_ENABLE();

  /*Configure GPIO pin Output Level */
  HAL_GPIO_WritePin(SENSOR_PWR_GPIO_Port, SENSOR_PWR_Pin, GPIO_PIN_RESET);
  HAL_GPIO_WritePin(LED_STATUS_GPIO_Port, LED_STATUS_Pin, GPIO_PIN_RESET);

  /*Configure GPIO pin : SENSOR_PWR_Pin */
  GPIO_InitStruct.Pin = SENSOR_PWR_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(SENSOR_PWR_GPIO_Port, &GPIO_InitStruct);

  /*Configure GPIO pin : LED_STATUS_Pin */
  GPIO_InitStruct.Pin = LED_STATUS_Pin;
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_PP;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(LED_STATUS_GPIO_Port, &GPIO_InitStruct);

}

/* USER CODE BEGIN 4 */

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
/* USER CODE END 4 */

/**
  * @brief  This function is executed in case of error occurrence.
  * @retval None
  */
void Error_Handler(void)
{
  /* USER CODE BEGIN Error_Handler_Debug */
  /* User can add his own implementation to report the HAL error return state */
  __disable_irq();
  while (1)
  {
    /* IWDGによる自動リセットを待つ */
  }
  /* USER CODE END Error_Handler_Debug */
}

#ifdef  USE_FULL_ASSERT
/**
  * @brief  Reports the name of the source file and the source line number
  *         where the assert_param error has occurred.
  * @param  file: pointer to the source file name
  * @param  line: assert_param error line source number
  * @retval None
  */
void assert_failed(uint8_t *file, uint32_t line)
{
  /* USER CODE BEGIN 6 */
  (void)file;
  (void)line;
  /* USER CODE END 6 */
}
#endif /* USE_FULL_ASSERT */
