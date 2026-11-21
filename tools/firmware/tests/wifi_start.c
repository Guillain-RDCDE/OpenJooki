/* Exercise the actual patched wcm_start (wcm.c): which network list leads to a connection at
 * start, and which to the Bluetooth set-up. A gap in the list (a network forgotten before the
 * home one) must no longer hide the home network (#51). */
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define JK_MAX_STA_CONF_CNT 10
#define LOG_TAG_WCM "WCM"
#define LOG_INFO(tag, ...) ((void)(tag))
#define LOG_ERROR(tag, ...) ((void)(tag))
typedef struct { uint8_t bssid[6]; uint8_t ssid[33]; uint8_t primary; int8_t rssi; } wifi_ap_record_t;
typedef struct { uint8_t ssid[32]; uint8_t password[64]; uint8_t channel; } wcm_wifi_config_t;

static wcm_wifi_config_t slots[JK_MAX_STA_CONF_CNT];
static int prov, reconnect, scans, scanned_slot_ok, fallback_visible;

static wcm_wifi_config_t *wcm_nvs_get_wifi_config(int i) { assert(i >= 0 && i < JK_MAX_STA_CONF_CNT); return &slots[i]; }
static int wcm_sta_scan_for_ssid(uint8_t *ssid, int max, wifi_ap_record_t *records, bool hidden) {
    (void)records; (void)hidden; assert(max == 1);
    ++scans; scanned_slot_ok = strcmp((const char *)ssid, "mnet2") == 0;
    return fallback_visible ? 1 : 0;
}
static bool wcm_prov_start(void) { ++prov; return true; }
static bool wcm_sta_reconnect_trig(void) { ++reconnect; return true; }

#include "wifi_start.inc"

static void set(const char *list) {   /* "mnet2,,Home": one name per slot, empty = an empty slot */
    memset(slots, 0, sizeof(slots));
    prov = reconnect = scans = scanned_slot_ok = 0;
    char buf[200]; strncpy(buf, list, sizeof(buf) - 1); buf[sizeof(buf) - 1] = 0;
    int i = 0; char *p = buf;
    while (p && i < JK_MAX_STA_CONF_CNT) {
        char *comma = strchr(p, ',');
        if (comma) *comma = 0;
        strncpy((char *)slots[i].ssid, p, sizeof(slots[i].ssid) - 1);
        i++; p = comma ? comma + 1 : NULL;
    }
}
static void starts(const char *list, int want_reconnect) {
    set(list);
    assert(wcm_start());
    assert(reconnect == want_reconnect && prov == !want_reconnect);
}

int main(void) {
    fallback_visible = 0;
    starts("Home", 1);
    starts("mnet2,Home", 1);
    starts("mnet2,,Home", 1);            /* the gap: the original went to the Bluetooth set-up */
    starts(",Home", 1);
    starts(",,,,,,,,,Home", 1);          /* the last slot */
    assert(scans == 0);
    puts("PASS a network after an empty slot is still found at start");
    starts("", 0);
    starts(",,", 0);
    puts("PASS no network at all: the Bluetooth set-up, as before");
    starts("mnet2", 0);
    assert(scans == 1 && scanned_slot_ok);
    starts(",mnet2", 0);                 /* the factory network alone, after a gap: looked for by its own slot */
    assert(scans == 1 && scanned_slot_ok);
    fallback_visible = 1;
    starts("mnet2", 1);
    starts(",,mnet2", 1);
    assert(scans == 1 && scanned_slot_ok);
    puts("PASS the factory network alone: looked for wherever it is, set-up only when it is not there");
    return 0;
}
