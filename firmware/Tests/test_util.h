/** @file test_util.h  最小テストハーネス(外部依存なし) */
#ifndef TEST_UTIL_H
#define TEST_UTIL_H
#include <stdio.h>
#include <string.h>

static int g_pass = 0, g_fail = 0;

#define ASSERT_TRUE(cond) do { \
    if (cond) { g_pass++; } \
    else { g_fail++; printf("  FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond); } \
} while (0)

#define ASSERT_EQ(a, b) do { \
    long long _a = (long long)(a), _b = (long long)(b); \
    if (_a == _b) { g_pass++; } \
    else { g_fail++; printf("  FAIL %s:%d  %s=%lld != %s=%lld\n", \
                            __FILE__, __LINE__, #a, _a, #b, _b); } \
} while (0)

#define ASSERT_STREQ(a, b) do { \
    if (strcmp((a), (b)) == 0) { g_pass++; } \
    else { g_fail++; printf("  FAIL %s:%d  \"%s\" != \"%s\"\n", \
                            __FILE__, __LINE__, (a), (b)); } \
} while (0)

#define TEST_SUMMARY() (printf("pass=%d fail=%d\n", g_pass, g_fail), (g_fail ? 1 : 0))
#endif
