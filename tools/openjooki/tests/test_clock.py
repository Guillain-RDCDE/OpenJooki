"""The time from the page, and the Wi-Fi command that cannot work on a Jooki 2 (2.1.4), on the bench.
The bench's clock is set, so the core must leave it alone: the "clock unset" path (1970 after a start
without Internet) is covered by the specs and was tried on a real Jooki.   python3 test_clock.py"""
import json, time
from playwright.sync_api import sync_playwright
import bench as B
from jk import PAGE
URL = PAGE
R = B.Results(lead=""); check = R.check

J = B.boot(seed=True, ui=True)

# what the page publishes
spy = B.Spy("/j/web/input/OJ_TIME", name="clockspy")
def times(): return [json.loads(p) for _, p in spy.since()]

with sync_playwright() as p:
    b = p.chromium.launch()
    ctx = b.new_context(viewport={"width": 390, "height": 844}, locale="fr-FR", timezone_id="Europe/Paris")
    pg = ctx.new_page(); errs = []
    pg.on("pageerror", lambda e: errs.append(str(e)))
    pg.goto(URL + "/"); pg.wait_for_selector(".pl[data-pl]")
    B.poll(lambda: spy.mark() >= 1, 5)
    t = times()
    check("C1 the page gives its time as soon as it connects", len(t) == 1 and abs(t[0].get("utc", 0) - time.time()) < 5, t)
    check("C1 whole UTC seconds, and nothing else (no parent code needed)", len(t) == 1 and set(t[0]) == {"utc"} and isinstance(t[0]["utc"], int), t)
    pg.reload(); pg.wait_for_selector(".pl[data-pl]"); B.poll(lambda: spy.mark() >= 2, 5)
    check("C2 again at every connection (a restarted Jooki forgets the time)", spy.mark() == 2, times())
    B.quiet(1, "a Jooki that disagreed with the time would answer within the second")
    check("C3 a Jooki whose clock is right says nothing back (no error, no toast)", not J.errors and pg.locator(".toast.error").count() == 0, (J.errors, pg.locator(".toast").all_inner_texts()))
    check("C3 no page error", not errs, errs)
    b.close()

# the core's side, straight on the bus
J.errors.clear()
J.send("OJ_TIME", {"utc": 12})
R.expect("C4 an impossible time (1970) is refused", lambda: any(e.get("msg") == "invalid utc" for e in J.errors), 3, lambda: J.errors)
J.errors.clear()
J.send("OJ_PARENT_SET", {"code": "4321"}); J.wait_state("maintenance.parent", True)
J.send("OJ_TIME", {"utc": int(time.time())}); J.barrier()
check("C5 with a parent code set, the time never asks for it", not any(e.get("msg") == "PARENT_CODE_REQUIRED" for e in J.errors), J.errors)
J.send("OJ_PARENT_CLEAR", {"current": "4321"}); J.wait_state("maintenance.parent", False)
J.errors.clear()
J.send("SET_WIFI", {"ssid": "Holiday home", "password": "pass1234"})
R.expect("C6 SET_WIFI says the Wi-Fi goes over Bluetooth", lambda: any(e.get("msg") == "WIFI_OVER_BLUETOOTH" for e in J.errors), 3, lambda: J.errors)
check("C6 without sending the password back to the pages", "pass1234" not in json.dumps(J.errors), J.errors)
J.barrier(); B.quiet(0.3, "a script the core had started would have written its line by now")
new = open(B.SERVICES_LOG).read()          # emptied by setup(): everything this core ran
check("C6 and runs nothing (no Jooki 1 script, no voice switched to English)", "wifi_add_network" not in new and "lang_set" not in new, new[-300:])
J.close(); spy.close()
R.finish()
