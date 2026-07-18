/**
 * @file  app_error.h
 * @brief HydroPaw 共通エラーコード定義。
 *        HPPプロトコル(docs/03)のエラーコードと1:1対応。Flutter側
 *        (core/error/app_exception.dart) と同一の値を保つこと。
 */
#ifndef APP_ERROR_H
#define APP_ERROR_H

typedef enum {
    APP_OK              = 0x00, /**< 正常 */
    E_SENSOR_TIMEOUT    = 0x01, /**< DGS2応答なし(リトライ超過) */
    E_SENSOR_PARSE      = 0x02, /**< CSVパース失敗 */
    E_OUT_OF_RANGE      = 0x03, /**< 測定値レンジ外 */
    E_BUSY              = 0x04, /**< 状態遷移不可(処理中) */
    E_INVALID_CMD       = 0x05, /**< 未定義コマンド */
    E_INVALID_PARAM     = 0x06, /**< パラメータ不正 */
    E_LOW_BATTERY       = 0x07, /**< 電池電圧低下 */
    E_INTERNAL          = 0x08, /**< 内部エラー */
    E_CRC               = 0x09, /**< フレームCRC不一致 */
    E_NO_BREATH         = 0x0A, /**< READYタイムアウト(呼気を検出できず) */
} app_err_t;

#endif /* APP_ERROR_H */
