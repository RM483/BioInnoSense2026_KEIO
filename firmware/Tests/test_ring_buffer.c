/** @file test_ring_buffer.c  SPSCリングバッファの単体テスト */
#include "test_util.h"
#include "ring_buffer.h"

static void test_push_pop_fifo(void)
{
    uint8_t storage[8];
    ring_buffer_t rb;
    rb_init(&rb, storage, sizeof(storage));

    ASSERT_EQ(rb_count(&rb), 0);
    for (uint8_t i = 0; i < 7; i++) {
        ASSERT_TRUE(rb_push(&rb, i));
    }
    /* サイズNのSPSCリングは N-1 まで格納可能 */
    ASSERT_TRUE(!rb_push(&rb, 0xFF));
    ASSERT_EQ(rb_count(&rb), 7);

    uint8_t b;
    for (uint8_t i = 0; i < 7; i++) {
        ASSERT_TRUE(rb_pop(&rb, &b));
        ASSERT_EQ(b, i);
    }
    ASSERT_TRUE(!rb_pop(&rb, &b)); /* 空 */
}

static void test_wraparound(void)
{
    uint8_t storage[4];
    ring_buffer_t rb;
    rb_init(&rb, storage, sizeof(storage));

    uint8_t b;
    /* 折り返しを複数回跨いでもFIFO順序が保たれる */
    for (int round = 0; round < 10; round++) {
        ASSERT_TRUE(rb_push(&rb, (uint8_t)(round * 2)));
        ASSERT_TRUE(rb_push(&rb, (uint8_t)(round * 2 + 1)));
        ASSERT_TRUE(rb_pop(&rb, &b));
        ASSERT_EQ(b, round * 2);
        ASSERT_TRUE(rb_pop(&rb, &b));
        ASSERT_EQ(b, round * 2 + 1);
    }
}

static void test_clear(void)
{
    uint8_t storage[8];
    ring_buffer_t rb;
    rb_init(&rb, storage, sizeof(storage));

    rb_push(&rb, 1);
    rb_push(&rb, 2);
    rb_clear(&rb);
    ASSERT_EQ(rb_count(&rb), 0);
    uint8_t b;
    ASSERT_TRUE(!rb_pop(&rb, &b));
    /* クリア後も正常に使える */
    ASSERT_TRUE(rb_push(&rb, 42));
    ASSERT_TRUE(rb_pop(&rb, &b));
    ASSERT_EQ(b, 42);
}

int main(void)
{
    printf("test_ring_buffer\n");
    test_push_pop_fifo();
    test_wraparound();
    test_clear();
    return TEST_SUMMARY();
}
