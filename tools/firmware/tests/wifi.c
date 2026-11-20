/* Exercise the actual patched Wi-Fi roaming bodies (wcm_sta.c) and the last
 * connection bookkeeping (wcm_nvs.c) with a fake Wi-Fi driver. ASan/UBSan
 * check the record arrays and the "no last connection" write. */
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define __unused __attribute__((unused))
typedef int esp_err_t;
#define ESP_OK 0
#define ESP_FAIL -1
typedef const char *esp_event_base_t;
static const char wifi_event_base[] = "WIFI_EVENT", ip_event_base[] = "IP_EVENT";
#define WIFI_EVENT wifi_event_base
#define IP_EVENT ip_event_base
enum { WIFI_EVENT_STA_CONNECTED = 4, WIFI_EVENT_STA_DISCONNECTED = 5 };
enum { IP_EVENT_STA_GOT_IP = 0 };
enum {
    WIFI_REASON_AUTH_EXPIRE = 2, WIFI_REASON_AUTH_LEAVE = 3, WIFI_REASON_NOT_ASSOCED = 7,
    WIFI_REASON_ASSOC_LEAVE = 8, WIFI_REASON_4WAY_HANDSHAKE_TIMEOUT = 15, WIFI_REASON_BEACON_TIMEOUT = 200, WIFI_REASON_NO_AP_FOUND = 201,
    WIFI_REASON_AUTH_FAIL = 202, WIFI_REASON_ASSOC_FAIL = 203, WIFI_REASON_HANDSHAKE_TIMEOUT = 204,
};
typedef enum { WIFI_IF_STA = 0 } wifi_interface_t;
#define ESP_IF_WIFI_STA WIFI_IF_STA
typedef enum { WIFI_SCAN_TYPE_ACTIVE = 0, WIFI_SCAN_TYPE_PASSIVE } wifi_scan_type_t;
typedef struct {
    uint8_t bssid[6];
    uint8_t ssid[33];
    uint8_t primary;
    int8_t rssi;
} wifi_ap_record_t;
typedef struct {
    uint8_t *ssid;
    uint8_t *bssid;
    uint8_t channel;
    bool show_hidden;
    wifi_scan_type_t scan_type;
} wifi_scan_config_t;
typedef struct {
    struct {
        uint8_t ssid[32];
        uint8_t password[64];
        bool bssid_set;
        uint8_t bssid[6];
        uint8_t channel;
    } sta;
} wifi_config_t;
typedef struct {
    uint8_t ssid[32];
    uint8_t ssid_len;
    uint8_t bssid[6];
    uint8_t reason;
} wifi_event_sta_disconnected_t;
typedef esp_err_t (*wifi_rxcb_t)(void *buffer, uint16_t len, void *eb);

#define LOG_TAG_WCM_STA "WCM_STA"
#define LOG_TAG_WCM_NVS "WCM_NVS"
#define LOG_INFO(tag, ...) ((void)(tag))
#define LOG_WARNING(tag, ...) ((void)(tag))
#define LOG_ERROR(tag, ...) ((void)(tag))
#define WCM_CONNECT_MINIMUM_RSSI -76
#define JK_MAX_STA_CONF_CNT 10

typedef enum { eInit, eConnect, eConnFailed, eConnected, eDisconnect, eDisconFailed,
               eDisconnected, eReconnect, eGotIP } wcm_sta_evt_t;
typedef enum { sIdle, sConnecting, sConnected, sDisconnecting, sDisconnected, sError } wcm_sta_state_t;
typedef enum {
    WCM_STA_CONNECTION_STATE_NEVER_TRIED,
    WCM_STA_CONNECTION_STATE_NON_WORKING,
    WCM_STA_CONNECTION_STATE_WORKING,
    WCM_STA_CONNECTION_STATE_NETWORK_NOT_AVAILABLE
} WcmStaConnectionState;

static wcm_sta_state_t _state;
static volatile bool _isCurrentlyConnected;
static int _wifiConfigurationIndex;
static WcmStaConnectionState _connectionStates[JK_MAX_STA_CONF_CNT];
static volatile bool _roaming;
static uint8_t _roamBssid[6];
static uint8_t _roamChannel;

/* ---------------------------------------------------------- fake driver */
static wifi_ap_record_t current, scanned[40];
static int scanned_count, ap_info_error, scan_error, records_error, disconnect_error;
static int get_config_error, set_config_error, connect_error;
static int scans, disconnects, connects, set_configs, pushes, notifies;
static wcm_sta_evt_t pushed[8];
static wifi_scan_config_t last_scan;
static char scan_ssid[33];
static wifi_config_t driver_config;
static wifi_rxcb_t rxcb = (wifi_rxcb_t)1;

esp_err_t esp_wifi_sta_get_ap_info(wifi_ap_record_t *ap) {
    if (ap_info_error) return ESP_FAIL;
    *ap = current;
    return ESP_OK;
}
esp_err_t esp_wifi_scan_start(const wifi_scan_config_t *conf, bool block) {
    assert(block && conf && conf->ssid);
    last_scan = *conf;
    strncpy(scan_ssid, (const char *)conf->ssid, sizeof(scan_ssid) - 1);
    ++scans;
    return scan_error ? ESP_FAIL : ESP_OK;
}
esp_err_t esp_wifi_scan_get_ap_records(uint16_t *number, wifi_ap_record_t *records) {
    if (records_error) return ESP_FAIL;
    int n = scanned_count < *number ? scanned_count : *number;
    memcpy(records, scanned, sizeof(wifi_ap_record_t) * (size_t)n);
    *number = (uint16_t)n;
    return ESP_OK;
}
esp_err_t esp_wifi_disconnect(void) { ++disconnects; return disconnect_error ? ESP_FAIL : ESP_OK; }
esp_err_t esp_wifi_get_config(wifi_interface_t i, wifi_config_t *c) {
    assert(i == WIFI_IF_STA);
    if (get_config_error) return ESP_FAIL;
    *c = driver_config;
    return ESP_OK;
}
esp_err_t esp_wifi_set_config(wifi_interface_t i, wifi_config_t *c) {
    assert(i == WIFI_IF_STA);
    ++set_configs;
    if (set_config_error) return ESP_FAIL;
    driver_config = *c;
    return ESP_OK;
}
esp_err_t esp_wifi_connect(void) { ++connects; return connect_error ? ESP_FAIL : ESP_OK; }
esp_err_t esp_wifi_internal_reg_rxcb(wifi_interface_t i, wifi_rxcb_t cb) { assert(i == WIFI_IF_STA); rxcb = cb; return ESP_OK; }
static esp_err_t wlan_sta_rx_callback(void *buffer, uint16_t len, void *eb) { (void)buffer; (void)len; (void)eb; return ESP_OK; }
static bool wcm_sta_push_event(wcm_sta_evt_t evt, bool reset) {
    (void)reset;
    assert(pushes < 8);
    pushed[pushes++] = evt;
    return true;
}
static void notify_wifi(int from, int to, int evt) { (void)from; (void)to; (void)evt; ++notifies; }

/* ------------------------------------------------- fake NVS for wcm_nvs.c */
typedef struct {
    uint8_t ssid[32];
    uint8_t password[64];
    uint8_t channel;
} wcm_wifi_config_t;
typedef struct {
    wcm_wifi_config_t connected_aps[JK_MAX_STA_CONF_CNT];
    int lastConnectedApIdx;
} wcm_db_t;
/* on the heap, so that ASan sees a write just before the array */
static wcm_db_t *db;
#define wcm_nvs (*db)
#define pdFALSE 0
#define pdTRUE 1
#define pdMS_TO_TICKS(ms) (ms)
#define WCM_MUTEX_MAX_WAIT_MS 1000
static int mut_wcm_nvs, nvs_locked, saves;
static int xSemaphoreTake(int m, int wait) { (void)m; (void)wait; assert(!nvs_locked); nvs_locked = 1; return pdTRUE; }
static void xSemaphoreGive(int m) { (void)m; assert(nvs_locked); nvs_locked = 0; }
static bool wcm_nvs_save_db(void) { ++saves; return true; }

#include "wifi_functions.inc"

/* ----------------------------------------------------------------- tests */
static wifi_ap_record_t ap(uint8_t last, const char *ssid, int8_t rssi, uint8_t channel) {
    wifi_ap_record_t r = {{0x24, 0x65, 0x11, 0, 0, last}, {0}, channel, rssi};
    strncpy((char *)r.ssid, ssid, sizeof(r.ssid) - 1);
    return r;
}
static void reset(void) {
    current = ap(1, "Home", -78, 6);
    scanned_count = 0;
    ap_info_error = scan_error = records_error = disconnect_error = 0;
    get_config_error = set_config_error = connect_error = 0;
    scans = disconnects = connects = set_configs = pushes = notifies = 0;
    memset(&driver_config, 0, sizeof(driver_config));
    memcpy(driver_config.sta.ssid, "Home", 4);
    memcpy(driver_config.sta.password, "secret", 6);
    _state = sConnected;
    _isCurrentlyConnected = true;
    _roaming = false;
    _wifiConfigurationIndex = 0;
    memset(_connectionStates, 0, sizeof(_connectionStates));
    _connectionStates[0] = WCM_STA_CONNECTION_STATE_WORKING;
    memset(_roamBssid, 0, sizeof(_roamBssid));
    _roamChannel = 0;
    rxcb = (wifi_rxcb_t)wlan_sta_rx_callback;
}
static void event(int32_t id, uint8_t reason) {
    wifi_event_sta_disconnected_t d = {{0}, 0, {0}, reason};
    wcm_sta_station_event_handler(NULL, WIFI_EVENT, id, &d);
}

static void test_pick(void) {
    const uint8_t *me = current.bssid, *ssid = current.ssid;
    wifi_ap_record_t r[4];
    reset();
    r[0] = ap(1, "Home", -50, 6);                       /* itself, whatever its scanned level */
    r[1] = ap(2, "Home", -71, 1);                       /* only 7 dB better */
    assert(wcm_sta_roam_pick(-78, me, ssid, r, 2) == -1);
    r[1] = ap(2, "Home", -70, 1);                       /* 8 dB better */
    assert(wcm_sta_roam_pick(-78, me, ssid, r, 2) == 1);
    r[2] = ap(3, "Home", -55, 11);                      /* the strongest wins */
    r[3] = ap(4, "Neighbour", -30, 11);                 /* another network never */
    assert(wcm_sta_roam_pick(-78, me, ssid, r, 4) == 2);
    assert(wcm_sta_roam_pick(WCM_STA_ROAM_RSSI, me, ssid, r, 4) == -1);   /* good enough: stay */
    assert(wcm_sta_roam_pick(WCM_STA_ROAM_RSSI - 1, me, ssid, r, 4) == 2);
    r[0] = ap(5, "Home", -77, 6);                       /* better, but under the connect threshold */
    assert(wcm_sta_roam_pick(-90, me, ssid, r, 1) == -1);
    r[0] = ap(5, "Home", WCM_CONNECT_MINIMUM_RSSI, 6);
    assert(wcm_sta_roam_pick(-90, me, ssid, r, 1) == 0);
    r[0] = ap(5, "Homeless", -40, 6);                   /* a longer name is another network */
    assert(wcm_sta_roam_pick(-90, me, ssid, r, 1) == -1);
    assert(wcm_sta_roam_pick(-90, me, ssid, r, 0) == -1);
    puts("PASS roaming picks only a clearly stronger access point of the same network");
}

static void test_check(void) {
    reset(); _state = sConnecting;
    assert(wcm_sta_roam_check() == WCM_STA_ROAM_CHECK_MS && scans == 0);
    reset(); _isCurrentlyConnected = false;
    assert(wcm_sta_roam_check() == WCM_STA_ROAM_CHECK_MS && scans == 0);
    reset(); _roaming = true;
    assert(wcm_sta_roam_check() == WCM_STA_ROAM_CHECK_MS && scans == 0);
    reset(); ap_info_error = 1;
    assert(wcm_sta_roam_check() == WCM_STA_ROAM_CHECK_MS && scans == 0);
    reset(); current.rssi = -60;
    assert(wcm_sta_roam_check() == WCM_STA_ROAM_CHECK_MS && scans == 0);
    puts("PASS a good link, or a station that is not connected, is never scanned");

    reset();
    assert(wcm_sta_roam_check() == WCM_STA_ROAM_SCAN_MS && scans == 1 && disconnects == 0);
    assert(!strcmp(scan_ssid, "Home"));
    assert(last_scan.scan_type == WIFI_SCAN_TYPE_ACTIVE && !last_scan.show_hidden && last_scan.channel == 0);
    reset(); scan_error = 1; scanned[0] = ap(2, "Home", -50, 1); scanned_count = 1;
    assert(wcm_sta_roam_check() == WCM_STA_ROAM_SCAN_MS && disconnects == 0 && !_roaming);
    reset(); records_error = 1; scanned_count = 1;
    assert(wcm_sta_roam_check() == WCM_STA_ROAM_SCAN_MS && disconnects == 0 && !_roaming);
    puts("PASS a weak link is scanned for its own network, then waits a minute when nothing is better");

    reset();
    for (int i = 0; i < 40; i++) scanned[i] = ap((uint8_t)(10 + i), "Home", -90, 1);
    scanned[39] = ap(9, "Home", -40, 11);               /* beyond the 30 records kept */
    scanned_count = 40;
    assert(wcm_sta_roam_check() == WCM_STA_ROAM_SCAN_MS && disconnects == 0);
    puts("PASS at most 30 scan records are read");

    reset(); scanned[0] = current; scanned[1] = ap(2, "Home", -52, 11); scanned_count = 2;
    assert(wcm_sta_roam_check() == WCM_STA_ROAM_SCAN_MS);
    assert(disconnects == 1 && _roaming && _roamChannel == 11 && _roamBssid[5] == 2);
    reset(); disconnect_error = 1; scanned[0] = ap(2, "Home", -52, 11); scanned_count = 1;
    assert(wcm_sta_roam_check() == WCM_STA_ROAM_SCAN_MS && disconnects == 1 && !_roaming);
    puts("PASS a stronger access point is chosen and the current one is left for it");
}

static void test_events(void) {
    /* the station leaves on purpose: no failure, the chosen access point is joined */
    reset(); scanned[0] = ap(2, "Home", -52, 11); scanned_count = 1;
    wcm_sta_roam_check();
    event(WIFI_EVENT_STA_DISCONNECTED, WIFI_REASON_ASSOC_LEAVE);
    assert(!_roaming && !_isCurrentlyConnected && rxcb == NULL);
    assert(connects == 1 && pushes == 0 && _connectionStates[0] == WCM_STA_CONNECTION_STATE_WORKING);
    assert(driver_config.sta.bssid_set && driver_config.sta.bssid[5] == 2 && driver_config.sta.channel == 11);
    assert(!memcmp(driver_config.sta.ssid, "Home", 4) && !memcmp(driver_config.sta.password, "secret", 6));
    event(WIFI_EVENT_STA_CONNECTED, 0);
    assert(_isCurrentlyConnected && rxcb == (wifi_rxcb_t)wlan_sta_rx_callback);
    assert(pushes == 1 && pushed[0] == eConnected && _connectionStates[0] == WCM_STA_CONNECTION_STATE_WORKING);
    puts("PASS leaving for a stronger access point is not a failed connection");

    /* a later drop on the new access point is handled as usual */
    event(WIFI_EVENT_STA_DISCONNECTED, WIFI_REASON_NO_AP_FOUND);
    assert(pushes == 2 && pushed[1] == eConnFailed && _connectionStates[0] == WCM_STA_CONNECTION_STATE_NON_WORKING);
    assert(!_isCurrentlyConnected && connects == 1);

    for (int step = 0; step < 3; step++) {
        reset(); scanned[0] = ap(2, "Home", -52, 11); scanned_count = 1;
        wcm_sta_roam_check();
        if (step == 0) get_config_error = 1;
        if (step == 1) set_config_error = 1;
        if (step == 2) connect_error = 1;
        event(WIFI_EVENT_STA_DISCONNECTED, WIFI_REASON_ASSOC_LEAVE);
        assert(!_roaming && pushes == 1 && pushed[0] == eConnFailed);
        assert(_connectionStates[0] == WCM_STA_CONNECTION_STATE_NON_WORKING && !_isCurrentlyConnected);
    }
    puts("PASS a move that cannot start falls back to the usual reconnection");

    reset();
    event(WIFI_EVENT_STA_DISCONNECTED, WIFI_REASON_BEACON_TIMEOUT);
    assert(connects == 0 && set_configs == 0 && pushes == 1 && pushed[0] == eConnFailed);
    puts("PASS a lost connection is handled as before");
}

static void test_last_connection(void) {
    db = calloc(1, sizeof(*db));
    assert(db);
    memcpy(db->connected_aps[2].ssid, "Home", 4);
    db->lastConnectedApIdx = 2;
    wcm_nvs_set_last_connected_ap_idx(2, 6);
    assert(db->lastConnectedApIdx == 2 && db->connected_aps[2].channel == 6 && saves == 1);
    wcm_nvs_set_last_connected_ap_idx(2, 6);
    assert(saves == 1);
    wcm_nvs_set_last_connected_ap_idx(-1, 0);           /* wrote connected_aps[-1] */
    assert(db->lastConnectedApIdx == -1 && saves == 2 && db->connected_aps[2].channel == 6);
    wcm_nvs_set_last_connected_ap_idx(5, 3);            /* empty slot: "none" */
    assert(db->lastConnectedApIdx == -1 && saves == 2);
    wcm_nvs_set_last_connected_ap_idx(2, 99);           /* bad channel stored as 0 */
    assert(db->lastConnectedApIdx == 2 && db->connected_aps[2].channel == 0 && saves == 3 && !nvs_locked);
    free(db);
    puts("PASS forgetting the last connection writes nothing outside the list");
}

int main(void) {
    test_pick();
    test_check();
    test_events();
    test_last_connection();
    return 0;
}
