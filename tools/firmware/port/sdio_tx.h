/* Bounded SDIO transmission using the public ESP-IDF 4.4 driver.
 * All calls require the application's TX mutex. A timeout does not cancel DMA:
 * the single preallocated buffer stays owned until its exact token is returned.
 */
#ifndef OJ_SDIO_TX_H
#define OJ_SDIO_TX_H
#include <stdbool.h>
#include "driver/sdio_slave.h"
#include "freertos/task.h"

typedef struct {
    uint8_t *buffer;
    bool pending;
    bool fault;
} oj_sdio_tx_t;

typedef struct {
    TimeOut_t started;
    TickType_t remaining;
} oj_sdio_budget_t;

static inline void oj_sdio_budget_start(oj_sdio_budget_t *b, TickType_t ticks) {
    b->remaining = ticks;
    vTaskSetTimeOutState(&b->started);
}

static inline TickType_t oj_sdio_remaining(oj_sdio_budget_t *b) {
    if (xTaskCheckForTimeOut(&b->started, &b->remaining)) b->remaining = 0;
    return b->remaining;
}

/* Must succeed before the caller writes any byte of tx->buffer. */
static inline esp_err_t oj_sdio_tx_prepare(oj_sdio_tx_t *tx, oj_sdio_budget_t *b) {
    if (tx->fault) return ESP_ERR_INVALID_STATE;
    if (!tx->pending) return ESP_OK;
    void *done = NULL;
    esp_err_t ret = sdio_slave_send_get_finished(&done, oj_sdio_remaining(b));
    if (ret != ESP_OK) return ret;
    if (done != tx->buffer) {
        tx->fault = true;
        return ESP_ERR_INVALID_STATE;
    }
    tx->pending = false;
    return ESP_OK;
}

static inline esp_err_t oj_sdio_tx_submit(oj_sdio_tx_t *tx, size_t len, oj_sdio_budget_t *b) {
    if (tx->fault || tx->pending) return ESP_ERR_INVALID_STATE;
    TickType_t left = oj_sdio_remaining(b);
    if (!left) return ESP_ERR_TIMEOUT;
    esp_err_t ret = sdio_slave_send_queue(tx->buffer, len, tx->buffer, left);
    if (ret != ESP_OK) return ret;
    tx->pending = true;
    return oj_sdio_tx_prepare(tx, b);
}

/* Call only after sdio_slave_stop() and a successful sdio_slave_reset(), while
 * holding write, TX and RX locks. reset flushes the outstanding TX token into
 * the finished queue; verify it before making the buffer writable again.
 */
static inline esp_err_t oj_sdio_tx_reclaim(oj_sdio_tx_t *tx) {
    unsigned count = 0;
    void *done = NULL;
    esp_err_t ret;
    while ((ret = sdio_slave_send_get_finished(&done, 0)) == ESP_OK) {
        if (done != tx->buffer || ++count > 1) {
            tx->fault = true;
            return ESP_ERR_INVALID_STATE;
        }
    }
    if (ret != ESP_ERR_TIMEOUT || count != (unsigned)tx->pending) {
        tx->fault = true;
        return ret == ESP_ERR_TIMEOUT ? ESP_ERR_INVALID_STATE : ret;
    }
    tx->pending = false;
    tx->fault = false;
    return ESP_OK;
}
#endif
