/**
 * @file  log.h
 * @brief 軽量デバッグログ(LPUART1向け)。HAL非依存 — 送信はコールバック注入。
 *        Releaseでは HYDROPAW_LOG_DISABLE を定義すると完全に消える。
 */
#ifndef LOG_H
#define LOG_H

#include <stdint.h>
#include <stddef.h>

typedef void (*log_tx_fn)(const uint8_t *data, size_t len);

/** 送信関数を注入して初期化。NULLならログは無効。 */
void log_init(log_tx_fn tx);

/** printf形式。末尾にCRLFを付与して送信する(1行最大128B)。 */
void log_line(const char *fmt, ...) __attribute__((format(printf, 1, 2)));

#ifdef HYDROPAW_LOG_DISABLE
#define LOG(...) ((void)0)
#else
#define LOG(...) log_line(__VA_ARGS__)
#endif

#endif /* LOG_H */
