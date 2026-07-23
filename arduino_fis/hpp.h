/**
 * @file  hpp.h
 * @brief HydroPaw Protocol (HPP) — STM32版と完全バイト互換の移植。
 *        | SOF(0xA5) | VER(0x01) | TYPE | SEQ | LEN | PAYLOAD(<=48) | CRC16(BE) |
 *        CRC16 = CCITT-FALSE (poly 0x1021, init 0xFFFF)。
 *        既存 Flutter/Web アプリはこのフレームをそのまま解釈できる。
 */
#ifndef HP_HPP_H
#define HP_HPP_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#define HPP_SOF             0xA5u
#define HPP_VERSION         0x01u
#define HPP_MAX_PAYLOAD     48u
#define HPP_HEADER_SIZE     5u
#define HPP_CRC_SIZE        2u
#define HPP_MAX_FRAME_SIZE  (HPP_HEADER_SIZE + HPP_MAX_PAYLOAD + HPP_CRC_SIZE)

/* メッセージタイプ (STM32版 hpp.h と一致) */
enum {
    HPP_CMD_START_CONT = 0x01, HPP_CMD_STOP = 0x02, HPP_CMD_SINGLE = 0x03,
    HPP_CMD_SLEEP = 0x04, HPP_CMD_WAKE = 0x05, HPP_CMD_GET_STATUS = 0x06,
    HPP_CMD_GET_INFO = 0x07, HPP_CMD_ZERO = 0x08, HPP_CMD_ACK_EVT = 0x09,
    HPP_CMD_BREATH = 0x0A,
    HPP_ACK = 0x40, HPP_NAK = 0x41,
    HPP_EVT_DATA = 0x81, HPP_EVT_SUMMARY = 0x82, HPP_EVT_STATUS = 0x83,
    HPP_EVT_ERROR = 0x84, HPP_EVT_INFO = 0x85, HPP_EVT_RESULT = 0x86,
    HPP_EVT_PHASE = 0x87
};

/* EVT_PHASE の phase 値 (STM32版と一致) */
enum {
    HPP_PHASE_WARMUP = 0, HPP_PHASE_READY = 1, HPP_PHASE_BREATH = 2,
    HPP_PHASE_ANALYZE = 3, HPP_PHASE_RETRY = 4, HPP_PHASE_DONE = 5,
    HPP_PHASE_ABORTED = 6
};

typedef struct {
    uint8_t type, seq, len;
    uint8_t payload[HPP_MAX_PAYLOAD];
} hpp_frame_t;

typedef struct {
    uint8_t  buf[HPP_MAX_FRAME_SIZE];
    size_t   idx;
    uint32_t crc_errors;
    uint32_t resyncs;
} hpp_decoder_t;

uint16_t hpp_crc16(const uint8_t *data, size_t len);
size_t   hpp_encode(uint8_t type, uint8_t seq, const uint8_t *payload,
                    uint8_t payload_len, uint8_t *out);
void     hpp_decoder_init(hpp_decoder_t *dec);
bool     hpp_decoder_feed(hpp_decoder_t *dec, uint8_t byte, hpp_frame_t *out);

/* リトルエンディアン書き込み(payload用。CRCのみBEなのは hpp_encode 内で処理) */
static inline void hpp_put_u16(uint8_t *p, uint16_t v){ p[0]=(uint8_t)v; p[1]=(uint8_t)(v>>8); }
static inline void hpp_put_u32(uint8_t *p, uint32_t v){ p[0]=(uint8_t)v; p[1]=(uint8_t)(v>>8); p[2]=(uint8_t)(v>>16); p[3]=(uint8_t)(v>>24); }
static inline void hpp_put_i16(uint8_t *p, int16_t v){ hpp_put_u16(p,(uint16_t)v); }
static inline void hpp_put_i32(uint8_t *p, int32_t v){ hpp_put_u32(p,(uint32_t)v); }

#endif /* HP_HPP_H */
