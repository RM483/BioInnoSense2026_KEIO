/**
 * @file test_arq.c
 * @brief 選択的ARQ (ble_link v1.2) の損失注入テスト (docs/18 §4)。
 */
#include "test_util.h"
#include "ble_link.h"

/* ---- 送信捕捉(損失注入つき) ---- */
#define MAX_TX 32
static struct {
    uint8_t buf[HPP_MAX_FRAME_SIZE];
    size_t  len;
} g_tx[MAX_TX];
static int  g_tx_count;
static bool g_drop_all; /* true = リンク切断を模擬(送信は闇へ) */

static void tx(const uint8_t *d, size_t n)
{
    if (g_tx_count < MAX_TX) {
        memcpy(g_tx[g_tx_count].buf, d, n);
        g_tx[g_tx_count].len = n;
        g_tx_count++;
    }
    (void)g_drop_all; /* 捕捉自体は常に行う(送信回数の検証用) */
}

static void reset(void)
{
    g_tx_count = 0;
    g_drop_all = false;
}

/** 捕捉フレームの type / seq を読む(HPPヘッダ直読) */
static uint8_t tx_type(int i) { return g_tx[i].buf[2]; }
static uint8_t tx_seq(int i)  { return g_tx[i].buf[3]; }

static const uint8_t PAYLOAD[4] = {1, 2, 3, 4};

static void test_reliable_sends_immediately(void)
{
    ble_link_t l;
    reset();
    ble_link_init(&l, tx);
    ble_link_send_reliable(&l, HPP_EVT_RESULT, PAYLOAD, 4, 1000);
    ASSERT_EQ(g_tx_count, 1);
    ASSERT_EQ(tx_type(0), HPP_EVT_RESULT);
}

static void test_ack_stops_retransmission(void)
{
    ble_link_t l;
    reset();
    ble_link_init(&l, tx);
    ble_link_send_reliable(&l, HPP_EVT_RESULT, PAYLOAD, 4, 1000);
    uint8_t seq = tx_seq(0);
    ble_link_on_ack_evt(&l, seq);
    /* ACK後はいくら時間が経っても再送しない */
    for (uint32_t t = 1000; t < 20000; t += 500) {
        ble_link_tick(&l, t);
    }
    ASSERT_EQ(g_tx_count, 1);
}

static void test_retransmits_until_ack(void)
{
    ble_link_t l;
    reset();
    ble_link_init(&l, tx);
    ble_link_send_reliable(&l, HPP_EVT_RESULT, PAYLOAD, 4, 1000);
    /* ACKなし: 1回目の再送はCFG_ARQ_TIMEOUT_MS後 */
    ble_link_tick(&l, 1000 + CFG_ARQ_TIMEOUT_MS - 1);
    ASSERT_EQ(g_tx_count, 1);
    ble_link_tick(&l, 1000 + CFG_ARQ_TIMEOUT_MS + 1);
    ASSERT_EQ(g_tx_count, 2);
    /* 再送は同一SEQ(受側の重複排除が機能する前提) */
    ASSERT_EQ(tx_seq(1), tx_seq(0));
    /* 途中でACK → 以後停止 */
    ble_link_on_ack_evt(&l, tx_seq(0));
    ble_link_tick(&l, 1000 + 10U * CFG_ARQ_TIMEOUT_MS);
    ASSERT_EQ(g_tx_count, 2);
}

static void test_gives_up_after_max_attempts(void)
{
    ble_link_t l;
    reset();
    ble_link_init(&l, tx);
    ble_link_send_reliable(&l, HPP_EVT_RESULT, PAYLOAD, 4, 0);
    for (uint32_t t = 0; t < 60000; t += 100) {
        ble_link_tick(&l, t);
    }
    /* 初回+再送(MAX-1)=MAX回で断念、dropsに計上 */
    ASSERT_EQ(g_tx_count, (int)CFG_ARQ_MAX_ATTEMPTS);
    ASSERT_EQ(l.arq_drops, 1);
    ASSERT_EQ(l.arq_retransmits, CFG_ARQ_MAX_ATTEMPTS - 1U);
}

static void test_queue_evicts_oldest_when_full(void)
{
    ble_link_t l;
    reset();
    ble_link_init(&l, tx);
    /* 深さ+1件を積む → 最古が追い出される(新しい結果を優先) */
    for (uint32_t i = 0; i <= CFG_ARQ_DEPTH; i++) {
        ble_link_send_reliable(&l, HPP_EVT_RESULT, PAYLOAD, 4, 1000 + i);
    }
    ASSERT_EQ(l.arq_drops, 1);
    /* キューに残る4件は後から積んだもの(SEQ 1..4) */
    int live = 0;
    for (uint8_t i = 0; i < CFG_ARQ_DEPTH; i++) {
        if (l.arq[i].used) live++;
    }
    ASSERT_EQ(live, (int)CFG_ARQ_DEPTH);
}

static void test_unknown_ack_is_ignored(void)
{
    ble_link_t l;
    reset();
    ble_link_init(&l, tx);
    ble_link_send_reliable(&l, HPP_EVT_RESULT, PAYLOAD, 4, 1000);
    ble_link_on_ack_evt(&l, 0xEE); /* 存在しないSEQ */
    ble_link_tick(&l, 1000 + CFG_ARQ_TIMEOUT_MS + 1);
    ASSERT_EQ(g_tx_count, 2); /* まだ生きていて再送される */
}

static void test_besteffort_send_not_queued(void)
{
    ble_link_t l;
    reset();
    ble_link_init(&l, tx);
    ble_link_send(&l, HPP_EVT_DATA, PAYLOAD, 4);
    for (uint32_t t = 0; t < 20000; t += 500) {
        ble_link_tick(&l, t);
    }
    ASSERT_EQ(g_tx_count, 1); /* ストリームは再送されない(設計) */
}

int main(void)
{
    printf("test_arq\n");
    test_reliable_sends_immediately();
    test_ack_stops_retransmission();
    test_retransmits_until_ack();
    test_gives_up_after_max_attempts();
    test_queue_evicts_oldest_when_full();
    test_unknown_ack_is_ignored();
    test_besteffort_send_not_queued();
    return TEST_SUMMARY();
}
