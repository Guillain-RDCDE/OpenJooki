#!/usr/bin/env python3
"""The page keeps still while a song plays (#29): a position report draws nothing.

The core sends the whole `audio` part with each position, and the page used to rebuild everything
each time, so the player and its cover flickered every second. A real change must still be drawn.
  python3 test_page_steady.py
"""
import json, time
import bench as B
from playwright.sync_api import sync_playwright

R = B.Results(); check = R.check
j = B.boot(ui=True)
pl = j.newpl("Songs", ["media/song1.mp3", "media/song2.mp3"], star=None)
j.send("PLAYLIST_PLAY", {"playlistId": pl, "trackIndex": 0})
j.wait_state("audio.playback.state", "PLAYING")

with sync_playwright() as p:
    b = p.chromium.launch(args=["--no-sandbox"])
    pg = b.new_page(viewport={"width": 420, "height": 800})
    errs = []
    pg.on("pageerror", lambda e: errs.append(str(e)))
    pg.goto(B.PAGE)
    pg.wait_for_selector(".player .info", timeout=15000)
    # each redraw puts a new player in the page; a timer of the core may cause one, a position must not
    pg.evaluate("""() => { window.__bar = document.querySelector('.player'); window.__redraws = 0;
      new MutationObserver(l => { for (const r of l) for (const n of r.addedNodes)
        if (n.nodeType === 1 && (n.matches('.player') || n.querySelector('.player'))) window.__redraws++; })
        .observe(document.body, { subtree: true, childList: true }); }""")
    # the page's own first round (update check, clock) is over: 3 s without a redraw, however long it takes
    seen, still_since, end = -1, time.time(), time.time() + 40
    while time.time() - still_since < 3 and time.time() < end:
        n = pg.evaluate("() => window.__redraws")
        if n != seen: seen, still_since = n, time.time()
        time.sleep(0.2)
    pg.evaluate("() => { window.__bar = document.querySelector('.player'); window.__redraws = 0; }")
    same = "() => window.__bar === document.querySelector('.player')"
    width = "() => document.querySelector('[data-prog]').style.width"

    pos = 1000
    for _ in range(8):
        pos += 1000
        j.c.publish("/j/audio/input/position", json.dumps({"id": 7, "pos": pos}))
        time.sleep(0.25)
    R.expect("the core took the positions", lambda: j.state["audio"]["playback"]["position_ms"] >= pos - 1000)
    redraws = pg.evaluate("() => window.__redraws")
    check("8 positions do not redraw the player", redraws <= 1, redraws)
    R.expect("the progress bar still moves", lambda: pg.evaluate(width) not in ("", "0%"), 3)

    # real changes are drawn: pause changes the button, a new song the title
    j.send("DO_PAUSE", {})
    j.wait_state("audio.playback.state", "PAUSED")
    R.expect("a pause is drawn", lambda: not pg.evaluate(same), 3)
    pg.evaluate("() => { window.__bar = document.querySelector('.player'); }")
    j.send("DO_PLAY", {})
    j.wait_state("audio.playback.state", "PLAYING")
    R.expect("playing again is drawn", lambda: not pg.evaluate(same), 3)
    title = pg.inner_text(".player .t")
    j.send("DO_NEXT", {})
    R.expect("the next song is drawn", lambda: pg.inner_text(".player .t") != title, 5)
    pg.evaluate("() => { window.__bar = document.querySelector('.player'); }")
    # a volume change reaches an open page too
    j.send("SET_VOL", {"vol": "33"})
    R.expect("a volume change is drawn", lambda: not pg.evaluate(same), 3)
    check("no error on the page", not errs, errs)
    b.close()
j.close()
R.finish()
