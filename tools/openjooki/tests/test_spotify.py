"""Spotify on the bench: a fake spotify_ctrl talks to the real core, the real page is checked in a browser.

What the family saw on 29/09/2026 with Spotify started from the phone: the page said "Nothing playing",
and a token put on played on top of Spotify. Here, the daemon's messages are sent in the order that
broke it ("playing" before "now_playing"), then a token, then Spotify again, then the headphones.
"""
import sys, time, json, os, subprocess, threading
import paho.mqtt.client as mqtt
from playwright.sync_api import sync_playwright
from jk import Jooki
LUA = os.environ.get("PLAYER_LUA", "player.patched.lua")
URL = "http://127.0.0.1:8080"
FOX = "04000000F00001"
R = []
def check(n, c, info=""):
    R.append((n, bool(c))); print(("PASS " if c else "FAIL ") + n + ("" if c else "  -> " + str(info)[:300]), flush=True)
subprocess.run(["bash", "setup.sh"], capture_output=True)
subprocess.run(["python3", "seed_demo.py"], capture_output=True)
subprocess.run(["./deploy_ui.sh"], capture_output=True)
subprocess.run(["./start_player.sh", LUA], capture_output=True); time.sleep(1)
J = Jooki()

# what the core says to the Spotify daemon and to the local audio engine
seen, lock = [], threading.Lock()
spy = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, "spy-spotify")
def on_msg(c, u, m):
    with lock: seen.append((m.topic, m.payload.decode(errors="replace")))
spy.on_message = on_msg
spy.connect("127.0.0.1", 1883); spy.subscribe("/j/spotify/output/#"); spy.subscribe("/j/audio/out/#"); spy.loop_start(); time.sleep(0.3)
def mark():
    with lock: return len(seen)
def since(n, prefix):
    with lock: return [(t, p) for t, p in seen[n:] if t.startswith(prefix)]
def daemon(kind, payload=""):
    J.c.publish("/j/spotify/input/" + kind, payload if isinstance(payload, str) else json.dumps(payload))
def np(): return (J.state.get("audio") or {}).get("nowPlaying") or {}
def pb(): return ((J.state.get("audio") or {}).get("playback") or {}).get("state")

TRACK = {"source_uri": "spotify:playlist:37i9dQZF1DX4sWSpwq3LiO", "source": "Peaceful Piano", "track": "Nuvole Bianche",
         "artist": "Ludovico Einaudi", "album": "Una Mattina", "duration_ms": 357000, "hasNext": True, "hasPrev": True}

with sync_playwright() as p:
    b = p.chromium.launch()
    ctx = b.new_context(viewport={"width": 390, "height": 844}, is_mobile=True, has_touch=True, locale="fr-FR", bypass_csp=True)
    pg = ctx.new_page(); errs = []
    pg.on("pageerror", lambda e: errs.append("PAGEERROR " + str(e)))
    pg.goto(URL + "/"); pg.wait_for_selector(".pl[data-pl]")
    check("SP0 nothing plays at first", "Rien en lecture" in pg.locator("[data-k=player]").inner_text(), pg.locator("[data-k=player]").inner_text())

    # SP1 Spotify started from the phone, "playing" first, then the track
    daemon("playing"); time.sleep(0.2); daemon("now_playing", TRACK)
    J.wait(lambda: np().get("track") == "Nuvole Bianche" and pb() == "PLAYING")
    check("SP1 the core knows Spotify plays (playing before now_playing)", np().get("service") == "SPOTIFY" and pb() == "PLAYING", (np(), pb()))
    try: pg.wait_for_function("document.querySelector('[data-k=player] .t').textContent.indexOf('Nuvole Bianche') >= 0", timeout=5000)
    except Exception: pass
    bar = pg.locator("[data-k=player]").inner_text()
    check("SP1 the page shows the Spotify track, not 'Nothing playing'", "Nuvole Bianche" in bar and "Rien en lecture" not in bar, bar)
    check("SP1 ... with where it plays from", "Peaceful Piano" in bar, bar)
    pp = pg.locator("[data-k=pp]")
    check("SP1 the page has a pause button", pp.count() == 1 and pp.get_attribute("aria-label") == "Pause", pp.count() and pp.get_attribute("aria-label"))

    # SP2 the page's pause and play reach the daemon
    n = mark(); pp.click()
    J.wait(lambda: since(n, "/j/spotify/output/pauz"))
    check("SP2 pause on the page -> Spotify pauses", since(n, "/j/spotify/output/pauz"), since(n, "/j/"))
    daemon("paused"); J.wait(lambda: pb() == "PAUSED")
    try: pg.wait_for_function("document.querySelector('[data-k=pp]').getAttribute('aria-label') !== 'Pause'", timeout=5000)
    except Exception: pass
    n = mark(); pg.locator("[data-k=pp]").click()
    J.wait(lambda: since(n, "/j/spotify/output/cont"))
    check("SP2 play on the page -> Spotify continues", since(n, "/j/spotify/output/cont"), since(n, "/j/"))
    daemon("playing"); J.wait(lambda: pb() == "PLAYING")
    daemon("position", "61000"); J.wait(lambda: ((J.state.get("audio") or {}).get("playback") or {}).get("position_ms") == 61000)
    check("SP2 the position follows Spotify", ((J.state.get("audio") or {}).get("playback") or {}).get("position_ms") == 61000, J.state.get("audio"))

    # SP3 the now-playing sheet opens on a Spotify track
    pg.locator("[data-k=player] .info").click()
    try: pg.wait_for_selector(".np", timeout=3000)
    except Exception: pass
    sheet = pg.locator(".np").inner_text() if pg.locator(".np").count() else ""
    check("SP3 the now-playing sheet shows title and artist", "Nuvole Bianche" in sheet and "Ludovico Einaudi" in sheet, sheet)
    pg.keyboard.press("Escape"); time.sleep(0.3)

    # SP4 a token put on while Spotify plays: Spotify pauses, the token plays alone
    n = mark(); J.nfc(FOX, "101")
    J.wait(lambda: np().get("service") == "FILE" and pb() == "PLAYING")
    check("SP4 token on -> Spotify told to pause", since(n, "/j/spotify/output/pauz"), since(n, "/j/"))
    check("SP4 ... and the token's music plays", np().get("service") == "FILE" and pb() == "PLAYING" and since(n, "/j/audio/out/play"), (np(), pb()))
    daemon("paused"); time.sleep(0.4)
    check("SP4 Spotify's own 'paused' does not stop the token", np().get("service") == "FILE" and pb() == "PLAYING", (np(), pb()))
    try: pg.wait_for_function("document.querySelector('[data-k=player] .t').textContent.indexOf('Nuvole') < 0", timeout=5000)
    except Exception: pass
    bar = pg.locator("[data-k=player]").inner_text()
    check("SP4 the page shows the token's track", "Nuvole Bianche" not in bar and "Rien en lecture" not in bar and "Comptines 2" in bar, bar)

    # SP5 play again on the phone: Spotify takes the speaker back, the token's music stops
    n = mark(); daemon("playing")
    J.wait(lambda: np().get("service") == "SPOTIFY" and pb() == "PLAYING")
    check("SP5 Spotify again -> the local music stops", since(n, "/j/audio/out/stop"), since(n, "/j/"))
    check("SP5 ... and Spotify is what plays (track remembered)", np().get("service") == "SPOTIFY" and np().get("track") == "Nuvole Bianche" and pb() == "PLAYING", (np(), pb()))
    time.sleep(0.6)
    check("SP5 the local engine's late 'stopped' does not undo it", np().get("service") == "SPOTIFY" and pb() == "PLAYING", (np(), pb()))
    n = mark(); J.nfc_off(); time.sleep(0.6)
    check("SP5 taking the token off does not pause the phone's Spotify", not since(n, "/j/spotify/output/pauz") and pb() == "PLAYING", since(n, "/j/"))

    # SP6 the headphones: Spotify's sound follows them (1.x did it, 2.0 had lost it)
    J.c.publish("/j/esp32/input/knobs/state", json.dumps({"volume": 40, "hp_state": 0, "control": 0})); time.sleep(0.3)
    n = mark(); J.c.publish("/j/esp32/input/knobs/state", json.dumps({"volume": 40, "hp_state": 1, "control": 0}))
    J.wait(lambda: since(n, "/j/spotify/output/set_output_device"))
    check("SP6 headphones in -> Spotify goes to the headphones", ("/j/spotify/output/set_output_device", "headphones") in since(n, "/j/spotify/output/"), since(n, "/j/"))
    n = mark(); J.c.publish("/j/esp32/input/knobs/state", json.dumps({"volume": 40, "hp_state": 0, "control": 0}))
    J.wait(lambda: since(n, "/j/spotify/output/set_output_device"))
    check("SP6 headphones out -> back to the speaker", ("/j/spotify/output/set_output_device", "speaker") in since(n, "/j/spotify/output/"), since(n, "/j/"))

    check("SP7 no page error", not errs, errs)
    b.close()
spy.loop_stop(); J.nfc_off(); J.close()
bad = [n for n, ok in R if not ok]
print("%d/%d passed" % (len(R) - len(bad), len(R)))
sys.exit(1 if bad else 0)
