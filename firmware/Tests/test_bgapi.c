/**
 * @file test_bgapi.c
 * @brief BGAPIトランスポートのホストテスト (framing / dispatch / 再同期)。
 */
#include "test_util.h"
#include "bgapi.h"

static bgapi_decoder_t d;

static bgapi_rx_t feed_all(const uint8_t *bytes, size_t n,
                           const uint8_t **data, uint8_t *len,
                           uint8_t *conn)
{
    bgapi_rx_t last = BGAPI_RX_NONE;
    for (size_t i = 0; i < n; i++) {
        bgapi_rx_t r = bgapi_feed(&d, bytes[i], data, len, conn);
        if (r != BGAPI_RX_NONE) last = r;
    }
    return last;
}

static void test_notify_frame_layout(void)
{
    uint8_t out[80];
    const uint8_t payload[3] = {0xA5, 0x01, 0x06};
    size_t n = bgapi_build_notify(1, 0x000C, payload, 3, out);
    ASSERT_EQ(n, 4 + 4 + 3);
    ASSERT_EQ(out[0], BGAPI_TYPE_CMD);
    ASSERT_EQ(out[1], 7);            /* conn+handle(2)+len+value(3) */
    ASSERT_EQ(out[2], BGAPI_CLS_GATT_SERVER);
    ASSERT_EQ(out[3], BGAPI_MTD_SEND_NOTIFY);
    ASSERT_EQ(out[4], 1);            /* connection */
    ASSERT_EQ(out[5], 0x0C);         /* handle LE */
    ASSERT_EQ(out[6], 0x00);
    ASSERT_EQ(out[7], 3);            /* value_len */
    ASSERT_EQ(out[8], 0xA5);
}

static void test_write_event_extracts_hpp_payload(void)
{
    bgapi_decoder_init(&d);
    /* attribute_value evt: conn(1)+attr(2)+opcode(1)+offset(2)+len(1)+val */
    const uint8_t hpp[2] = {0xA5, 0x01};
    uint8_t evt[16] = {
        BGAPI_TYPE_EVT, 9, BGAPI_CLS_GATT_SERVER, BGAPI_MTD_ATTR_VALUE,
        1, 0x0E, 0x00, 0x12, 0x00, 0x00, 2, hpp[0], hpp[1],
    };
    const uint8_t *data = NULL;
    uint8_t len = 0;
    bgapi_rx_t r = feed_all(evt, 13, &data, &len, NULL);
    ASSERT_EQ(r, BGAPI_RX_WRITE);
    ASSERT_EQ(len, 2);
    ASSERT_EQ(data[0], 0xA5);
    ASSERT_EQ(data[1], 0x01);
}

static void test_connection_events(void)
{
    bgapi_decoder_init(&d);
    /* connection_opened: addr(6)+type(1)+master(1)+connection(1)+... */
    uint8_t opened[16] = {
        BGAPI_TYPE_EVT, 11, BGAPI_CLS_LE_CONN, BGAPI_MTD_CONN_OPENED,
        1, 2, 3, 4, 5, 6, /* addr */ 0, /* type */ 0, /* master */
        7, /* connection */ 0, 0,
    };
    uint8_t conn = 0xFF;
    bgapi_rx_t r = feed_all(opened, 4 + 11, NULL, NULL, &conn);
    ASSERT_EQ(r, BGAPI_RX_CONNECTED);
    ASSERT_EQ(conn, 7);

    uint8_t closed[8] = {
        BGAPI_TYPE_EVT, 3, BGAPI_CLS_LE_CONN, BGAPI_MTD_CONN_CLOSED,
        0x08, 0x3E, 7,
    };
    r = feed_all(closed, 7, NULL, NULL, NULL);
    ASSERT_EQ(r, BGAPI_RX_DISCONNECTED);
}

static void test_resync_on_garbage(void)
{
    bgapi_decoder_init(&d);
    /* ゴミ → boot evt が来ても正しく同期する */
    const uint8_t garbage[3] = {0x00, 0xFF, 0x13};
    (void)feed_all(garbage, 3, NULL, NULL, NULL);
    ASSERT_EQ(d.drops, 3);

    uint8_t boot[24] = {
        BGAPI_TYPE_EVT, 18, BGAPI_CLS_SYSTEM, BGAPI_MTD_SYSTEM_BOOT,
    };
    bgapi_rx_t r = feed_all(boot, 4 + 18, NULL, NULL, NULL);
    ASSERT_EQ(r, BGAPI_RX_BOOT);
}

static void test_advertise_cmd(void)
{
    uint8_t out[8];
    size_t n = bgapi_build_advertise(out);
    ASSERT_EQ(n, 6);
    ASSERT_EQ(out[0], BGAPI_TYPE_CMD);
    ASSERT_EQ(out[2], BGAPI_CLS_LE_GAP);
}

int main(void)
{
    printf("test_bgapi\n");
    test_notify_frame_layout();
    test_write_event_extracts_hpp_payload();
    test_connection_events();
    test_resync_on_garbage();
    test_advertise_cmd();
    return TEST_SUMMARY();
}
