"""The time from the page, and the Wi-Fi command that cannot work on a Jooki 2 (2.1.4), on the bench.
The bench's clock is set, so the core must leave it alone: the "clock unset" path (1970 after a start
without Internet) is covered by the specs and was tried on a real Jooki.   python3 test_clock.py"""
import json, os, subprocess, time
import paho.mqtt.client as mqtt
from playwright.sync_api import sync_playwright
from jk import Jooki, PAGE
LUA = os.environ.get("PLAYER_LUA", "core")
URL = PAGE
R = []
def check(n, c, info=""):
    R.append((n, bool(c))); print(("PASS " if c else "FAIL ") + n + ("" if c else "  -> " + str(info)[:300]))

subprocess.run(["bash", "setup.sh"], capture_output=True)
subprocess.run(["python3", "seed_demo.py"], capture_output=True)
subprocess.run(["./deploy_ui.sh"], capture_output=True)
open("/tmp/bench_services.log", "a").close()
services_before = open("/tmp/bench_services.log").read()
subprocess.run(["./start_player.sh", LUA], capture_output=True); time.sleep(1)
J = Jooki()

# what the page publishes
seen = []
spy = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, "clockspy")
spy.on_message = lambda c, u, m: seen.append((time.time(), m.topic, m.payload.decode(errors="replace")))
spy.connect("127.0.0.1", 1883); spy.subscribe("/j/web/input/OJ_TIME"); spy.loop_start(); time.sleep(0.3)
def times(): return [json.loads(p) for _, t, p in seen]

with sync_playwright() as p:
    b = p.chromium.launch()
    ctx = b.new_context(viewport={"width": 390, "height": 844}, locale="fr-FR", timezone_id="Europe/Paris")
    pg = ctx.new_page(); errs = []
    pg.on("pageerror", lambda e: errs.append(str(e)))
    pg.goto(URL + "/"); pg.wait_for_selector(".pl[data-pl]")
    J.wait(lambda: len(seen) >= 1, 5)
    t = times()
    check("C1 the page gives its time as soon as it connects", len(t) == 1 and abs(t[0].get("utc", 0) - time.time()) < 5, t)
    check("C1 whole UTC seconds, and nothing else (no parent code needed)", len(t) == 1 and set(t[0]) == {"utc"} and isinstance(t[0]["utc"], int), t)
    pg.reload(); pg.wait_for_selector(".pl[data-pl]"); J.wait(lambda: len(seen) >= 2, 5)
    check("C2 again at every connection (a restarted Jooki forgets the time)", len(seen) == 2, times())
    time.sleep(1)
    check("C3 a Jooki whose clock is right says nothing back (no error, no toast)", not J.errors and pg.locator(".toast.error").count() == 0, (J.errors, pg.locator(".toast").all_inner_texts()))
    check("C3 no page error", not errs, errs)
    b.close()

# the core's side, straight on the bus
J.errors.clear()
J.send("OJ_TIME", {"utc": 12}); J.wait(lambda: J.errors, 3)
check("C4 an impossible time (1970) is refused", any(e.get("msg") == "invalid utc" for e in J.errors), J.errors)
J.errors.clear()
J.send("OJ_PARENT_SET", {"code": "4321"}); J.settle()
J.send("OJ_TIME", {"utc": int(time.time())}); J.settle(1)
check("C5 with a parent code set, the time never asks for it", not any(e.get("msg") == "PARENT_CODE_REQUIRED" for e in J.errors), J.errors)
J.send("OJ_PARENT_CLEAR", {"current": "4321"}); J.settle()
J.errors.clear()
J.send("SET_WIFI", {"ssid": "Holiday home", "password": "pass1234"}); J.wait(lambda: J.errors, 3)
check("C6 SET_WIFI says the Wi-Fi goes over Bluetooth", any(e.get("msg") == "WIFI_OVER_BLUETOOTH" for e in J.errors), J.errors)
check("C6 without sending the password back to the pages", "pass1234" not in json.dumps(J.errors), J.errors)
time.sleep(0.5)
new = open("/tmp/bench_services.log").read()[len(services_before):]
check("C6 and runs nothing (no Jooki 1 script, no voice switched to English)", "wifi_add_network" not in new and "lang_set" not in new, new[-300:])
J.close(); spy.loop_stop()
print("%d/%d passed" % (sum(1 for _, c in R if c), len(R)))
raise SystemExit(0 if all(c for _, c in R) else 1)
