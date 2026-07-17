/**
 * @file dgs2.c
 * @brief DGS2 970-Seriesドライバ実装。strtok非依存の安全なCSVパーサ。
 *        コマンド文字・CSVフォーマットは公式データシート(Rev 24a)準拠。
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

/* データシート Command Library (大文字/小文字を区別):
 *   '\r' Single, 'C' Continuous toggle, 's' Sleep, 'e' EEPROM,
 *   'Z' Zero, 'r' Reset。Wakeは任意の1バイト(コマンドとして解釈されない)。 */
void dgs2_cmd_single(dgs2_t *d)            { tx_char(d, '\r'); }
void dgs2_cmd_continuous_toggle(dgs2_t *d) { tx_char(d, 'C'); }
void dgs2_cmd_sleep(dgs2_t *d)             { tx_char(d, 's'); }
void dgs2_cmd_wake(dgs2_t *d)              { tx_char(d, '\n'); }
void dgs2_cmd_eeprom(dgs2_t *d)            { tx_char(d, 'e'); }
void dgs2_cmd_zero(dgs2_t *d)              { tx_char(d, 'Z'); }
void dgs2_cmd_reset(dgs2_t *d)             { tx_char(d, 'r'); }

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
    /* データシート "Example Measurement String" (7フィールド固定):
     *   SN[12], PPB, TEMP(℃×100), RH(%×100), ADC_G, ADC_T, ADC_H
     * フィールド数の検証により 'e'(EEPROMダンプ)等の非測定行を弾く。 */
    const char *tok[DGS2_FIELD_COUNT + 1];
    size_t     len[DGS2_FIELD_COUNT + 1];
    int n = split_csv(line, tok, len, DGS2_FIELD_COUNT + 1);
    if (n != DGS2_FIELD_COUNT) {
        return E_SENSOR_PARSE;
    }

    /* SN: 12桁の英数字のみ許可 */
    if (len[0] != DGS2_SN_LEN) {
        return E_SENSOR_PARSE;
    }
    for (size_t i = 0; i < len[0]; i++) {
        if (!isalnum((unsigned char)tok[0][i])) {
            return E_SENSOR_PARSE;
        }
    }
    memcpy(out->sn, tok[0], len[0]);
    out->sn[len[0]] = '\0';

    long ppb, temp_x100, rh_x100;
    if (!parse_long(tok[1], len[1], &ppb) ||
        !parse_long(tok[2], len[2], &temp_x100) ||
        !parse_long(tok[3], len[3], &rh_x100)) {
        return E_SENSOR_PARSE;
    }
    /* 生値レンジ検証 (データシート: TEMP [-5000:15000], RH [0:10000]) */
    if (temp_x100 < -5000L || temp_x100 > 15000L ||
        rh_x100 < 0L || rh_x100 > 10000L) {
        return E_SENSOR_PARSE;
    }
    /* ADC生値3フィールドは数値であることのみ検証(値は未使用) */
    long adc;
    for (int i = 4; i < (int)DGS2_FIELD_COUNT; i++) {
        if (!parse_long(tok[i], len[i], &adc)) {
            return E_SENSOR_PARSE;
        }
    }

    out->h2_ppb   = (int32_t)ppb;
    out->temp_c10 = (int16_t)(temp_x100 / 10L);  /* ℃×100 → ℃×10 */
    out->rh10     = (uint16_t)(rh_x100 / 10L);   /* %×100 → %×10 */
    return APP_OK;
}

uint8_t dgs2_validate(dgs2_t *d, const dgs2_sample_t *s)
{
    uint8_t flags = 0;

    if (s->h2_ppb < DGS2_PPB_MIN || s->h2_ppb > DGS2_PPB_MAX) {
        flags |= HPP_FLAG_OUT_OF_RANGE;
    }
    /* 温湿度が性能保証レンジ外 → 参考値扱い(UNSTABLE) */
    if (s->temp_c10 < DGS2_TEMP_MIN_C10 || s->temp_c10 > DGS2_TEMP_MAX_C10 ||
        s->rh10 < DGS2_RH_MIN_10 || s->rh10 > DGS2_RH_MAX_10) {
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
