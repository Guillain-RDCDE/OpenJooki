#ifndef TEST_SDIO_SLAVE_H
#define TEST_SDIO_SLAVE_H
#include <stddef.h>
#include <stdint.h>
#include "esp_err.h"
#include "freertos/task.h"
typedef void *sdio_slave_buf_handle_t;
esp_err_t sdio_slave_send_queue(uint8_t *buffer, size_t len, void *token, TickType_t wait);
esp_err_t sdio_slave_send_get_finished(void **token, TickType_t wait);
#endif
