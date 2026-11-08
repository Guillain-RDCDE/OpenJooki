#ifndef TEST_FREERTOS_TASK_H
#define TEST_FREERTOS_TASK_H
#include <stdint.h>
typedef uint32_t TickType_t;
typedef struct { TickType_t entered; } TimeOut_t;
void vTaskSetTimeOutState(TimeOut_t *state);
int xTaskCheckForTimeOut(TimeOut_t *state, TickType_t *remaining);
#endif
