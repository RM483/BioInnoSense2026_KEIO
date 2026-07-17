/** @file ble_link.c */
#include "ble_link.h"

void ble_link_init(ble_link_t *l, ble_tx_fn tx)
{
    l->tx = tx;
    l->tx_seq = 0;
    hpp_decoder_init(&l->dec);
}

void ble_link_send(ble_link_t *l, uint8_t type,
                   const uint8_t *payload, uint8_t len)
{
    uint8_t frame[HPP_MAX_FRAME_SIZE];
    size_t n = hpp_encode(type, l->tx_seq++, payload, len, frame);
    if (n > 0U) {
        l->tx(frame, n);
    }
}

bool ble_link_feed(ble_link_t *l, uint8_t byte, hpp_frame_t *out)
{
    return hpp_decoder_feed(&l->dec, byte, out);
}

void ble_link_send_ack(ble_link_t *l, uint8_t cmd)
{
    ble_link_send(l, HPP_ACK, &cmd, 1);
}

void ble_link_send_nak(ble_link_t *l, uint8_t cmd, uint8_t err)
{
    uint8_t p[2] = { cmd, err };
    ble_link_send(l, HPP_NAK, p, 2);
}

void ble_link_send_error(ble_link_t *l, uint8_t code, uint8_t detail)
{
    uint8_t p[2] = { code, detail };
    ble_link_send(l, HPP_EVT_ERROR, p, 2);
}
