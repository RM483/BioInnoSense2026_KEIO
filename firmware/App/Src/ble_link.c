/**
 * @file ble_link.c
 * @brief HPPリンク + 選択的ARQ実装 (docs/18 §4)。
 *
 * 設計判断: 全フレームARQ(TCP的)は1Hzストリームでキューを詰まらせ
 * 遅延・電力を悪化させる。損失許容度でQoSを分け、失うと測定1回が
 * 消えるフレームだけを保証する。
 */
#include <string.h>
#include "ble_link.h"

void ble_link_init(ble_link_t *l, ble_tx_fn tx)
{
    memset(l, 0, sizeof(*l));
    l->tx = tx;
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

/** 空きスロットを返す。満杯なら最古(next_msが最小)を追い出す。 */
static ble_arq_slot_t *arq_alloc(ble_link_t *l)
{
    ble_arq_slot_t *oldest = &l->arq[0];
    for (uint8_t i = 0; i < CFG_ARQ_DEPTH; i++) {
        if (!l->arq[i].used) {
            return &l->arq[i];
        }
        if (l->arq[i].next_ms < oldest->next_ms) {
            oldest = &l->arq[i];
        }
    }
    l->arq_drops++; /* 追い出し: 新しい結果を優先する設計 */
    oldest->used = false;
    return oldest;
}

void ble_link_send_reliable(ble_link_t *l, uint8_t type,
                            const uint8_t *payload, uint8_t len,
                            uint32_t now_ms)
{
    uint8_t frame[HPP_MAX_FRAME_SIZE];
    uint8_t seq = l->tx_seq++;
    size_t n = hpp_encode(type, seq, payload, len, frame);
    if (n == 0U) {
        return;
    }
    l->tx(frame, n); /* 初回送信 */

    ble_arq_slot_t *s = arq_alloc(l);
    memcpy(s->frame, frame, n);
    s->frame_len = (uint8_t)n;
    s->seq = seq;
    s->attempts = 1;
    s->next_ms = now_ms + CFG_ARQ_TIMEOUT_MS;
    s->used = true;
}

void ble_link_on_ack_evt(ble_link_t *l, uint8_t seq)
{
    for (uint8_t i = 0; i < CFG_ARQ_DEPTH; i++) {
        if (l->arq[i].used && l->arq[i].seq == seq) {
            l->arq[i].used = false;
            return;
        }
    }
    /* 未知SEQのACK: 再送とACKの交差で起きる正常事象。無視する */
}

void ble_link_tick(ble_link_t *l, uint32_t now_ms)
{
    for (uint8_t i = 0; i < CFG_ARQ_DEPTH; i++) {
        ble_arq_slot_t *s = &l->arq[i];
        if (!s->used || (int32_t)(now_ms - s->next_ms) < 0) {
            continue;
        }
        if (s->attempts >= CFG_ARQ_MAX_ATTEMPTS) {
            s->used = false;
            l->arq_drops++;
            continue;
        }
        l->tx(s->frame, s->frame_len); /* 同一SEQのまま再送(受側で重複排除) */
        s->attempts++;
        l->arq_retransmits++;
        s->next_ms = now_ms + CFG_ARQ_TIMEOUT_MS;
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
