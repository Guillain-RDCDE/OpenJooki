#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include "commands.h"
#include "esp_hosted_config.pb-c.h"
#include "transport_pserial.h"
static int mode, calls, percent;
static bool wrong_knobs;
static unsigned maximum;
void *esp_hosted_calloc(size_t n, size_t size) { return calloc(n, size); }
void esp_hosted_free(void *p) { free(p); }
uint8_t *transport_pserial_data_handler(uint8_t *data, uint16_t len, uint8_t wait, uint32_t *out_len) {
    (void)wait; ++calls;
    EspHostedConfigPayload *req = esp_hosted_config_payload__unpack(NULL, len, data);
    assert(req);
    EspHostedConfigPayload resp = ESP_HOSTED_CONFIG_PAYLOAD__INIT;
    EspHostedRespSetVolume vol = ESP_HOSTED_RESP_SET_VOLUME__INIT;
    EspHostedRespKnobsState knobs = ESP_HOSTED_RESP_KNOBS_STATE__INIT;
    if (req->msg == ESP_HOSTED_CONFIG_MSG_TYPE__TypeCmdGetKnobsState) {
        resp.msg = wrong_knobs ? 69 : ESP_HOSTED_CONFIG_MSG_TYPE__TypeRespGetKnobsState;
        resp.payload_case = ESP_HOSTED_CONFIG_PAYLOAD__PAYLOAD_RESP_GET_KNOBS_STATE;
        knobs.volume = 5; knobs.volume_api = mode; resp.resp_get_knobs_state = &knobs;
    } else {
        assert(req->msg == 86 && req->payload_case == 92);
        assert(req->cmd_set_volume->percent == percent);
        assert(req->cmd_set_volume->maximum_plus_one == maximum);
        resp.msg = mode == 1 ? 69 : 87;
        resp.payload_case = mode == 2 ? 0 : 93;
        vol.result = mode == 3 ? -1 : 0;
        resp.resp_set_volume = &vol;
    }
    esp_hosted_config_payload__free_unpacked(req, NULL);
    if (mode == 5) { *out_len = 0; return NULL; }
    if (mode == 4) { *out_len = 1; uint8_t *bad = malloc(1); *bad = 0xff; return bad; }
    *out_len = esp_hosted_config_payload__get_packed_size(&resp);
    uint8_t *out = malloc(*out_len);
    esp_hosted_config_payload__pack(&resp, out);
    return out;
}
int main(void) {
    // No capability field in an old response: the new controller must report 0.
    knobs_state_t knobs;
    for (mode = 0; mode <= 2; ++mode) { assert(get_knobs_state(&knobs) == 0); assert(knobs.volume_api == (unsigned)mode); }
    wrong_knobs = true; mode = 1; assert(get_knobs_state(&knobs) == -1); wrong_knobs = false;
    mode = 0; percent = 0; maximum = 1; assert(set_volume(percent, maximum) == 0);
    percent = 90; maximum = 36; assert(set_volume(percent, maximum) == 0);
    percent = 100; maximum = 101; assert(set_volume(percent, maximum) == 0);
    maximum = 0; assert(set_volume(percent, maximum) == 0); // optional ceiling omitted
    for (mode = 1; mode <= 5; ++mode) assert(set_volume(percent, maximum) == -1);
    int before = calls;
    assert(set_volume(-1, 101) == -1); assert(set_volume(101, 101) == -1); assert(set_volume(50, 102) == -1);
    assert(calls == before);
    puts("PASS actual controller protobuf requests, optional/zero ceiling, legacy capability, failures and malformed replies");
}
