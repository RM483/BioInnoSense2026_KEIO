/**
 * @file dgs2.c
 * @brief DGS2ドライバ実装。strtok非依存の安全なCSVパーサ。
 */
#include <string.h>
#include <stdlib.h>
#include <ctype.h>
#include "dgs2.h"
#include "hpp.h" /* HPP_FLAG_* */

void dgs2_init(dgs2_t *d, dgs2_tx_fn tx)
{
    memset(d, 0, sizeof(*d));
    d->tx = tx;
}

static void tx_char(dgs2_t *d, char c)
{
    uint8_t b = (uint8_t)c;
    d->tx(&b, 1);
}

void dgs2_cmd_single(dgs2_t *d)            { tx_char(d, '\r'); }
void dgs2_cmd_continuous_toggle(dgs2_t *d) { tx_char(d, 'c'); d->continuous = !d->continuous; }
void dgs2_cmd_sleep(dgs2_t *d)             { tx_char(d, 's'); d->continuous = false; }
void dgs2_cmd_eeprom(dgs2_t *d)            { tx_char(d, 'e'); }

bool dgs2_feed(dgs2_t *d, uint8_t byte, char *line_out, size_t line_out_size)
{
    if (byte == '\r' || byte == '\n') {
        if (d->line_len == 0U) {
            return false; /* 空行(CRLF連続)は無視 */
        }
        d->line[d->line_len] = '\0';
        strncpy(line_out, d->line, line_out_size - 1U);
        line_out[line_out_size - 1U] = '\0';
        d->line_len = 0;
        return true;
    }
    if (d->line_len < DGS2_LINE_MAX - 1U) {
        d->line[d->line_len++] = (char)byte;
    } else {
        d->line_len = 0; /* 行長超過: 破損行として破棄 */
    }
    return false;
}

/** カンマ区切りトークンを最大 max 個抽出(入力を書き換えない)。戻り値=個数 */
static int split_csv(const char *line, const char *tokens[], size_t *lens, int max)
{
    int n = 0;
    const char *p = line;
    while (n < max) {
        while (*p == ' ') p++;             /* 先頭空白スキップ */
        const char *start = p;
        while (*p != ',' && *p != '\0') p++;
        const char *end = p;
        while (end > start && *(end - 1) == ' ') end--; /* 末尾空白除去 */
        tokens[n] = start;
        lens[n] = (size_t)(end - start);
        n++;
        if (*p == '\0') break;
        p++;
    }
    return n;
}

/** 10進整数トークンをパース。数字以外を含めば失敗。 */
static bool parse_long(const char *tok, size_t len, long *out)
{
    if (len == 0U || len > 11U) return false;
    char tmp[12];
    memcpy(tmp, tok, len);
    tmp[len] = '\0';
    char *endp = NULL;
    long v = strtol(tmp, &endp, 10);
    return (endp != NULL && *endp == '\0') ? (*out = v, true) : false;
}

app_err_t dgs2_parse_line(const char *line, dgs2_sample_t *out)
{
    /* SN, PPB, TEMP, RH, ADC_RAW, T_RAW, RH_RAW, DAY, HOUR, MIN, SEC */
    const char *tok[11];
    size_t     len[11];
    int n = split_csv(line, tok, len, 11);
    if (n < 4) {
        return E_SENSOR_PARSE;
    }

    /* SN: 英数字のみ許可 */
    if (len[0] == 0U || len[0] > DGS2_SN_LEN) {
        return E_SENSOR_PARSE;
    }
    for (size_t i = 0; i < len[0]; i++) {
        if (!isalnum((unsigned char)tok[0][i])) {
            return E_SENSOR_PARSE;
        }
    }
    memcpy(out->sn, tok[0], len[0]);
    out->sn[len[0]] = '\0';

    long ppb, temp, rh;
    if (!parse_long(tok[1], len[1], &ppb) ||
        !parse_long(tok[2], len[2], &temp) ||
        !parse_long(tok[3], len[3], &rh)) {
        return E_SENSOR_PARSE;
    }
    out->h2_ppb  = (int32_t)ppb;
    out->temp_c10 = (int16_t)(temp * 10);  /* DGS2は整数℃出力 */
    out->rh10     = (uint16_t)(rh * 10);
    return APP_OK;
}

uint8_t dgs2_validate(dgs2_t *d, const dgs2_sample_t *s)
{
    uint8_t flags = 0;

    if (s->h2_ppb < DGS2_PPB_MIN || s->h2_ppb > DGS2_PPB_MAX) {
        flags |= HPP_FLAG_OUT_OF_RANGE;
    }
    int temp_c = s->temp_c10 / 10;
    if (temp_c < DGS2_TEMP_MIN_C || temp_c > DGS2_TEMP_MAX_C) {
        flags |= HPP_FLAG_UNSTABLE;
    }

    /* 固着検出: 0以外の完全同値が DGS2_STUCK_COUNT 回連続 */
    if (s->h2_ppb == d->last_ppb && s->h2_ppb != 0) {
        if (d->same_count < 0xFFFFU) d->same_count++;
    } else {
        d->same_count = 0;
    }
    d->last_ppb = s->h2_ppb;
    if (d->same_count >= DGS2_STUCK_COUNT) {
        flags |= HPP_FLAG_STUCK;
    }
    return flags;
}
