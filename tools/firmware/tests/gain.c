#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include "volume_control.h"
#define ESP_OK 0
#define ESP_FAIL -1
#define ESP_ERR_INVALID_ARG 2
#define YES 1
#define pdFALSE 0
#define portMAX_DELAY 0
#define ESP_LOGI(...) ((void)0)
static int atomic_volume = 1, held, fail_lock;
static oj_volume_t volume_control = OJ_VOLUME_INITIAL;
static uint8_t toysafe = true;
static int mute;
static float volume, sink;
static int xSemaphoreTake(int s, int t) { (void)s; (void)t; if (fail_lock) return 0; assert(!held); held = 1; return 1; }
static void xSemaphoreGive(int s) { (void)s; assert(held); held = 0; }
static void audio_sink_set_volume(float v) { assert(held); sink = v; }
static int store_setting_to_nvs(const char *k, uint8_t v) { (void)k; (void)v; assert(!held); return 0; }
#include "gain_functions.inc"
static void equal(float a, float b) { assert(a - b < 0.000001f && b - a < 0.000001f); }
int main(void) {
    audio_set_knob_volume(100); equal(sink, VOLUME_TABLE[100] * VOLUME_TABLE_SCALING_TOYSAFE);
    for (int p = 0; p <= 100; ++p) {
        assert(audio_set_toysafe(true) == ESP_OK);
        assert(audio_set_host_volume(p, 101) == ESP_OK);
        equal(sink, VOLUME_TABLE[p] * VOLUME_TABLE_SCALING_NORMAL);
        float kids = sink;
        assert(audio_set_toysafe(false) == ESP_OK);
        assert(audio_set_host_volume(p, 101) == ESP_OK); equal(sink, kids);
    }
    assert(VOLUME_TABLE[56] * VOLUME_TABLE_SCALING_NORMAL <= VOLUME_TABLE[100] * VOLUME_TABLE_SCALING_TOYSAFE);
    assert(VOLUME_TABLE[57] * VOLUME_TABLE_SCALING_NORMAL > VOLUME_TABLE[100] * VOLUME_TABLE_SCALING_TOYSAFE);
    assert(audio_set_toysafe(true) == ESP_OK);
    assert(audio_set_host_volume(100, 31) == ESP_OK); equal(sink, VOLUME_TABLE[30] * VOLUME_TABLE_SCALING_NORMAL);
    audio_set_knob_volume(80); equal(sink, VOLUME_TABLE[30] * VOLUME_TABLE_SCALING_NORMAL);
    assert(audio_set_toysafe(true) == ESP_OK); equal(sink, VOLUME_TABLE[30] * VOLUME_TABLE_SCALING_TOYSAFE);
    assert(audio_set_host_volume(20, 101) == ESP_OK); mute = YES; audio_set_knob_volume(90); equal(sink, 0);
    fail_lock = 1; assert(audio_set_host_volume(50, 101) == ESP_FAIL); equal(sink, 0);
    assert(audio_set_host_volume(-1, 101) == ESP_ERR_INVALID_ARG);
    puts("PASS actual global/legacy audio functions: all 101 levels, factory-equivalent default, ceilings, knob, mute, lock failure");
    return 0;
}
