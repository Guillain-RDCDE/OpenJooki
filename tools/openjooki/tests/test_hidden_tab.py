#!/usr/bin/env python3
"""A page left in a background tab does not connect again by itself (#47).

In a background tab the browser runs the page's timers once a minute: its pings come too late, the
broker drops it, and connecting again every couple of minutes (GET_STATE + OJ_TIME each time) kept
the Jooki awake. Hidden, the page now waits; back in front, it connects at once. A tab in front
still connects again by itself after a drop.
  python3 test_hidden_tab.py
"""
import bench as B
from playwright.sync_api import sync_playwright

R = B.Results(); check = R.check
j = B.boot(ui=True)


def drop():
    """The broker goes and comes back (as in e2e E14: the bench broker, then the core)."""
    B.kill_brokers(); B.quiet(1, "the broker stays away, like a Wi-Fi hiccup")
    B.start_bench_broker(); B.start_core()
def n(): pg.evaluate("1"); return len(sockets)   # a call into Playwright, so its events are delivered
def on(): return pg.evaluate("() => !!document.querySelector('.conn.on')")   # the page says it is connected
HIDE = """h => { Object.defineProperty(document, 'hidden', { get: () => h, configurable: true });
  Object.defineProperty(document, 'visibilityState', { get: () => h ? 'hidden' : 'visible', configurable: true });
  document.dispatchEvent(new Event('visibilitychange')); }"""

with sync_playwright() as p:
    b = p.chromium.launch(args=["--no-sandbox"])
    pg = b.new_page(viewport={"width": 420, "height": 800})
    errs, sockets = [], []
    pg.on("pageerror", lambda e: errs.append(str(e)))
    pg.on("websocket", lambda ws: sockets.append(ws))
    pg.goto(B.PAGE)
    R.expect("the page connects", on, 15)

    # in front: a drop is followed by a new connection, as before
    k = n(); drop()
    R.expect("in front, the page connects again by itself", lambda: n() > k and on(), 20)

    # hidden: dropped, it stays quiet
    pg.evaluate(HIDE, True)
    k = n(); drop()
    R.expect("hidden, the drop is noticed", lambda: not on(), 10)
    B.quiet(15, "a hidden page must not connect again by itself")
    check("hidden, no new connection", n() == k and not on(), (k, len(sockets)))

    # back in front: connected at once
    k = n(); pg.evaluate(HIDE, False)
    R.expect("back in front, it connects at once", lambda: n() > k and on(), 10)
    check("no error on the page", not errs, errs)
    b.close()

j.close()
B.check_clean_log(R, "hidden tab")
R.finish()
