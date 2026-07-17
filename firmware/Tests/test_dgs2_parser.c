/** @file test_dgs2_parser.c  DGS2 CSVパーサ/バリデータの単体テスト */
#include "test_util.h"
#include "dgs2.h"
#include "hpp.h"

static void noop_tx(const uint8_t *d, size_t n) { (void)d; (void)n; }

static void test_parse_normal(void)
{
    dgs2_sample_t s;
    app_err_t e = dgs2_parse_line(
        "010314010306, 1520, 25, 41, 232145, 27961, 40116, 6, 12, 44, 12", &s);
    ASSERT_EQ(e, APP_OK);
    ASSERT_STREQ(s.sn, "010314010306");
    ASSERT_EQ(s.h2_ppb, 1520);
    ASSERT_EQ(s.temp_c10, 250);
    ASSERT_EQ(s.rh10, 410);
}

static void test_parse_negative_and_spaces(void)
{
    dgs2_sample_t s;
    ASSERT_EQ(dgs2_parse_line("ABC123,-5, -3, 99", &s), APP_OK);
    ASSERT_EQ(s.h2_ppb, -5);
    ASSERT_EQ(s.temp_c10, -30);
}

static void test_parse_errors(void)
{
    dgs2_sample_t s;
    ASSERT_EQ(dgs2_parse_line("", &s), E_SENSOR_PARSE);
    ASSERT_EQ(dgs2_parse_line("only,two", &s), E_SENSOR_PARSE);
    ASSERT_EQ(dgs2_parse_line("sn!!,1,2,3", &s), E_SENSOR_PARSE);   /* SN不正 */
    ASSERT_EQ(dgs2_parse_line("ABC,12x,2,3", &s), E_SENSOR_PARSE);  /* 数値不正 */
    ASSERT_EQ(dgs2_parse_line("ABC,,2,3", &s), E_SENSOR_PARSE);     /* 空欄 */
}

static void test_line_assembly(void)
{
    dgs2_t d; dgs2_init(&d, noop_tx);
    char line[DGS2_LINE_MAX];
    const char *in = "ABC,1,2,3\r\nDEF,4,5,6\r\n";
    int lines = 0;
    for (const char *p = in; *p; p++) {
        if (dgs2_feed(&d, (uint8_t)*p, line, sizeof(line))) {
            lines++;
            if (lines == 1) ASSERT_STREQ(line, "ABC,1,2,3");
            if (lines == 2) ASSERT_STREQ(line, "DEF,4,5,6");
        }
    }
    ASSERT_EQ(lines, 2);
}

static void test_validate_range(void)
{
    dgs2_t d; dgs2_init(&d, noop_tx);
    dgs2_sample_t s = { "ABC", 5000, 250, 400 };
    ASSERT_EQ(dgs2_validate(&d, &s), 0);
    s.h2_ppb = DGS2_PPB_MAX + 1;
    ASSERT_TRUE(dgs2_validate(&d, &s) & HPP_FLAG_OUT_OF_RANGE);
    s.h2_ppb = 100; s.temp_c10 = 700; /* 70℃ */
    ASSERT_TRUE(dgs2_validate(&d, &s) & HPP_FLAG_UNSTABLE);
}

static void test_validate_stuck(void)
{
    dgs2_t d; dgs2_init(&d, noop_tx);
    dgs2_sample_t s = { "ABC", 1234, 250, 400 };
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
    test_parse_normal();
    test_parse_negative_and_spaces();
    test_parse_errors();
    test_line_assembly();
    test_validate_range();
    test_validate_stuck();
    return TEST_SUMMARY();
}
