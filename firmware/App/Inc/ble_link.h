/**
 * @file  ble_link.h
 * @brief AC02 (UART透過ブリッジ) 経由のHPP送受信リンク。HAL非依存(送信は注入)。
 *
 * v1.2: 選択的ARQ (docs/18 §4)。
 *  - EVT_DATA等のストリームは従来通りベストエフォート(損失は次サンプルで回復)
 *  - EVT_RESULT/SUMMARY/ERROR等のクリティカルフレームは
 *    ble_link_send_reliable() で送り、App側のCMD_ACK_EVT(payload=SEQ)を
 *    受けるまで CFG_ARQ_TIMEOUT_MS 間隔で再送する(最大CFG_ARQ_MAX_ATTEMPTS)。
 *  - キュー満杯時は最も古いスロットを破棄して積む(新しい結果を優先)。
 *    破棄は arq_drops に計上され EVT_STATUS で可視化される。
 */
#ifndef BLE_LINK_H
#define BLE_LINK_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "hpp.h"
#include "app_config.h"

typedef void (*ble_tx_fn)(const uint8_t *data, size_t len);

/** ARQスロット(静的確保, malloc不使用) */
typedef struct {
    uint8_t  frame[HPP_MAX_FRAME_SIZE];
    uint8_t  frame_len;
    uint8_t  seq;
    uint8_t  attempts;     /**< 送信済み回数(初回含む) */
    uint32_t next_ms;      /**< 次回再送時刻 */
    bool     used;
} ble_arq_slot_t;

typedef struct {
    ble_tx_fn      tx;
    hpp_decoder_t  dec;
    uint8_t        tx_seq;     /**< 送信SEQ(自動インクリメント) */
    ble_arq_slot_t arq[CFG_ARQ_DEPTH];
    uint32_t       arq_drops;      /**< 再送断念+キュー追い出し回数 */
    uint32_t       arq_retransmits;/**< 再送実行回数(診断用) */
} ble_link_t;

void ble_link_init(ble_link_t *l, ble_tx_fn tx);

/** HPPフレームを組み立てて送信する(ベストエフォート)。 */
void ble_link_send(ble_link_t *l, uint8_t type,
                   const uint8_t *payload, uint8_t len);

/** クリティカルフレーム送信: ACK_EVT受領まで再送保証(選択的ARQ)。 */
void ble_link_send_reliable(ble_link_t *l, uint8_t type,
                            const uint8_t *payload, uint8_t len,
                            uint32_t now_ms);

/** App→FWのCMD_ACK_EVT(payload=SEQ)を反映しスロットを解放する。 */
void ble_link_on_ack_evt(ble_link_t *l, uint8_t seq);

/** 周期処理: 期限が来たスロットを再送する。sm_tick()から毎回呼ぶ。 */
void ble_link_tick(ble_link_t *l, uint32_t now_ms);

/** 受信1バイトを供給。フレーム完成でtrue。 */
bool ble_link_feed(ble_link_t *l, uint8_t byte, hpp_frame_t *out);

/* ---- 送信ヘルパ ---- */
void ble_link_send_ack(ble_link_t *l, uint8_t cmd);
void ble_link_send_nak(ble_link_t *l, uint8_t cmd, uint8_t err);
void ble_link_send_error(ble_link_t *l, uint8_t code, uint8_t detail);

#endif /* BLE_LINK_H */
