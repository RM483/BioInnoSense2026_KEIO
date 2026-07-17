/**
 * @file  ring_buffer.h
 * @brief ISRセーフな SPSC(単一生産者/単一消費者) バイトリングバッファ。
 *        ISRがpush、メインループがpopする用途専用。ロック不要。
 */
#ifndef RING_BUFFER_H
#define RING_BUFFER_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

typedef struct {
    uint8_t          *buf;   /**< 呼び出し側が確保する格納領域 */
    size_t            size;  /**< 領域サイズ(2の冪を推奨) */
    volatile size_t   head;  /**< 書込み位置(producer=ISRが更新) */
    volatile size_t   tail;  /**< 読出し位置(consumer=mainが更新) */
} ring_buffer_t;

void   rb_init(ring_buffer_t *rb, uint8_t *storage, size_t size);
bool   rb_push(ring_buffer_t *rb, uint8_t byte);      /**< 満杯ならfalse(データ破棄) */
bool   rb_pop(ring_buffer_t *rb, uint8_t *out);       /**< 空ならfalse */
size_t rb_count(const ring_buffer_t *rb);
void   rb_clear(ring_buffer_t *rb);

#endif /* RING_BUFFER_H */
