/**
 * @file test_hpp.c
 * @brief HPP encode/decode/CRC/再同期の単体テスト。
 *        Dart側 (app/test/hpp_codec_test.dart) と同一テストベクタを使用。
 */
#include "test_util.h"
#include "hpp.h"

/* テストベクタ: CMD_START_CONT(interval=1), seq=0 */
static void test_encode_known_vector(void)
{
    uint8_t payload[1] = { 0x01 };
    uint8_t out[HPP_MAX_FRAME_SIZE];
    size_t n = hpp_encode(HPP_CMD_START_CONT, 0x00, payload, 1, out);
    ASSERT_EQ(n, 8);
    ASSERT_EQ(out[0], 0xA5); ASSERT_EQ(out[1], 0x01);
    ASSERT_EQ(out[2], 0x01); ASSERT_EQ(out[3], 0x00);
    ASSERT_EQ(out[4], 0x01); ASSERT_EQ(out[5], 0x01);
    /* CRCはDartテストと突合するため出力 */
    printf("  vector CRC = %02X %02X\n", out[6], out[7]);
}

static void test_roundtrip(void)
{
    uint8_t payload[13];
    for (int i = 0; i < 13; i++) payload[i] = (uint8_t)(i * 7);
    uint8_t wire[HPP_MAX_FRAME_SIZE];
    size_t n = hpp_encode(HPP_EVT_DATA, 42, payload, 13, wire);

    hpp_decoder_t dec; hpp_decoder_init(&dec);
    hpp_frame_t f;
    bool done = false;
    for (size_t i = 0; i < n; i++) {
        done = hpp_decoder_feed(&dec, wire[i], &f);
    }
    ASSERT_TRUE(done);
    ASSERT_EQ(f.type, HPP_EVT_DATA);
    ASSERT_EQ(f.seq, 42);
    ASSERT_EQ(f.len, 13);
    ASSERT_TRUE(memcmp(f.payload, payload, 13) == 0);
}

static void test_garbage_prefix_resync(void)
{
    uint8_t wire[HPP_MAX_FRAME_SIZE];
    size_t n = hpp_encode(HPP_CMD_STOP, 1, NULL, 0, wire);

    hpp_decoder_t dec; hpp_decoder_init(&dec);
    hpp_frame_t f;
    /* ゴミ(SOF含む偽ヘッダ)を先行させる */
    uint8_t junk[] = { 0x00, 0xFF, 0xA5, 0x99, 0x12 };
    bool done = false;
    for (size_t i = 0; i < sizeof(junk); i++) {
        done = hpp_decoder_feed(&dec, junk[i], &f);
        ASSERT_TRUE(!done);
    }
    for (size_t i = 0; i < n; i++) {
        done = hpp_decoder_feed(&dec, wire[i], &f);
    }
    ASSERT_TRUE(done);
    ASSERT_EQ(f.type, HPP_CMD_STOP);
}

static void test_crc_corruption_then_recover(void)
{
    uint8_t wire[HPP_MAX_FRAME_SIZE];
    size_t n = hpp_encode(HPP_CMD_SINGLE, 7, NULL, 0, wire);

    hpp_decoder_t dec; hpp_decoder_init(&dec);
    hpp_frame_t f;
    bool done = false;

    /* 1フレーム目: payload部を破壊 */
    uint8_t bad[HPP_MAX_FRAME_SIZE];
    memcpy(bad, wire, n);
    bad[3] ^= 0xFF; /* seq改竄 → CRC不一致 */
    for (size_t i = 0; i < n; i++) {
        done = hpp_decoder_feed(&dec, bad[i], &f);
    }
    ASSERT_TRUE(!done);
    ASSERT_TRUE(dec.crc_errors >= 1);

    /* 2フレーム目: 正常フレームが受かること */
    for (size_t i = 0; i < n; i++) {
        done = hpp_decoder_feed(&dec, wire[i], &f);
    }
    ASSERT_TRUE(done);
    ASSERT_EQ(f.seq, 7);
}

static void test_back_to_back_frames(void)
{
    uint8_t w1[HPP_MAX_FRAME_SIZE], w2[HPP_MAX_FRAME_SIZE];
    size_t n1 = hpp_encode(HPP_CMD_STOP, 1, NULL, 0, w1);
    size_t n2 = hpp_encode(HPP_CMD_SLEEP, 2, NULL, 0, w2);
    uint8_t stream[2 * HPP_MAX_FRAME_SIZE];
    memcpy(stream, w1, n1);
    memcpy(stream + n1, w2, n2);

    hpp_decoder_t dec; hpp_decoder_init(&dec);
    hpp_frame_t f;
    int frames = 0;
    for (size_t i = 0; i < n1 + n2; i++) {
        if (hpp_decoder_feed(&dec, stream[i], &f)) {
            frames++;
            ASSERT_EQ(f.seq, frames);
        }
    }
    ASSERT_EQ(frames, 2);
}

static void test_oversize_payload_rejected(void)
{
    uint8_t payload[HPP_MAX_PAYLOAD + 1] = {0};
    uint8_t out[HPP_MAX_FRAME_SIZE + 8];
    ASSERT_EQ(hpp_encode(HPP_EVT_DATA, 0, payload, HPP_MAX_PAYLOAD + 1, out), 0);
}

int main(void)
{
    printf("test_hpp\n");
    test_encode_known_vector();
    test_roundtrip();
    test_garbage_prefix_resync();
    test_crc_corruption_then_recover();
    test_back_to_back_frames();
    test_oversize_payload_rejected();
    return TEST_SUMMARY();
}
