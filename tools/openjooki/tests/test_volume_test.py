"""Settings auditions: real core, MQTT acknowledgments, a bounded fake PCM player and Chromium.
The PCM file is real; audible levels additionally need a physical Jooki.
"""
import datetime
import json
from pathlib import Path
import threading
import wave

import paho.mqtt.client as mqtt
from playwright.sync_api import sync_playwright
import bench as B
from jk import PAGE

R = B.Results()
seen, lock = [], threading.Lock()
api = 2
def hardware(cl, _u, m):
    if m.topic.endswith("/knobs/state"):
        cl.publish("/j/esp32/input/knobs/state", json.dumps({"volume": 8, "hp_state": 0, "volume_api": api}))
    elif m.topic.endswith("/set_volume"):
        with lock:
            seen.append(json.loads(m.payload))
        cl.publish("/j/esp32/input/audio/volume", "0")

ctrl = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, "volume-test-hardware")
ctrl.on_message = hardware
ctrl.connect("127.0.0.1", 1883)
ctrl.subscribe("/j/esp32/output/#")
ctrl.loop_start()
player = Path("/usr/bin/aplay")
old_player = player.read_bytes() if player.exists() else None
log = Path("/tmp/oj-tone-aplay.log")

def pre():
    log.write_text("")
    Path("/tmp/oj-tone-fail").unlink(missing_ok=True)
    player.write_text('''#!/bin/sh
printf '%s\\n' "$*" >> /tmp/oj-tone-aplay.log
[ ! -f /tmp/oj-tone-fail ] || exit 1
sleep 0.8
''')
    player.chmod(0o755)
    json.dump({"_": {"version": 1}, "enabled": False}, open(B.DB + "/bedtime.json", "w"))

def count():
    return len(log.read_text().splitlines())

def run_test(j, target):
    before = count()
    reply = j.v2("device.test_volume", {"target": target})
    R.check("v2 accepts " + target, reply.get("ok"), reply)
    j.wait(lambda: j.get("audio.volume_test.active"), what="audition status active")
    j.wait(lambda: count() > before, what="tone player started")
    j.wait(lambda: not j.get("audio.volume_test.active"), what="tone finished and level restored")
    R.check("tone player completed successfully", not j.get("audio.volume_test.error"), j.get("audio.volume_test"))

try:
    j = B.boot(ui=True, pre=pre)
    j.wait_state("device.volume_api", 2)
    j.send("SET_CFG", {"toy_safe_maxvol": 60})
    j.send("SET_VOL", {"vol": 15})
    j.send("OJ_BEDTIME_SET", {"maxvol": 40})
    j.wait_state("audio.config.volume", 15)
    saved = Path(B.DB + "/audiocfg.json").read_bytes()
    mark = len(seen)
    run_test(j, "night")
    R.check("daytime night preview reaches 40", j.get("audio.volume_test.percent") == 40)
    levels = []
    for x in seen[mark:]:
        if not levels or levels[-1] != x["percent"]:
            levels.append(x["percent"])
    R.check("ESP receives 0, 40, restored 15 in order", levels[-3:] == [0, 40, 15], levels)
    R.check("no saved volume/settings changes", Path(B.DB + "/audiocfg.json").read_bytes() == saved)

    book = j.newpl("Book", ["media/song1.mp3"], audiobook=True)
    j.send("PLAYLIST_PLAY", {"playlistId": book})
    j.wait_state("audio.playback.state", "PLAYING")
    run_test(j, "kids")
    R.expect("local book continues on the same chapter", lambda: j.pb == "PLAYING" and j.np.get("playlistId") == book)
    j.send("DO_PAUSE", {})
    j.wait_state("audio.playback.state", "PAUSED")
    run_test(j, "night")
    R.check("previously paused book stays paused", j.pb == "PAUSED")

    now = datetime.datetime.now(datetime.timezone.utc)
    m = now.hour * 60 + now.minute
    def hm(n):
        return "%02d:%02d" % ((n % 1440) // 60, n % 60)
    j.send("OJ_BEDTIME_SET", {"enabled": True, "tzbase": 0, "tzdst": "none", "start": hm(m-60), "stop": hm(m+60), "maxvol": 30})
    j.wait_state("bedtime.night", True)
    run_test(j, "kids")
    R.check("kids audition respects the active night maximum", j.get("audio.volume_test.percent") == 30)
    j.send("OJ_BEDTIME_SET", {"start": hm(m+60), "stop": hm(m+120), "maxvol": 40})
    j.wait_state("bedtime.night", False)

    j.send("OJ_PARENT_SET", {"code": "9876"}); j.wait_state("maintenance.parent", True)
    before = count()
    reply = j.v2("device.test_volume", {"target": "night"})
    R.check("v2 parent protection", not reply.get("ok") and reply.get("error", {}).get("code") == "forbidden", reply)
    j.errors.clear(); j.send("OJ_VOLUME_TEST", {"target": "night"}); j.barrier()
    R.check("v1 parent protection", j.errors and count() == before)
    j.send("OJ_PARENT_CLEAR", {"current": "9876"}); j.wait_state("maintenance.parent", False)

    Path("/tmp/oj-tone-fail").touch()
    before = count(); j.send("OJ_VOLUME_TEST", {"target": "night"})
    j.wait(lambda: count() > before)
    j.wait(lambda: j.get("audio.volume_test.error") == "VOLUME_TEST_FAILED" and not j.get("audio.volume_test.active"))
    R.check("a failed player restores the level and reports failure", j.get("audio.volume_test.error") == "VOLUME_TEST_FAILED" and seen[-1]["percent"] == 15)
    Path("/tmp/oj-tone-fail").unlink()

    with sync_playwright() as p:
        browser = p.chromium.launch(args=["--no-sandbox"])
        pg = browser.new_page(viewport={"width": 390, "height": 844}, locale="de-DE", timezone_id="UTC")
        errors = []
        pg.on("pageerror", lambda e: errors.append(str(e)))
        pg.goto(PAGE + "/#/settings/sound")
        pg.wait_for_selector("[data-k=testvol-kids]", timeout=15000)
        R.check("German kids button is beside the new maximum", pg.locator("[data-k=testvol-kids]").inner_text() == "Testen")
        n = count(); pg.click("[data-k=testvol-kids]")
        j.wait_state("audio.volume_test.active", True)
        j.wait(lambda: count() > n)
        R.check("button disabled while testing", pg.locator("[data-k=testvol-kids]").is_disabled())
        j.wait(lambda: not j.get("audio.volume_test.active"))
        pg.goto(PAGE + "/#/settings/night")
        pg.wait_for_selector("[data-k=testvol-night]")
        n = count(); pg.click("[data-k=testvol-night]")
        j.wait_state("audio.volume_test.active", True)
        j.wait(lambda: count() > n)
        j.wait(lambda: not j.get("audio.volume_test.active"))
        R.check("night button works before night starts", not j.get("bedtime.night") and j.get("audio.volume_test.percent") == 40, (j.bt, j.get("audio.volume_test")))
        R.check("no horizontal overflow on a narrow screen", pg.evaluate("document.documentElement.scrollWidth <= innerWidth"))
        R.check("no test button in the player", pg.locator(".player [data-k^=testvol], .mini-player [data-k^=testvol]").count() == 0)
        R.check("no browser exceptions", not errors, errors)
        Path("/tmp/volume-test-night.png").parent.mkdir(exist_ok=True)
        pg.screenshot(path="/tmp/volume-test-night.png", full_page=True)
        pg.goto(PAGE + "/#/settings/sound"); pg.wait_for_selector("[data-k=testvol-kids]")
        pg.screenshot(path="/tmp/volume-test-kids.png", full_page=True)
        browser.close()
    api = 0
    ctrl.publish("/j/esp32/input/knobs/state", json.dumps({"volume": 8, "hp_state": 0, "volume_api": 0}))
    j.wait_state("device.volume_api", 0)
    run_test(j, "night")
    R.check("stock firmware test stays below the dial", j.get("audio.volume_test.percent") == 8)
    with wave.open(str(Path(B.HERE).parent / "webui/volume-test.wav")) as tone:
        R.check("bounded, mono PCM tone", tone.getnchannels() == 1 and tone.getsampwidth() == 2 and tone.getnframes()/tone.getframerate() == 0.8)
    j.close()
finally:
    ctrl.loop_stop(); ctrl.disconnect()
    if old_player is None:
        player.unlink(missing_ok=True)
    else:
        player.write_bytes(old_player)
    Path("/tmp/oj-tone-fail").unlink(missing_ok=True)
R.finish(list_failed=True)
