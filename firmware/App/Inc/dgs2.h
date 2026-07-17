/**
 * @file  dgs2.h
 * @brief SPEC Sensors DGS2 970-Series ガスセンサ ドライバ (UART 9600bps 8N1)。
 *        パース/検証はHAL非依存 — ホストPCで単体テスト可能。
 *        送信はコールバック注入(テスト時はスタブ、実機はHAL_UART_Transmit)。
 *
 * 準拠資料: DGS2 970-Series Datasheet (Interlink Electronics, 2024, Rev 24a)
 *
 * UARTコマンド (データシート "DGS2 COMMAND LIBRARY", 大文字/小文字を区別):
 *   '\r' : 単発測定(1行応答)
 *   'C'  : 連続測定(約1Hz)の開始/停止トグル  ※大文字
 *   's'  : Sleep(センサバイアス維持, 0.4mA)。任意の1バイト受信でWake
 *   'e'  : EEPROM設定・診断ダンプ(複数行テキスト)
 *   'Z'  : ゼロ校正(クリーンエア中で実行)
 *   'r'  : モジュールリセット(EEPROM設定は保持)
 *
 * Sleep復帰: 「任意のUART文字でWakeし、その後コマンド文字を送る」仕様のため、
 * Wake用バイトはコマンドとして解釈されない前提で1文字消費される。
 * dgs2_cmd_wake() は無害な '\n' を送る(コマンド表に存在しない文字)。
 *
 * 応答CSV (7フィールド, 末尾 <space><cr><lf>):
 *   SN[12], PPB, TEMP(℃×100), RH(%×100), ADC_G, ADC_T, ADC_H
 *   例: 032122030234, 1588, 2436, 3278, 32291, 26636, 20390
 */
#ifndef DGS2_H
#define DGS2_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "app_error.h"

#define DGS2_LINE_MAX       128U  /**< 1行の最大長 */
#define DGS2_SN_LEN         12U   /**< シリアル番号は12桁固定 */
#define DGS2_FIELD_COUNT    7U    /**< 測定行のフィールド数(データシート準拠) */
#define DGS2_STUCK_COUNT    30U   /**< 固着判定: 連続同値サンプル数 */

/* ---- 妥当性レンジ (データシート準拠) ----
 * H2センサ(110-005)の測定レンジは 0-100 ppm。
 * 短期暴露の絶対最大はレンジの120% (=120 ppm = 120,000 ppb)。
 * ゼロ校正後の負側ノイズは正常(Zero Accuracy)のため小さな負値は許容する。 */
#define DGS2_PPB_MAX        120000L   /* 120% of 100 ppm range */
#define DGS2_PPB_MIN        (-5000L)  /* ゼロ点ノイズ許容(-5% of range) */
/* 温度: 測定性能保証レンジ -20〜40℃ (連続動作絶対最大 -30〜50℃) */
#define DGS2_TEMP_MIN_C10   (-200)
#define DGS2_TEMP_MAX_C10   (400)
/* 湿度: 動作レンジ 15〜95%RH (結露なし) */
#define DGS2_RH_MIN_10      (150U)
#define DGS2_RH_MAX_10      (950U)

/** パース済み1サンプル */
typedef struct {
    char     sn[DGS2_SN_LEN + 1]; /**< センサシリアル(NUL終端) */
    int32_t  h2_ppb;              /**< 水素濃度 [ppb] */
    int16_t  temp_c10;            /**< 温度×10 [0.1℃] (生値は℃×100) */
    uint16_t rh10;                /**< 相対湿度×10 [0.1%] (生値は%×100) */
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
} dgs2_t;

void dgs2_init(dgs2_t *d, dgs2_tx_fn tx);

/* ---- コマンド送信 (データシート Command Library と1:1) ---- */
void dgs2_cmd_single(dgs2_t *d);            /**< '\r' : 単発測定 */
void dgs2_cmd_continuous_toggle(dgs2_t *d); /**< 'C' : 連続(1Hz)トグル */
void dgs2_cmd_sleep(dgs2_t *d);             /**< 's' : Sleep */
void dgs2_cmd_wake(dgs2_t *d);              /**< '\n': Wake専用バイト(非コマンド) */
void dgs2_cmd_eeprom(dgs2_t *d);            /**< 'e' : EEPROMダンプ */
void dgs2_cmd_zero(dgs2_t *d);              /**< 'Z' : ゼロ校正 */
void dgs2_cmd_reset(dgs2_t *d);             /**< 'r' : モジュールリセット */

/**
 * @brief 受信1バイトを供給し、1行(CR/LF終端)完成時にtrueを返す。
 *        完成した行は dgs2_parse_line() へ渡すこと。
 */
bool dgs2_feed(dgs2_t *d, uint8_t byte, char *line_out, size_t line_out_size);

/**
 * @brief 測定CSV1行をパースする(純関数)。
 *        7フィールド構成・SN12桁英数字・数値妥当性を検証する。
 *        'e' のEEPROMダンプ等の非測定行は E_SENSOR_PARSE になる(仕様)。
 * @return APP_OK / E_SENSOR_PARSE
 */
app_err_t dgs2_parse_line(const char *line, dgs2_sample_t *out);

/**
 * @brief 異常値チェック。HPP flags(bitmask)を返す(0=正常)。
 *        固着検出は d 内の履歴を更新する。
 */
uint8_t dgs2_validate(dgs2_t *d, const dgs2_sample_t *s);

#endif /* DGS2_H */
