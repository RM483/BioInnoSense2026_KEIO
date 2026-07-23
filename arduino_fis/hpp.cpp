/**
 * @file hpp.cpp
 * @brief HPP 実装 (STM32版 hpp.c と同一アルゴリズム=バイト互換)。
 */
#include <string.h>
#include "hpp.h"

uint16_t hpp_crc16(const uint8_t *data, size_t len) {
    uint16_t crc = 0xFFFFu;
    for (size_t i = 0; i < len; i++) {
        crc ^= (uint16_t)data[i] << 8;
        for (int b = 0; b < 8; b++)
            crc = (crc & 0x8000u) ? (uint16_t)((crc << 1) ^ 0x1021u) : (uint16_t)(crc << 1);
    }
    return crc;
}

size_t hpp_encode(uint8_t type, uint8_t seq, const uint8_t *payload,
                  uint8_t payload_len, uint8_t *out) {
    if (payload_len > HPP_MAX_PAYLOAD) return 0;
    out[0] = HPP_SOF; out[1] = HPP_VERSION; out[2] = type; out[3] = seq; out[4] = payload_len;
    if (payload_len > 0u) memcpy(&out[HPP_HEADER_SIZE], payload, payload_len);
    size_t body = HPP_HEADER_SIZE + payload_len;
    uint16_t crc = hpp_crc16(out, body);
    out[body]     = (uint8_t)(crc >> 8);   /* CRCのみビッグエンディアン */
    out[body + 1] = (uint8_t)(crc & 0xFF);
    return body + HPP_CRC_SIZE;
}

void hpp_decoder_init(hpp_decoder_t *dec) { memset(dec, 0, sizeof(*dec)); }

static void drop_front(hpp_decoder_t *dec, size_t n) {
    dec->idx -= n;
    memmove(dec->buf, &dec->buf[n], dec->idx);
}

bool hpp_decoder_feed(hpp_decoder_t *dec, uint8_t byte, hpp_frame_t *out) {
    if (dec->idx >= HPP_MAX_FRAME_SIZE) { drop_front(dec, 1); dec->resyncs++; }
    dec->buf[dec->idx++] = byte;
    while (dec->idx > 0u) {
        if (dec->buf[0] != HPP_SOF) { drop_front(dec, 1); continue; }
        if (dec->idx >= 2u && dec->buf[1] != HPP_VERSION) { dec->resyncs++; drop_front(dec, 1); continue; }
        if (dec->idx < HPP_HEADER_SIZE) return false;
        uint8_t len = dec->buf[4];
        if (len > HPP_MAX_PAYLOAD) { dec->resyncs++; drop_front(dec, 1); continue; }
        size_t total = HPP_HEADER_SIZE + (size_t)len + HPP_CRC_SIZE;
        if (dec->idx < total) return false;
        size_t body = total - HPP_CRC_SIZE;
        uint16_t calc = hpp_crc16(dec->buf, body);
        uint16_t recv = (uint16_t)((dec->buf[body] << 8) | dec->buf[body + 1]);
        if (calc != recv) { dec->crc_errors++; drop_front(dec, 1); continue; }
        out->type = dec->buf[2]; out->seq = dec->buf[3]; out->len = len;
        memcpy(out->payload, &dec->buf[HPP_HEADER_SIZE], len);
        drop_front(dec, total);
        return true;
    }
    return false;
}
