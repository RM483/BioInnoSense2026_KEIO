/**
 * @file  ble_link.h
 * @brief AC02 (UART透過ブリッジ) 経由のHPP送受信リンク。HAL非依存(送信は注入)。
 */
#ifndef BLE_LINK_H
#define BLE_LINK_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "hpp.h"

typedef void (*ble_tx_fn)(const uint8_t *data, size_t len);

typedef struct {
    ble_tx_fn     tx;
    hpp_decoder_t dec;
    uint8_t       tx_seq;    /**< 送信SEQ(自動インクリメント) */
} ble_link_t;

void ble_link_init(ble_link_t *l, ble_tx_fn tx);

/** HPPフレームを組み立てて送信する。 */
void ble_link_send(ble_link_t *l, uint8_t type,
                   const uint8_t *payload, uint8_t len);

/** 受信1バイトを供給。フレーム完成でtrue。 */
bool ble_link_feed(ble_link_t *l, uint8_t byte, hpp_frame_t *out);

/* ---- 送信ヘルパ ---- */
void ble_link_send_ack(ble_link_t *l, uint8_t cmd);
void ble_link_send_nak(ble_link_t *l, uint8_t cmd, uint8_t err);
void ble_link_send_error(ble_link_t *l, uint8_t code, uint8_t detail);

#endif /* BLE_LINK_H */
