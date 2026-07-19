/**
 * @file  bgapi.h
 * @brief AC02 (Silicon Labs BGM11S / Blue Gecko) BGAPIトランスポート層。
 *        HAL非依存・ホストテスト可能 (Tests/test_bgapi.c)。
 *
 * 位置づけ (docs/15 B4):
 *   AC02は透過UARTではなくBGAPIプロトコル(9600bps)で制御する。
 *   HPPフレームはGATT notify(ハンドル0x000C)のペイロードとして送り、
 *   アプリからの書き込みは attribute_value イベントで受ける。
 *   → 上位のHPP/ARQ/状態機械は一切変更しない(トランスポート差替えのみ)。
 *
 * フレーム形式 (BGAPI v2 / Blue Gecko):
 *   [B0] type: 0x20=cmd/rsp, 0xA0=event (上位3bitにlen_high)
 *   [B1] payload長(下位8bit)
 *   [B2] class ID
 *   [B3] method ID
 *   [B4..] payload
 *
 * ★ID検証について: class/method IDは公式TBGLib
 *   (github.com/leafony/TBGLib) と突合して確定させること。
 *   すべて BGAPI_ID_* に集約してあり、値の修正はこのヘッダのみで済む。
 */
#ifndef BGAPI_H
#define BGAPI_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#define BGAPI_MAX_PAYLOAD   64U
#define BGAPI_HEADER_SIZE   4U

/* ---- メッセージ種別 ---- */
#define BGAPI_TYPE_CMD      0x20U
#define BGAPI_TYPE_EVT      0xA0U

/* ---- class/method ID (★TBGLibと要突合 — PROVISIONAL) ---- */
#define BGAPI_CLS_SYSTEM        0x01U
#define BGAPI_MTD_SYSTEM_BOOT   0x00U  /* evt: モジュール起動 */

#define BGAPI_CLS_LE_GAP        0x03U
#define BGAPI_MTD_SET_MODE      0x01U  /* cmd: アドバタイズ開始(旧API) */

#define BGAPI_CLS_LE_CONN       0x08U
#define BGAPI_MTD_CONN_OPENED   0x00U  /* evt: 接続確立 */
#define BGAPI_MTD_CONN_CLOSED   0x01U  /* evt: 切断 */

#define BGAPI_CLS_GATT_SERVER   0x0AU
#define BGAPI_MTD_SEND_NOTIFY   0x05U  /* cmd: characteristic notify送信 */
#define BGAPI_MTD_ATTR_VALUE    0x00U  /* evt: 書き込み受信 */

/* HPPを載せるGATTハンドル (docs/15 B5: AC02標準GATTのnotifyハンドル) */
#define BGAPI_NOTIFY_HANDLE     0x000CU

/** 受信ディスパッチ結果 */
typedef enum {
    BGAPI_RX_NONE = 0,       /**< フレーム未完成 */
    BGAPI_RX_BOOT,           /**< モジュール起動(再アドバタイズが必要) */
    BGAPI_RX_CONNECTED,      /**< セントラル接続 */
    BGAPI_RX_DISCONNECTED,   /**< 切断(再アドバタイズが必要) */
    BGAPI_RX_WRITE,          /**< アプリからの書き込み(payloadにHPPバイト列) */
    BGAPI_RX_OTHER,          /**< その他のrsp/evt(上位は無視してよい) */
} bgapi_rx_t;

/** ストリーミングデコーダ */
typedef struct {
    uint8_t  buf[BGAPI_HEADER_SIZE + BGAPI_MAX_PAYLOAD];
    size_t   idx;
    size_t   expected;
    uint32_t drops;          /**< 解釈不能で読み捨てたバイト数 */
} bgapi_decoder_t;

typedef void (*bgapi_tx_fn)(const uint8_t *data, size_t len);

/**
 * @brief notifyコマンドを組み立てる。
 *        gatt_server_send_characteristic_notification(connection, handle,
 *        len, data)。connectionは接続イベントで得た値を渡す。
 * @return 生成バイト数(0=payload過大)
 */
size_t bgapi_build_notify(uint8_t connection, uint16_t handle,
                          const uint8_t *payload, uint8_t len, uint8_t *out);

/** アドバタイズ開始コマンド(接続可能・一般発見可能)を組み立てる。 */
size_t bgapi_build_advertise(uint8_t *out);

void bgapi_decoder_init(bgapi_decoder_t *d);

/**
 * @brief 受信1バイトを供給。イベント確定時に種別を返す。
 *        BGAPI_RX_WRITE時は data/len に書き込みペイロード、
 *        BGAPI_RX_CONNECTED時は *conn_out に接続ハンドル。
 */
bgapi_rx_t bgapi_feed(bgapi_decoder_t *d, uint8_t byte,
                      const uint8_t **data, uint8_t *len,
                      uint8_t *conn_out);

#endif /* BGAPI_H */
