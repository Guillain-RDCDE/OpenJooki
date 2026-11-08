#include <assert.h>
#include <stdio.h>
#include "volume_control.h"
#include "volume_request.h"
int main(void) {
    // Every percentage and ceiling, with the host request arriving before or
    // after the first ADC reading. Repeated sampling must never take it back.
    for (int requested = 0; requested <= 100; ++requested) {
        for (unsigned ceiling = 0; ceiling <= 100; ++ceiling) {
            for (int first = 0; first < 2; ++first) {
                oj_volume_t state = OJ_VOLUME_INITIAL;
                if (first) oj_volume_knob(&state, 5);
                assert(oj_volume_host(&state, requested, ceiling + 1));
                for (int sample = 0; sample < 100; ++sample) {
                    oj_volume_knob(&state, 5);
                    assert(oj_volume_output(&state, false) == (requested < (int)ceiling ? requested : (int)ceiling));
                    assert(oj_volume_output(&state, true) == 0);
                }
                oj_volume_knob(&state, 95);
                assert(state.requested == 95);
                assert(oj_volume_output(&state, false) == (ceiling < 95 ? (int)ceiling : 95));
            }
        }
    }
    puts("PASS all 101 volume values and ceilings, repeated ADC sampling and both startup orders");
    oj_volume_t s = OJ_VOLUME_INITIAL;
    oj_volume_knob(&s, 5);
    assert(oj_volume_host(&s, 80, 101));
    for (int i = 0; i < 100; ++i) { oj_volume_knob(&s, 5); assert(oj_volume_output(&s, false) == 80); }
    oj_volume_knob(&s, 12); assert(oj_volume_output(&s, false) == 12);
    // Boot can receive Linux's saved value before the first ADC sample.
    s = (oj_volume_t) OJ_VOLUME_INITIAL;
    assert(oj_volume_host(&s, 75, 36));
    oj_volume_knob(&s, 5); assert(oj_volume_output(&s, false) == 35);
    oj_volume_knob(&s, 90); assert(s.requested == 90 && oj_volume_output(&s, false) == 35);
    assert(oj_volume_output(&s, true) == 0); assert(oj_volume_output(&s, false) == 35);
    assert(oj_volume_host(&s, 90, 1)); oj_volume_knob(&s, 40); assert(oj_volume_output(&s, false) == 0);
    assert(oj_volume_host(&s, 90, 101)); assert(oj_volume_output(&s, false) == 90);
    assert(!oj_volume_host(&s, 101, 101)); assert(!oj_volume_host(&s, -1, 101)); assert(!oj_volume_host(&s, 80, 102));
    assert(s.requested == 90 && s.maximum == 100);
    assert(oj_volume_host(&s, 70, 0)); assert(s.maximum == 100); // omitted ceiling preserves it
    int p, m;
    const char *good[] = { "{\"percent\":0,\"maximum\":0}", " { \"maximum\" : 35, \"percent\" : 90 } ", "{\"percent\":100}" };
    const int ps[] = { 0, 90, 100 }, ms[] = { 0, 35, -1 };
    for (unsigned i = 0; i < sizeof(good)/sizeof(*good); ++i) {
        assert(oj_volume_request(good[i], strlen(good[i]), &p, &m)); assert(p == ps[i] && m == ms[i]);
    }
    const char *bad[] = { "{}", "{\"percent\":101}", "{\"percent\":-1}", "{\"percent\":2.5}", "{\"percent\":\"80\"}",
        "{\"percent\":true}", "{\"percent\":null}", "{\"percent\":01}", "{\"percent\":0}x", "{\"percent\":0,}",
        "{\"percent\":0,\"percent\":80}", "{\"maximum\":80}", "{\"percent\":80,\"maximum\":101}", "{\"percent\":80,\"extra\":1}", "{\"percent\":999999999999999999999999999999}" };
    for (unsigned i = 0; i < sizeof(bad)/sizeof(*bad); ++i) assert(!oj_volume_request(bad[i], strlen(bad[i]), &p, &m));
    puts("PASS firmware volume arbitration, ceilings, mute, startup and request validation");
}
