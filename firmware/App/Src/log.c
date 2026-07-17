/** @file log.c */
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include "log.h"

static log_tx_fn s_tx;

void log_init(log_tx_fn tx)
{
    s_tx = tx;
}

void log_line(const char *fmt, ...)
{
    if (s_tx == NULL) {
        return;
    }
    char buf[128];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(buf, sizeof(buf) - 2U, fmt, ap);
    va_end(ap);
    if (n < 0) {
        return;
    }
    size_t len = (n < (int)(sizeof(buf) - 2U)) ? (size_t)n : sizeof(buf) - 2U;
    buf[len++] = '\r';
    buf[len++] = '\n';
    s_tx((const uint8_t *)buf, len);
}
