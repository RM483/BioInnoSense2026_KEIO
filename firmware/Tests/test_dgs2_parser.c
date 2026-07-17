/** @file test_dgs2_parser.c  DGS2 CSVパーサ/バリデータ/コマンドの単体テスト。
 *  期待値はDGS2 970-Seriesデータシート(Rev 24a)の実例に基づく。 */
#include "test_util.h"
#include "dgs2.h"
#include "hpp.h"

static uint8_t g_tx_buf[64];
static size_t  g_tx_len;

static void capture_tx(const uint8_t *d, size_t n)
{
    for (size_t i = 0; i < n && g_tx_len < sizeof(g_tx_buf); i++) {
        g_tx_buf[g_tx_len++] = d[i];
    }
}

static void noop_tx(const uint8_t *d, size_t n) { (void)d; (void)n; }

/* データシート "Example Measurement String" そのまま */
static void test_parse_datasheet_example(void)
{
    dgs2_sample_t s;
    app_err_t e = dgs2_parse_line(
        "032122030234, 1588, 2436, 3278, 32291, 26636, 20390", &s);
    ASSERT_EQ(e, APP_OK);
    ASSERT_STREQ(s.sn, "032122030234");
    ASSERT_EQ(s.h2_ppb, 1588);
    ASSERT_EQ(s.temp_c10, 243); /* 2436 (℃×100) → 24.3℃ */
    ASSERT_EQ(s.rh10, 327);     /* 3278 (%×100) → 32.7% */
}

static void test_parse_negative_ppb(void)
{
    /* ゼロ校正後の負値ノイズは正常応答 (Zero Accuracy) */
    dgs2_sample_t s;
    ASSERT_EQ(dgs2_parse_line(
        "ABC123DEF456, -55, -310, 990, 1, 2, 3", &s), APP_OK);
    ASSERT_EQ(s.h2_ppb, -55);
    ASSERT_EQ(s.temp_c10, -31);
    ASSERT_EQ(s.rh10, 99);
}

static void test_parse_errors(void)
{
    dgs2_sample_t s;
    ASSERT_EQ(dgs2_parse_line("", &s), E_SENSOR_PARSE);
    /* フィールド数不正(旧4列形式も不正扱い) */
    ASSERT_EQ(dgs2_parse_line("ABC123DEF456,1,2,3", &s), E_SENSOR_PARSE);
    /* 8フィールドは過剰 */
    ASSERT_EQ(dgs2_parse_line(
        "ABC123DEF456,1,2,3,4,5,6,7", &s), E_SENSOR_PARSE);
    /* SNが12桁でない */
    ASSERT_EQ(dgs2_parse_line("ABC,1,2,3,4,5,6", &s), E_SENSOR_PARSE);
    /* SNに記号 */
    ASSERT_EQ(dgs2_parse_line(
        "ABC!23DEF456,1,2,3,4,5,6", &s), E_SENSOR_PARSE);
    /* 数値不正 */
    ASSERT_EQ(dgs2_parse_line(
        "ABC123DEF456,12x,2,3,4,5,6", &s), E_SENSOR_PARSE);
    /* 空欄 */
    ASSERT_EQ(dgs2_parse_line(
        "ABC123DEF456,,2,3,4,5,6", &s), E_SENSOR_PARSE);
    /* 生値レンジ外 (TEMP範囲 [-5000:15000]) */
    ASSERT_EQ(dgs2_parse_line(
        "ABC123DEF456,1,20000,3,4,5,6", &s), E_SENSOR_PARSE);
    /* 生値レンジ外 (RH範囲 [0:10000]) */
    ASSERT_EQ(dgs2_parse_line(
        "ABC123DEF456,1,2,10001,4,5,6", &s), E_SENSOR_PARSE);
    /* EEPROMダンプ行('e'応答)は測定行でない */
    ASSERT_EQ(dgs2_parse_line("FW Date 10FEB23", &s), E_SENSOR_PARSE);
}

static void test_line_assembly(void)
{
    dgs2_t d; dgs2_init(&d, noop_tx);
    char line[DGS2_LINE_MAX];
    /* データシート: 行末は <space><cr><lf> */
    const char *in = "ABC,1,2,3 \r\nDEF,4,5,6 \r\n";
    int lines = 0;
    for (const char *p = in; *p; p++) {
        if (dgs2_feed(&d, (uint8_t)*p, line, sizeof(line))) {
            lines++;
            if (lines == 1) ASSERT_STREQ(line, "ABC,1,2,3 ");
            if (lines == 2) ASSERT_STREQ(line, "DEF,4,5,6 ");
        }
    }
    ASSERT_EQ(lines, 2);
}

static void test_command_bytes(void)
{
    /* データシートCommand Library: 大文字/小文字の区別が正しいこと */
    dgs2_t d; dgs2_init(&d, capture_tx);
    g_tx_len = 0;
    dgs2_cmd_single(&d);
    dgs2_cmd_continuous_toggle(&d);
    dgs2_cmd_sleep(&d);
    dgs2_cmd_wake(&d);
    dgs2_cmd_eeprom(&d);
    dgs2_cmd_zero(&d);
    dgs2_cmd_reset(&d);
    ASSERT_EQ(g_tx_len, 7);
    ASSERT_EQ(g_tx_buf[0], '\r');
    ASSERT_EQ(g_tx_buf[1], 'C');  /* 連続は大文字C (小文字cは無効) */
    ASSERT_EQ(g_tx_buf[2], 's');  /* Sleepは小文字s */
    ASSERT_EQ(g_tx_buf[3], '\n'); /* Wake専用バイト(非コマンド) */
    ASSERT_EQ(g_tx_buf[4], 'e');
    ASSERT_EQ(g_tx_buf[5], 'Z');  /* ゼロ校正は大文字Z */
    ASSERT_EQ(g_tx_buf[6], 'r');  /* リセットは小文字r */
}

static void test_validate_range(void)
{
    dgs2_t d; dgs2_init(&d, noop_tx);
    dgs2_sample_t s = { "ABC123DEF456", 5000, 250, 400 };
    ASSERT_EQ(dgs2_validate(&d, &s), 0);
    /* H2レンジ: 0-100ppm、短期最大120% → 120,000ppb超はレンジ外 */
    s.h2_ppb = DGS2_PPB_MAX + 1;
    ASSERT_TRUE(dgs2_validate(&d, &s) & HPP_FLAG_OUT_OF_RANGE);
    s.h2_ppb = DGS2_PPB_MIN - 1;
    ASSERT_TRUE(dgs2_validate(&d, &s) & HPP_FLAG_OUT_OF_RANGE);
    /* 温度: 性能保証 -20〜40℃ の外はUNSTABLE */
    s.h2_ppb = 100; s.temp_c10 = 450;
    ASSERT_TRUE(dgs2_validate(&d, &s) & HPP_FLAG_UNSTABLE);
    /* 湿度: 動作レンジ 15〜95% の外はUNSTABLE */
    s.temp_c10 = 250; s.rh10 = 100; /* 10% */
    ASSERT_TRUE(dgs2_validate(&d, &s) & HPP_FLAG_UNSTABLE);
    s.rh10 = 960; /* 96% */
    ASSERT_TRUE(dgs2_validate(&d, &s) & HPP_FLAG_UNSTABLE);
}

static void test_validate_stuck(void)
{
    dgs2_t d; dgs2_init(&d, noop_tx);
    dgs2_sample_t s = { "ABC123DEF456", 1234, 250, 400 };
    uint8_t flags = 0;
    for (unsigned i = 0; i <= DGS2_STUCK_COUNT; i++) {
        flags = dgs2_validate(&d, &s);
    }
    ASSERT_TRUE(flags & HPP_FLAG_STUCK);
    s.h2_ppb = 1235; /* 変化すれば解除 */
    ASSERT_TRUE(!(dgs2_validate(&d, &s) & HPP_FLAG_STUCK));
}

int main(void)
{
    printf("test_dgs2_parser\n");
    test_parse_datasheet_example();
    test_parse_negative_ppb();
    test_parse_errors();
    test_line_assembly();
    test_command_bytes();
    test_validate_range();
    test_validate_stuck();
    return TEST_SUMMARY();
}
