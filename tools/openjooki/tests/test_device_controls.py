"""Device controls on the real core and Chromium, with an answering hardware controller on MQTT.
This verifies the bus and browser paths; audible / visible hardware behaviour needs a Jooki.
"""
import datetime
import json
from pathlib import Path
import threading
import paho.mqtt.client as mqtt
from playwright.sync_api import sync_playwright
import bench as B
from jk import PAGE

R = B.Results()
lock = threading.Lock()
seen = []
knob = 8
volume_api = 2
headphones = 0
ctrl = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, "device-controls-hardware")
def knobs_payload():
    payload = {"volume": knob, "hp_state": headphones}
    if volume_api is not None:
        payload["volume_api"] = volume_api
    return json.dumps(payload)
def hardware(cl, _u, m):
    if m.topic == "/j/esp32/output/knobs/state":
        cl.publish("/j/esp32/input/knobs/state", knobs_payload())
    elif m.topic == "/j/ht/output/raw_write":
        with lock: seen.append((m.topic, m.payload.decode()))
        cl.publish("/j/ht/input/raw_read_response", m.payload)
    elif m.topic == "/j/esp32/output/audio/set_volume":
        with lock: seen.append((m.topic, json.loads(m.payload)))
        cl.publish("/j/esp32/input/audio/volume", "0")
ctrl.on_message = hardware
ctrl.connect("127.0.0.1", 1883)
ctrl.subscribe("/j/esp32/output/#")
ctrl.subscribe("/j/ht/output/#")
ctrl.loop_start()
def last(topic):
    with lock:
        return next((p for t, p in reversed(seen) if t == topic), None)
def last_alsa():
    values = Path(B.VOL_LOG).read_text().split()
    return int(values[-1]) if values else None
def last_mixer(control):
    return next((line for line in reversed(Path(B.SERVICES_LOG).read_text().splitlines())
                 if line.startswith("AMIXER ") and control in line), "")
def volume_count():
    with lock:
        return sum(t == VOL for t, _ in seen)
VOL = "/j/esp32/output/audio/set_volume"
LED = "/j/ht/output/raw_write"

def pre():
    json.dump({"_": {"version": 1}, "enabled": False}, open(B.DB + "/bedtime.json", "w"))
j = B.boot(ui=True, pre=pre)
j.send("OJ_BEDTIME_SET", {"enabled": False})
R.expect("web volume reaches ESP32 and ALSA", lambda: last(VOL) is not None)
R.check("factory ceiling migrates to the global scale", j.get("audio.config.toy_safe_maxvol") == 56)
j.send("SET_CFG", {"toy_safe_maxvol": 100})
j.send("SET_VOL", {"vol": 90})
R.expect("low dial permits a higher web value", lambda: last(VOL) == {"percent": 90, "maximum": 100})
for _ in range(4): j.c.publish("/j/esp32/input/knobs/state", '{"volume":8,"hp_state":0,"volume_api":2}')
j.barrier()
R.check("unchanged reports keep the web value", j.get("audio.config.volume") == 90)
knob = 22
j.c.publish("/j/gpio/input/vol_set", '{"vol":22}')
j.wait_state("audio.config.volume", 22)
R.expect("real dial movement reaches both paths", lambda: last(VOL)["percent"] == 22)
j.send("SET_VOL", {"vol": 90})
for maximum in (0, 35, 100):
    j.send("SET_CFG", {"toy_safe_maxvol": maximum})
    R.expect("kids maximum %d on the ESP32" % maximum, lambda: last(VOL) == {"percent": min(90, maximum), "maximum": maximum})
    R.check("requested volume stays 90", j.get("audio.config.volume") == 90)
j.send("SET_CFG", {"toy_safe_maxvol": 35})
j.send("SET_TOY_SAFE", {"enable": False})
R.expect("kids maximum only applies in kids mode", lambda: last(VOL) == {"percent": 90, "maximum": 100})
j.send("SET_TOY_SAFE", {"enable": True})
R.expect("kids mode immediately reapplies the maximum", lambda: last(VOL) == {"percent": 35, "maximum": 35})
now = datetime.datetime.now(datetime.timezone.utc)
minutes = now.hour * 60 + now.minute
def hm(n): return "%02d:%02d" % ((n % 1440) // 60, n % 60)
j.send("OJ_BEDTIME_SET", {"enabled": True, "tzbase": 0, "tzdst": "none", "start": hm(minutes - 60), "stop": hm(minutes + 60), "maxvol": 20})
R.expect("night and parents use the smaller ceiling", lambda: last(VOL) == {"percent": 20, "maximum": 20})
j.send("OJ_BEDTIME_SET", {"enabled": False})
j = B.restart(j)
j.send("OJ_BEDTIME_SET", {"enabled": False})
R.expect("saved web volume and parent limit survive restart", lambda: j.get("audio.config.volume") == 90 and j.get("audio.config.toy_safe_maxvol") == 35 and last(VOL) == {"percent": 35, "maximum": 35}, info=lambda: (j.get("audio.config"), last(VOL)))
for p in ({"toy_safe_maxvol": -1}, {"toy_safe_maxvol": 101}, {"toy_safe_maxvol": 2.5}, {"toy_safe_maxvol": "35"}):
    r = j.v2("device.set_config", p)
    R.check("v2 rejects %r" % p, not r.get("ok") and r.get("error", {}).get("code") == "invalid_argument", r)
j.send("OJ_PARENT_SET", {"code": "9876"})
j.wait_state("maintenance.parent", True)
r = j.v2("device.set_config", {"toy_safe_maxvol": 5})
R.check("v2 protects the limit with the parent code", not r.get("ok") and r.get("error", {}).get("code") == "forbidden", r)
j.errors.clear()
j.send("SET_CFG", {"toy_safe_maxvol": 5})
j.barrier()
R.check("v1 protects the ceiling with the parent code", j.get("audio.config.toy_safe_maxvol") == 35 and j.errors, j.errors)
r = j.v2("device.set_config", {"toy_safe_maxvol": 35}, code="9876")
R.check("correct code permits the setting", r.get("ok"), r)
j.send("OJ_PARENT_CLEAR", {"current": "9876"})
j.wait_state("maintenance.parent", False)
j.errors.clear()
j.nfc("04000000F00001", "101")
j.nfc_off()
j.nfc("04A1B2C3D49C41", "200")
j.nfc_off()

# Old and intermediate firmware keep the factory attenuation, including after
# a live downgrade with an unchanged dial. The answering peer also covers the
# original controller, which omits volume_api altogether.
# On battery: with the charger in, a "plugged" reading is the charger and never switches to
# headphones. The first reading on battery raises usb_mux and the next one is skipped, so four.
j.c.publish("/j/power/input/plugged_in", "0")
j.wait_state("power.connected", False)
for volume_api in (0, 1, None):
    for headphones in (1, 0):
        for _ in range(4):
            j.c.publish("/j/esp32/input/knobs/state", knobs_payload())
        j.wait_state("device.volume_api", volume_api or 0)
        j.wait_state("audio.config.headphones_en", bool(headphones))
        j.barrier()
        before = volume_count()
        for requested in (80, 100):
            j.send("SET_VOL", {"vol": requested})
            # headphones: the mixer is the volume; speaker: above the dial it stays open, at the dial
            R.expect("legacy API %r, headphones %d: request %d reaches ALSA" % (volume_api, headphones, requested),
                     lambda: last_alsa() == (requested if headphones else 100))
            if not headphones:
                j.wait_state("audio.config.volume", knob)
        if not headphones:
            j.send("SET_VOL", {"vol": knob - 10})
            R.expect("legacy API %r: the page lowers the speaker below the dial" % (volume_api,), lambda: last_alsa() == 90)
            j.c.publish("/j/esp32/input/knobs/state", knobs_payload())
            j.barrier()
            R.check("legacy API %r: an unchanged dial keeps the lower level" % (volume_api,), j.get("audio.config.volume") == knob - 10 and last_alsa() == 90)
            j.send("SET_VOL", {"vol": 100})
            R.expect("legacy API %r: back at the dial" % (volume_api,), lambda: last_alsa() == 100)
        j.barrier()
        R.check("legacy API %r, headphones %d: no new ESP32 volume command" % (volume_api, headphones), volume_count() == before)
        R.check("legacy API %r, headphones %d: factory kids attenuation retained" % (volume_api, headphones),
                last_mixer("Toysafe override").endswith(" off"))

# On the charger the page's switch decides (headphones added after the charger cannot be seen);
# on battery it is refused and the detection decides. A charger reads "plugged" on the line.
headphones = 1
j.c.publish("/j/power/input/plugged_in", "1")
j.wait_state("power.connected", True)
j.send("OJ_HEADPHONES", {"on": True})
j.wait_state("audio.config.headphones_en", True)
for _ in range(3):
    j.c.publish("/j/esp32/input/knobs/state", knobs_payload())
j.barrier()
R.check("charger: the switch keeps the headphones", j.get("audio.config.headphones_en") is True)
j.send("OJ_HEADPHONES", {"on": False})
j.wait_state("audio.config.headphones_en", False)
headphones = 0
j.c.publish("/j/power/input/plugged_in", "0")
j.wait_state("power.connected", False)
j.send("OJ_HEADPHONES", {"on": True})
j.barrier()
R.check("battery: the switch is refused", j.get("audio.config.headphones_en") is False)

night_max = knob - 7
j.send("OJ_BEDTIME_SET", {"enabled": True, "tzbase": 0, "tzdst": "none", "start": hm(minutes - 60), "stop": hm(minutes + 60), "maxvol": night_max})
R.expect("legacy speaker takes the night ceiling", lambda: last_alsa() == 93)
j.send("OJ_BEDTIME_SET", {"enabled": False})
R.expect("legacy night ceiling restores the requested level", lambda: last_alsa() == 100)
j.send("SET_CFG", {"hp_boost": True})
R.expect("headphone boost stays at factory gain in kids mode", lambda: last_mixer("MERCURY Playback Volume").endswith(" 31"))
j.send("SET_TOY_SAFE", {"enable": False})
R.expect("headphone boost is available with kids mode off", lambda: last_mixer("MERCURY Playback Volume").endswith(" 37"))
j.send("SET_TOY_SAFE", {"enable": True})
R.expect("kids mode restores the factory headphone gain", lambda: last_mixer("MERCURY Playback Volume").endswith(" 31"))
volume_api = 2
j.c.publish("/j/esp32/input/knobs/state", knobs_payload())
j.send("SET_VOL", {"vol": 90})
R.expect("API 2 restores the shared ceiling after a legacy controller", lambda: last(VOL) == {"percent": 35, "maximum": 35})
R.expect("API 2 bypasses only the fixed attenuation", lambda: last_mixer("Toysafe override").endswith(" on"))

with sync_playwright() as pw:
    browser = pw.chromium.launch(args=["--no-sandbox"])
    pg = browser.new_page(locale="en-GB", viewport={"width":375,"height":812})
    errors=[]
    pg.on("pageerror", lambda e: errors.append(str(e)))
    pg.goto(PAGE + "/#/settings/sound")
    pg.wait_for_selector("[data-k=toysafemax]")
    R.check("one-percent slider and accessible label", pg.get_attribute("[data-k=toysafemax]","step")=="1" and pg.get_attribute("[data-k=toysafemax]","aria-label")=="Maximum volume in kids mode")
    pg.locator("[data-k=toysafemax]").fill("42")
    pg.locator("[data-k=toysafemax]").dispatch_event("change")
    j.wait_state("audio.config.toy_safe_maxvol",42)
    R.expect("browser applies the ceiling",lambda:last(VOL)=={"percent":42,"maximum":42})
    pg.uncheck("[data-k=toysafe]")
    pg.wait_for_function("() => document.querySelector('[data-k=toysafemax]').disabled")
    R.check("disabled outside kids mode",pg.is_disabled("[data-k=toysafemax]"))
    pg.check("[data-k=toysafe]")
    volume_api=0
    j.c.publish("/j/esp32/input/knobs/state",json.dumps({"volume":knob,"hp_state":0,"volume_api":0}))
    pg.wait_for_function("() => !document.querySelector('[data-k=toysafemax]')")
    R.check("legacy firmware does not offer the limit",pg.locator("[data-k=toysafemax]").count()==0)
    R.check("kids mode on: no maximum volume",pg.locator("[data-k=maxvolume]").count()==0)
    pg.uncheck("[data-k=toysafe]")
    pg.wait_for_selector("[data-k=maxvolume]")
    R.check("kids mode off: the maximum volume, 100 by default",
            pg.input_value("[data-k=maxvolume]")=="100" and pg.get_attribute("[data-k=maxvolume]","aria-label")=="Maximum volume")
    pg.locator("[data-k=maxvolume]").fill("10")
    pg.locator("[data-k=maxvolume]").dispatch_event("change")
    j.wait_state("audio.config.max_volume",10)
    R.expect("the maximum lowers the speaker under the dial at once",lambda:last_alsa()==100-(knob-10))
    pg.check("[data-k=toysafe]")
    pg.wait_for_function("() => !document.querySelector('[data-k=maxvolume]')")
    R.check("kids mode back on: the maximum is hidden",pg.locator("[data-k=maxvolume]").count()==0)
    j.send("SET_CFG",{"max_volume":100})
    R.check("narrow layout",pg.evaluate("() => document.documentElement.scrollWidth <= innerWidth"))
    R.check("no browser errors",not errors,errors)
    browser.close()
B.check_clean_log(R, "device controls")
j.close(); ctrl.loop_stop(); ctrl.disconnect()
R.finish()
