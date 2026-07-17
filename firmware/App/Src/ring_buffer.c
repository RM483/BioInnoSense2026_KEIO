/** @file ring_buffer.c  実装。head/tailの単方向更新のみでSPSC安全性を担保。 */
#include "ring_buffer.h"

void rb_init(ring_buffer_t *rb, uint8_t *storage, size_t size)
{
    rb->buf  = storage;
    rb->size = size;
    rb->head = 0;
    rb->tail = 0;
}

bool rb_push(ring_buffer_t *rb, uint8_t byte)
{
    size_t next = (rb->head + 1U) % rb->size;
    if (next == rb->tail) {
        return false; /* 満杯: 最新データを破棄(上書きしない方針) */
    }
    rb->buf[rb->head] = byte;
    rb->head = next;
    return true;
}

bool rb_pop(ring_buffer_t *rb, uint8_t *out)
{
    if (rb->tail == rb->head) {
        return false; /* 空 */
    }
    *out = rb->buf[rb->tail];
    rb->tail = (rb->tail + 1U) % rb->size;
    return true;
}

size_t rb_count(const ring_buffer_t *rb)
{
    size_t h = rb->head, t = rb->tail;
    return (h >= t) ? (h - t) : (rb->size - t + h);
}

void rb_clear(ring_buffer_t *rb)
{
    rb->tail = rb->head;
}
