/**
 * @file  dgs2.h
 * @brief SPEC Sensors DGS2 水素センサ ドライバ (UART 9600bps 8N1)。
 *        パース/検証はHAL非依存 — ホストPCで単体テスト可能。
 *        送信はコールバック注入(テスト時はスタブ、実機はHAL_UART_Transmit)。
 *
 * DGS2 UARTコマンド:  '\r'=単発測定/Wake, 'c'=連続(1Hz)トグル, 's'=Sleep, 'e'=EEPROMダンプ
 * 応答CSV: SN, PPB, TEMP_C, RH, ADC_RAW, T_RAW, RH_RAW, DAY, HOUR, MIN, SEC
 */
#ifndef DGS2_H
#define DGS2_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "app_error.h"

#define DGS2_LINE_MAX       128U  /**< 1行の最大長 */
#define DGS2_SN_LEN         12U
#define DGS2_STUCK_COUNT    30U   /**< 固着判定: 連続同値サンプル数 */
#define DGS2_PPB_MIN        0L
#define DGS2_PPB_MAX        10000000L  /* 10,000 ppm */
#define DGS2_TEMP_MIN_C     (-20)
#define DGS2_TEMP_MAX_C     60

/** パース済み1サンプル */
typedef struct {
    char    sn[DGS2_SN_LEN + 1]; /**< センサシリアル(NUL終端) */
    int32_t h2_ppb;              /**< 水素濃度 [ppb] */
    int16_t temp_c10;            /**< 温度×10 [0.1℃] */
    uint16_t rh10;               /**< 相対湿度×10 [0.1%] */
} dgs2_sample_t;

/** UART送信コールバック型 */
typedef void (*dgs2_tx_fn)(const uint8_t *data, size_t len);

/** ドライバ状態 */
typedef struct {
    dgs2_tx_fn tx;                       /**< 注入された送信関数 */
    char       line[DGS2_LINE_MAX];      /**< 行組立バッファ */
    size_t     line_len;
    int32_t    last_ppb;                 /**< 固着検出用 */
    uint16_t   same_count;
    bool       continuous;               /**< 連続モード(自己申告状態) */
} dgs2_t;

void dgs2_init(dgs2_t *d, dgs2_tx_fn tx);

/* ---- コマンド送信 ---- */
void dgs2_cmd_single(dgs2_t *d);       /**< '\r' : 単発測定 / Wake */
void dgs2_cmd_continuous_toggle(dgs2_t *d); /**< 'c' : 連続モードトグル */
void dgs2_cmd_sleep(dgs2_t *d);        /**< 's' : Sleep */
void dgs2_cmd_eeprom(dgs2_t *d);       /**< 'e' : EEPROMダンプ(SN取得) */

/**
 * @brief 受信1バイトを供給し、1行(CR/LF終端)完成時にtrueを返す。
 *        完成した行は dgs2_parse_line() へ渡すこと。
 */
bool dgs2_feed(dgs2_t *d, uint8_t byte, char *line_out, size_t line_out_size);

/**
 * @brief CSV1行をパースする(純関数)。
 * @return APP_OK / E_SENSOR_PARSE
 */
app_err_t dgs2_parse_line(const char *line, dgs2_sample_t *out);

/**
 * @brief 異常値チェック。HPP flags(bitmask)を返す(0=正常)。
 *        固着検出は d 内の履歴を更新する。
 */
uint8_t dgs2_validate(dgs2_t *d, const dgs2_sample_t *s);

#endif /* DGS2_H */
