/**
 * @file  hpp.h
 * @brief HydroPaw Protocol (HPP) v1 エンコーダ/デコーダ。
 *        HAL非依存の純粋Cモジュール — ホストPCで単体テスト可能。
 *        フレーム形式は docs/03_ble_spec.md 参照。
 *
 *        | SOF(0xA5) | VER(0x01) | TYPE | SEQ | LEN | PAYLOAD(≤48) | CRC16(BE) |
 */
#ifndef HPP_H
#define HPP_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "app_error.h"

#define HPP_SOF             0xA5U
#define HPP_VERSION         0x01U
#define HPP_MAX_PAYLOAD     48U
#define HPP_HEADER_SIZE     5U   /* SOF+VER+TYPE+SEQ+LEN */
#define HPP_CRC_SIZE        2U
#define HPP_MAX_FRAME_SIZE  (HPP_HEADER_SIZE + HPP_MAX_PAYLOAD + HPP_CRC_SIZE)

/* ---- メッセージタイプ (App→FW: 0x0x, FW→App: 0x4x/0x8x) ---- */
typedef enum {
    HPP_CMD_START_CONT  = 0x01,
    HPP_CMD_STOP        = 0x02,
    HPP_CMD_SINGLE      = 0x03,
    HPP_CMD_SLEEP       = 0x04,
    HPP_CMD_WAKE        = 0x05,
    HPP_CMD_GET_STATUS  = 0x06,
    HPP_CMD_GET_INFO    = 0x07,
    HPP_CMD_ZERO        = 0x08, /**< DGS2ゼロ校正 'Z' (クリーンエア中に実行) */
    HPP_ACK             = 0x40,
    HPP_NAK             = 0x41,
    HPP_EVT_DATA        = 0x81,
    HPP_EVT_SUMMARY     = 0x82,
    HPP_EVT_STATUS      = 0x83,
    HPP_EVT_ERROR       = 0x84,
    HPP_EVT_INFO        = 0x85,
} hpp_type_t;

/* ---- EVT_DATA flags ---- */
#define HPP_FLAG_OUT_OF_RANGE  (1U << 0)
#define HPP_FLAG_STUCK         (1U << 1)
#define HPP_FLAG_WARMUP        (1U << 2)
#define HPP_FLAG_UNSTABLE      (1U << 3)

/** デコード済みフレーム */
typedef struct {
    uint8_t type;
    uint8_t seq;
    uint8_t len;
    uint8_t payload[HPP_MAX_PAYLOAD];
} hpp_frame_t;

/** ストリーミングデコーダ(1バイトずつfeed) */
typedef struct {
    uint8_t  buf[HPP_MAX_FRAME_SIZE];
    size_t   idx;          /**< bufへの書込み位置 */
    size_t   expected;     /**< フレーム全長(LEN確定後) */
    uint32_t crc_errors;   /**< 統計: CRC不一致回数 */
    uint32_t resyncs;      /**< 統計: 再同期回数 */
} hpp_decoder_t;

uint16_t hpp_crc16(const uint8_t *data, size_t len);

/**
 * @brief フレームを組み立てる。
 * @param out     HPP_MAX_FRAME_SIZE 以上のバッファ
 * @return 生成バイト数。payload_len超過時は0。
 */
size_t hpp_encode(uint8_t type, uint8_t seq,
                  const uint8_t *payload, uint8_t payload_len, uint8_t *out);

void hpp_decoder_init(hpp_decoder_t *dec);

/**
 * @brief 受信1バイトをデコーダへ供給。
 * @return フレーム完成時 true(outへ格納)。CRC不一致・非同期は内部で再同期。
 */
bool hpp_decoder_feed(hpp_decoder_t *dec, uint8_t byte, hpp_frame_t *out);

/* ---- リトルエンディアン読み書きヘルパ ---- */
static inline void hpp_put_u16(uint8_t *p, uint16_t v) { p[0]=(uint8_t)v; p[1]=(uint8_t)(v>>8); }
static inline void hpp_put_u32(uint8_t *p, uint32_t v) { p[0]=(uint8_t)v; p[1]=(uint8_t)(v>>8); p[2]=(uint8_t)(v>>16); p[3]=(uint8_t)(v>>24); }
static inline void hpp_put_i32(uint8_t *p, int32_t v)  { hpp_put_u32(p, (uint32_t)v); }
static inline void hpp_put_i16(uint8_t *p, int16_t v)  { hpp_put_u16(p, (uint16_t)v); }
static inline uint16_t hpp_get_u16(const uint8_t *p)   { return (uint16_t)(p[0] | (p[1]<<8)); }
static inline uint32_t hpp_get_u32(const uint8_t *p)   { return (uint32_t)p[0] | ((uint32_t)p[1]<<8) | ((uint32_t)p[2]<<16) | ((uint32_t)p[3]<<24); }

#endif /* HPP_H */
