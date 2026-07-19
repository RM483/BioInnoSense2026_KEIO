/**
 * @file bgapi.c
 * @brief BGAPIトランスポート実装 (framing + 最小ディスパッチ)。
 *        参照: Silicon Labs BGAPI v2 / Leafony公式TBGLib (docs/15追補)。
 */
#include <string.h>
#include "bgapi.h"

size_t bgapi_build_notify(uint8_t connection, uint16_t handle,
                          const uint8_t *payload, uint8_t len, uint8_t *out)
{
    /* gatt_server_send_characteristic_notification:
     * payload = connection(1) + handle(2,LE) + value_len(1) + value(n) */
    if ((size_t)len + 4U > BGAPI_MAX_PAYLOAD) {
        return 0;
    }
    uint8_t plen = (uint8_t)(4U + len);
    out[0] = BGAPI_TYPE_CMD;
    out[1] = plen;
    out[2] = BGAPI_CLS_GATT_SERVER;
    out[3] = BGAPI_MTD_SEND_NOTIFY;
    out[4] = connection;
    out[5] = (uint8_t)(handle & 0xFFU);
    out[6] = (uint8_t)(handle >> 8);
    out[7] = len;
    memcpy(&out[8], payload, len);
    return (size_t)BGAPI_HEADER_SIZE + plen;
}

size_t bgapi_build_advertise(uint8_t *out)
{
    /* le_gap_set_mode(discoverable=2:general, connectable=2:undirected) */
    out[0] = BGAPI_TYPE_CMD;
    out[1] = 2;
    out[2] = BGAPI_CLS_LE_GAP;
    out[3] = BGAPI_MTD_SET_MODE;
    out[4] = 2;
    out[5] = 2;
    return 6;
}

void bgapi_decoder_init(bgapi_decoder_t *d)
{
    memset(d, 0, sizeof(*d));
}

/** 完成フレームを解釈して種別へ振り分ける。 */
static bgapi_rx_t classify(const bgapi_decoder_t *d,
                           const uint8_t **data, uint8_t *len,
                           uint8_t *conn_out)
{
    uint8_t type = d->buf[0] & 0xF8U; /* 下位3bitはlen_high */
    uint8_t cls = d->buf[2];
    uint8_t mtd = d->buf[3];
    const uint8_t *p = &d->buf[4];
    uint8_t plen = d->buf[1];

    if (type == BGAPI_TYPE_EVT) {
        if (cls == BGAPI_CLS_SYSTEM && mtd == BGAPI_MTD_SYSTEM_BOOT) {
            return BGAPI_RX_BOOT;
        }
        if (cls == BGAPI_CLS_LE_CONN && mtd == BGAPI_MTD_CONN_OPENED) {
            /* connection handleはpayload末尾側(addr(6)+type(1)+master(1)+
             * connection(1)+...)。TBGLib準拠でoffset=8。 */
            if (plen > 8U && conn_out != NULL) {
                *conn_out = p[8];
            }
            return BGAPI_RX_CONNECTED;
        }
        if (cls == BGAPI_CLS_LE_CONN && mtd == BGAPI_MTD_CONN_CLOSED) {
            return BGAPI_RX_DISCONNECTED;
        }
        if (cls == BGAPI_CLS_GATT_SERVER && mtd == BGAPI_MTD_ATTR_VALUE) {
            /* attribute_value: connection(1)+attribute(2)+att_opcode(1)+
             * offset(2)+value_len(1)+value(n) — TBGLib準拠 */
            if (plen >= 7U) {
                uint8_t vlen = p[6];
                if ((size_t)vlen + 7U <= plen) {
                    if (data != NULL) *data = &p[7];
                    if (len != NULL) *len = vlen;
                    return BGAPI_RX_WRITE;
                }
            }
            return BGAPI_RX_OTHER;
        }
    }
    return BGAPI_RX_OTHER; /* rsp等 — 上位は無視してよい */
}

bgapi_rx_t bgapi_feed(bgapi_decoder_t *d, uint8_t byte,
                      const uint8_t **data, uint8_t *len,
                      uint8_t *conn_out)
{
    if (d->idx == 0U) {
        /* 先頭バイトはcmd/rsp(0x20)かevt(0xA0)のみ許容(上位5bit) */
        uint8_t t = byte & 0xF8U;
        if (t != BGAPI_TYPE_CMD && t != BGAPI_TYPE_EVT) {
            d->drops++;
            return BGAPI_RX_NONE; /* 同期外れ: 読み捨てて再同期 */
        }
    }
    d->buf[d->idx++] = byte;

    if (d->idx == 2U) {
        size_t plen = ((size_t)(d->buf[0] & 0x07U) << 8) | d->buf[1];
        if (plen > BGAPI_MAX_PAYLOAD) {
            d->idx = 0;
            d->drops += 2U;
            return BGAPI_RX_NONE;
        }
        d->expected = BGAPI_HEADER_SIZE + plen;
    }
    if (d->idx >= BGAPI_HEADER_SIZE && d->idx == d->expected) {
        bgapi_rx_t r = classify(d, data, len, conn_out);
        d->idx = 0;
        d->expected = 0;
        return r;
    }
    return BGAPI_RX_NONE;
}
