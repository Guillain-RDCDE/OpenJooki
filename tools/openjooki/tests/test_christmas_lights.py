"""#54 on the real core and the real page: the Christmas tree as long as the parents chose, started and
stopped from the page or the heart; the everyday lights in the parents' colours; a playlist's own lights
while it plays; all of it kept across a restart."""
import json
from playwright.sync_api import sync_playwright
import bench as B
from jk import PAGE

R = B.Results()
SET = "/j/led/output/set_raw"
spy = B.Spy(SET, "/j/led/output/pulse_raw", "/j/all/quit")


def pre():
    json.dump({"_": {"version": 1}, "enabled": False}, open(B.DB + "/bedtime.json", "w"))


def rings(mark):
    return [p for p in spy.payloads(SET, mark) if p.startswith("RING,")]


def gpio(btn, hold):
    j.c.publish("/j/gpio/input/" + btn, "1"); B.quiet(hold, "the button is held this long, as a hand would"); j.c.publish("/j/gpio/input/" + btn, "0")


j = B.boot(seed=True, ui=True, pre=pre)
j.c.publish("/j/esp32/input/net/sta/config", json.dumps({"stat": "success", "ip": "10.0.0.2"}))
cfg = j.get("audio.config")
R.check("the tree lasts 5 s by default, no colour chosen", cfg.get("party_s") == 5 and not cfg.get("colours"), cfg)

# --- the tree, as long as asked, and stopped by a second tap
j.send("OJ_PARTY", {})
R.expect("a tap starts the tree", lambda: j.get("device.party") is True)
R.expect("then it stops by itself after 5 s", lambda: not j.get("device.party"), 8)
j.send("SET_CFG", {"party_s": 0}); j.wait_state("audio.config.party_s", 0)
mark = spy.mark()
j.send("OJ_PARTY", {})
R.expect("until stopped: it starts", lambda: j.get("device.party") is True)
B.quiet(6.5, "longer than the 5 s of old")
R.check("until stopped: still running after 6 s", j.get("device.party") is True)
R.check("and still turning through the colours", len(set(rings(mark))) >= 6, len(set(rings(mark))))
stop = spy.mark()
j.send("OJ_PARTY", {})
R.expect("a second tap stops it", lambda: not j.get("device.party"))
R.expect("the ring is back to white", lambda: rings(stop) and rings(stop)[-1] == "RING,200,200,200", info=lambda: rings(stop)[-3:])
B.quiet(1, "no frame may follow")
R.check("no frame after the stop", rings(stop)[-1] == "RING,200,200,200", rings(stop)[-3:])

# --- the heart
j.send("SET_CFG", {"heart_press": "party", "party_s": 30}); j.wait_state("audio.config.heart_press", "party")
gpio("circle", 0.2)
R.expect("a press on the heart starts the tree", lambda: j.get("device.party") is True)
gpio("circle", 0.2)
R.expect("another one stops it", lambda: not j.get("device.party"))
gpio("circle", 2.6)
B.quiet(1, "a 2.6 s press is not a power-off when the heart has a job")
R.check("the Jooki is still on", not spy.payloads("/j/all/quit"))
R.expect("and the press started the tree", lambda: j.get("device.party") is True)
j.send("OJ_PARTY", {}); R.expect("stopped again from the page", lambda: not j.get("device.party"))

# --- the parents' colours
mark = spy.mark()
j.send("SET_CFG", {"colours": {"ring": "#ff0000", "dots": "#00ff00"}})
R.expect("the ring turns red at once", lambda: "RING,200,0,0" in rings(mark))
R.expect("the side dots green", lambda: "PREV,0,200,0" in spy.payloads(SET, mark) and "NEXT,0,200,0" in spy.payloads(SET, mark))
reply = j.v2("device.set_config", {"colours": {"heart": "#ffffff"}})
R.check("an unknown light is refused", reply.get("ok") is False, reply)
reply = j.v2("device.set_config", {"colours": {"off": "purple"}})
R.check("a colour that is not #rrggbb is refused", reply.get("ok") is False, reply)
R.check("v2 takes a good one", j.v2("device.set_config", {"colours": {"off": "#8000ff"}}).get("ok"))
j.wait(lambda: (j.get("audio.config.colours") or {}).get("off") == "#8000ff")

# --- a playlist's own lights
pid = "user_1"
j.send("PLAYLIST_UPDATE", {"playlist": {"id": pid, "lights": {"fx": "colour", "colour": "#0000ff"}}})
j.wait(lambda: (j.pls[pid].get("lights") or {}).get("fx") == "colour")
mark = spy.mark()
j.send("PLAYLIST_PLAY", {"playlistId": pid}); j.wait_state("audio.playback.state", "PLAYING")
R.expect("playing: the ring is the playlist's blue", lambda: rings(mark) and rings(mark)[-1] == "RING,0,0,200", info=lambda: rings(mark)[-3:])
mark = spy.mark()
j.send("PLAYLIST_UPDATE", {"playlist": {"id": pid, "lights": {"fx": "breathe", "colour": "#ffffff"}}})
R.expect("breathing, changed while it plays: the ring glows up and down", lambda: len(set(rings(mark))) >= 6, 6, info=lambda: rings(mark)[-6:])
R.check("all its frames are white, from dim to full", all(p.split(",")[1] == p.split(",")[2] == p.split(",")[3] for p in rings(mark)), rings(mark)[:8])
mark = spy.mark()
j.v2("playlist.update", {"id": pid, "lights": {"fx": "tree"}})
R.expect("the tree for the whole playlist: ring and side dots", lambda: len(set(rings(mark))) >= 6 and len(set(p for p in spy.payloads(SET, mark) if p.startswith("PREV,"))) >= 4, 6)
mark = spy.mark()
j.send("DO_PAUSE", {}); j.wait_state("audio.playback.state", "PAUSED")
R.expect("paused: the usual ring comes back (the parents' red)", lambda: rings(mark) and rings(mark)[-1] == "RING,200,0,0", info=lambda: rings(mark)[-3:])
B.quiet(1, "the frames must have stopped")
after = spy.mark(); B.quiet(1, "watching for frames")
R.check("no more frames while paused", not rings(after), rings(after))
j.send("DO_PLAY", {}); j.wait_state("audio.playback.state", "PLAYING")
j.send("DO_PAUSE", {}); j.wait_state("audio.playback.state", "PAUSED")

# --- kept across a restart
j = B.restart(j)
j.c.publish("/j/esp32/input/net/sta/config", json.dumps({"stat": "success", "ip": "10.0.0.2"}))
c2 = j.get("audio.config")
R.check("after a restart: the length, the heart and the colours are kept",
        c2.get("party_s") == 30 and c2.get("heart_press") == "party" and c2.get("colours") == {"ring": "#ff0000", "dots": "#00ff00", "off": "#8000ff"}, c2)
R.check("and the playlist's lights", j.pls[pid].get("lights") == {"fx": "tree"}, j.pls[pid].get("lights"))

# --- the page
with sync_playwright() as pw:
    browser = pw.chromium.launch(args=["--no-sandbox"])
    ctx = browser.new_context(locale="en-GB", timezone_id="UTC", viewport={"width": 375, "height": 812})
    pg = ctx.new_page(); errors = []
    pg.on("pageerror", lambda e: errors.append(str(e)))
    pg.goto(PAGE + "/#/settings"); pg.wait_for_selector("[data-k=party]")
    R.check("Settings: the tree has its own Lights section", pg.locator("[data-k=lightsnav]").count() == 1)
    R.check("the tree's line says how long", "30 s" in pg.inner_text("[data-k=party]"), pg.inner_text("[data-k=party]"))
    pg.click("[data-k=party]")
    R.expect("a tap on the page starts it", lambda: j.get("device.party") is True)
    R.expect("and the line becomes Stop", lambda: "Stop the Christmas tree" in pg.inner_text("[data-k=party]"))
    pg.click("[data-k=party]")
    R.expect("a second tap stops it", lambda: not j.get("device.party"))
    R.expect("and the line comes back", lambda: "Stop" not in pg.inner_text("[data-k=party]"))
    pg.click("[data-k=lightsnav]"); pg.wait_for_selector("[data-k=partylen]")
    R.check("the length is shown", pg.input_value("[data-k=partylen]") == "30")
    pg.select_option("[data-k=partylen]", "0")
    R.expect("Until stopped is saved", lambda: j.get("audio.config.party_s") == 0)
    R.check("the heart line says it is on", "On" in pg.inner_text("[data-k=partyheart]"), pg.inner_text("[data-k=partyheart]"))
    R.check("five colours to choose", pg.locator("input.cpick").count() == 5)
    R.check("the red ring shows red", pg.input_value("[data-k=col-ring]") == "#ff0000")
    R.check("the switch-on blink shows the Jooki's own white", pg.input_value("[data-k=col-start]") == "#ffffff")
    mark = spy.mark()
    pg.fill("[data-k=col-ring]", "#ffaa00")
    R.expect("a colour picked on the page reaches the ring", lambda: "RING,200,133,0" in rings(mark), info=lambda: rings(mark)[-3:])
    pg.click("[data-k=colreset-ring]")
    R.expect("Usual gives the ring back its white", lambda: "ring" not in (j.get("audio.config.colours") or {}) and rings(mark)[-1] == "RING,200,200,200")
    R.expect("and the page says so", lambda: pg.locator("[data-k=colreset-ring]").count() == 0)
    pg.goto(PAGE + "/#/settings/buttons"); pg.wait_for_selector("[data-k=heartpress]")
    R.check("Jooki buttons: the heart can be the tree", pg.input_value("[data-k=heartpress]") == "party")
    pg.select_option("[data-k=heartpress]", "none"); R.expect("the heart's choice changes", lambda: j.get("audio.config.heart_press") == "none")
    pg.select_option("[data-k=heartpress]", "party"); R.expect("and back", lambda: j.get("audio.config.heart_press") == "party")
    pg.goto(PAGE + "/#/p/" + pid); pg.wait_for_selector("[data-k=plfx]")
    R.check("the playlist shows its tree", pg.input_value("[data-k=plfx]") == "tree" and pg.locator("[data-k=plcolour]").count() == 0)
    pg.select_option("[data-k=plfx]", "colour")
    R.expect("One colour is saved, with a colour", lambda: (j.pls[pid].get("lights") or {}).get("fx") == "colour" and (j.pls[pid].get("lights") or {}).get("colour"))
    pg.wait_for_selector("[data-k=plcolour]")
    pg.fill("[data-k=plcolour]", "#00ff00")
    R.expect("its colour is picked on the page", lambda: j.pls[pid].get("lights") == {"fx": "colour", "colour": "#00ff00"}, info=lambda: j.pls[pid].get("lights"))
    mark = spy.mark()
    j.send("PLAYLIST_PLAY", {"playlistId": pid}); j.wait_state("audio.playback.state", "PLAYING")
    R.expect("and it plays in green", lambda: rings(mark) and rings(mark)[-1] == "RING,0,200,0", info=lambda: rings(mark)[-3:])
    j.send("DO_PAUSE", {}); j.wait_state("audio.playback.state", "PAUSED")
    pg.select_option("[data-k=plfx]", "none")
    R.expect("Usual takes the playlist's lights away", lambda: "lights" not in j.pls[pid])
    for language, word in (("en", "Christmas tree"), ("fr", "Sapin de Noël"), ("nl", "Kerstboom"), ("de", "Weihnachtsbaum")):
        pg.evaluate("v => localStorage.setItem('oj.lang', v)", language)
        pg.goto(PAGE + "/#/settings/lights"); pg.reload(); pg.wait_for_selector("[data-k=partylen]")
        R.check(language + ": the lights page is translated", word in pg.inner_text("body"))
        R.check(language + ": it fits a narrow phone", pg.evaluate("() => document.documentElement.scrollWidth <= innerWidth"))
        pg.goto(PAGE + "/#/p/" + pid); pg.wait_for_selector("[data-k=plfx]")
        R.check(language + ": the playlist's lights fit a narrow phone", pg.evaluate("() => document.documentElement.scrollWidth <= innerWidth"))
    pg.set_viewport_size({"width": 1280, "height": 900})
    pg.goto(PAGE + "/#/settings/lights"); pg.wait_for_selector("[data-k=partylen]")
    R.check("wide screen fits", pg.evaluate("() => document.documentElement.scrollWidth <= innerWidth"))
    R.check("no browser errors", not errors, errors)
    browser.close()
B.check_clean_log(R, "christmas lights")
j.close(); R.finish()
