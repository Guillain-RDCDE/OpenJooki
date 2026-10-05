"""Spotify on the bench: a fake spotify_ctrl talks to the real core, the real page is checked in a browser.

What the family saw on 29/09/2026 with Spotify started from the phone: the page said "Nothing playing",
and a token put on played on top of Spotify. Here, the daemon's messages are sent in the order that
broke it ("playing" before "now_playing"), then a token, then Spotify again, then the headphones.
"""
import json
from playwright.sync_api import sync_playwright
import bench as B
from jk import PAGE
URL = PAGE
FOX = "04000000F00001"
R = B.Results(lead=""); check = R.check
J = B.boot(seed=True, ui=True)

# what the core says to the Spotify daemon and to the local audio engine (and the engine's answers)
spy = B.Spy("/j/spotify/output/#", "/j/audio/out/#", "/j/audio/input/#", name="spy-spotify")
mark, since = spy.mark, spy.since
def daemon(kind, payload=""):
    J.c.publish("/j/spotify/input/" + kind, payload if isinstance(payload, str) else json.dumps(payload))
def np(): return J.np
def pb(): return J.pb

TRACK = {"source_uri": "spotify:playlist:37i9dQZF1DX4sWSpwq3LiO", "source": "Peaceful Piano", "track": "Nuvole Bianche",
         "artist": "Ludovico Einaudi", "album": "Una Mattina", "duration_ms": 357000, "hasNext": True, "hasPrev": True}
SCDN = "https://i.scdn.co/image/"

with sync_playwright() as p:
    b = p.chromium.launch()
    ctx = b.new_context(viewport={"width": 390, "height": 844}, is_mobile=True, has_touch=True, locale="fr-FR", bypass_csp=True)
    pg = ctx.new_page(); errs = []
    pg.on("pageerror", lambda e: errs.append("PAGEERROR " + str(e)))
    pg.goto(URL + "/"); pg.wait_for_selector(".pl[data-pl]")
    check("SP0 nothing plays at first", "Rien en lecture" in pg.locator("[data-k=player]").inner_text(), pg.locator("[data-k=player]").inner_text())

    # SP1 Spotify started from the phone, "playing" first, then the track
    daemon("playing"); B.quiet(0.2, "the daemon's 'playing' is handled on its own before the track arrives (the order that broke 2.0.5)"); daemon("now_playing", TRACK)
    J.poll(lambda: np().get("track") == "Nuvole Bianche" and pb() == "PLAYING")
    check("SP1 the core knows Spotify plays (playing before now_playing)", np().get("service") == "SPOTIFY" and pb() == "PLAYING", (np(), pb()))
    try: pg.wait_for_function("document.querySelector('[data-k=player] .t').textContent.indexOf('Nuvole Bianche') >= 0", timeout=5000)
    except Exception: pass
    bar = pg.locator("[data-k=player]").inner_text()
    check("SP1 the page shows the Spotify track, not 'Nothing playing'", "Nuvole Bianche" in bar and "Rien en lecture" not in bar, bar)
    check("SP1 ... with 'artist / album' under it", "Ludovico Einaudi / Una Mattina" in bar, bar)
    pp = pg.locator("[data-k=pp]")
    check("SP1 the page has a pause button", pp.count() == 1 and pp.get_attribute("aria-label") == "Pause", pp.count() and pp.get_attribute("aria-label"))

    # SP2 the page's pause and play reach the daemon
    n = mark(); pp.click()
    B.poll(lambda: since(n, "/j/spotify/output/pauz"))
    check("SP2 pause on the page -> Spotify pauses", since(n, "/j/spotify/output/pauz"), since(n, "/j/"))
    daemon("paused"); J.wait_state("audio.playback.state", "PAUSED")
    try: pg.wait_for_function("document.querySelector('[data-k=pp]').getAttribute('aria-label') !== 'Pause'", timeout=5000)
    except Exception: pass
    n = mark(); pg.locator("[data-k=pp]").click()
    B.poll(lambda: since(n, "/j/spotify/output/cont"))
    check("SP2 play on the page -> Spotify continues", since(n, "/j/spotify/output/cont"), since(n, "/j/"))
    daemon("playing"); J.wait_state("audio.playback.state", "PLAYING")
    daemon("position", "61000")
    R.expect("SP2 the position follows Spotify", lambda: J.get("audio.playback.position_ms") == 61000, 5, lambda: J.get("audio"))

    # SP3 the now-playing sheet opens on a Spotify track
    pg.locator("[data-k=player] .info").click()
    try: pg.wait_for_selector(".np", timeout=3000)
    except Exception: pass
    sheet = pg.locator(".np").inner_text() if pg.locator(".np").count() else ""
    check("SP3 the now-playing sheet shows title, artist and album", "Nuvole Bianche" in sheet and "Ludovico Einaudi / Una Mattina" in sheet, sheet)
    pg.keyboard.press("Escape"); pg.wait_for_selector(".np", state="detached", timeout=3000)

    # SP4 a token put on while Spotify plays: Spotify pauses, the token plays alone
    n = mark(); J.nfc(FOX, "101")
    J.poll(lambda: np().get("service") == "FILE" and pb() == "PLAYING")
    check("SP4 token on -> Spotify told to pause", since(n, "/j/spotify/output/pauz"), since(n, "/j/"))
    check("SP4 ... and the token's music plays", np().get("service") == "FILE" and pb() == "PLAYING" and since(n, "/j/audio/out/play"), (np(), pb()))
    daemon("paused"); J.barrier()
    check("SP4 Spotify's own 'paused' does not stop the token", np().get("service") == "FILE" and pb() == "PLAYING", (np(), pb()))
    try: pg.wait_for_function("document.querySelector('[data-k=player] .t').textContent.indexOf('Nuvole') < 0", timeout=5000)
    except Exception: pass
    bar = pg.locator("[data-k=player]").inner_text()
    check("SP4 the page shows the token's track", "Nuvole Bianche" not in bar and "Rien en lecture" not in bar and "Comptines 2" in bar, bar)

    # SP5 play again on the phone: Spotify takes the speaker back, the token's music stops
    n = mark(); daemon("playing")
    J.poll(lambda: np().get("service") == "SPOTIFY" and pb() == "PLAYING")
    check("SP5 Spotify again -> the local music stops", since(n, "/j/audio/out/stop"), since(n, "/j/"))
    check("SP5 ... and Spotify is what plays (track remembered)", np().get("service") == "SPOTIFY" and np().get("track") == "Nuvole Bianche" and pb() == "PLAYING", (np(), pb()))
    B.poll(lambda: since(n, "/j/audio/input/stopped")); J.barrier()     # the engine's 'stopped' came in, the core handled it
    check("SP5 the local engine's late 'stopped' does not undo it", np().get("service") == "SPOTIFY" and pb() == "PLAYING", (np(), pb()))
    n = mark(); J.nfc_off(); J.barrier()
    check("SP5 taking the token off does not pause the phone's Spotify", not since(n, "/j/spotify/output/pauz") and pb() == "PLAYING", since(n, "/j/"))

    # SP8 put what Spotify plays on a character (the Muuselabs app had it; 2.0.6 had no button)
    WHALE = "04000000E00005"          # a whale token (tag ids are hex; the core learns it)
    pg.locator("[data-k=player] .info").click()
    try: pg.wait_for_selector("[data-k=spsave]", timeout=4000)
    except Exception: pass
    check("SP8 the now-playing sheet offers 'Put on a character'", pg.locator("[data-k=spsave]").count() == 1, pg.locator(".np").inner_text() if pg.locator(".np").count() else "")
    pg.click("[data-k=spsave]")
    pg.wait_for_selector("[data-k=spname]")
    check("SP8 the name is what Spotify plays from", pg.input_value("[data-k=spname]") == "Peaceful Piano", pg.input_value("[data-k=spname]"))
    check("SP8 'Save' waits for a character", pg.locator("[data-k=spsaveok]").is_disabled())
    pg.click(".sheet [data-char='Jooki.Whale']")
    moved = pg.locator(".sheet .banner").inner_text() if pg.locator(".sheet .banner").count() else ""
    check("SP8 taking a character already used says so", "Le carnaval des animaux" in moved, moved)
    n = mark(); pg.click("[data-k=spsaveok]")
    B.poll(lambda: since(n, "/j/spotify/output/save_preset"))
    check("SP8 the Jooki asks Spotify for a preset", since(n, "/j/spotify/output/save_preset"), since(n, "/j/"))
    daemon("new_preset", "PRESET-BYTES")          # what spotify_ctrl answers (raw bytes)
    def sp_pl():
        for k, v in J.pls.items():
            if v.get("spotify"): return k, v
        return None, None
    J.poll(lambda: sp_pl()[0])
    pid, pl = sp_pl()
    check("SP8 a Spotify playlist is created on the whale", pl and pl.get("title") == "Peaceful Piano" and pl.get("star") == "Jooki.Whale"
          and pl["spotify"].get("uri") == TRACK["source_uri"] and pl["spotify"].get("preset") == "PRESET-BYTES".encode().hex().upper(), pl)
    old = [v for v in J.pls.values() if v.get("title") == "Le carnaval des animaux"]
    check("SP8 ... and the whale left its old playlist", old and not old[0].get("star"), old)
    try: pg.wait_for_selector("[data-k=sphelp]", timeout=5000)
    except Exception: pass
    check("SP8 the page opens the new playlist and explains it plays from Spotify", pg.locator("[data-k=sphelp]").count() == 1 and "#/p/" in pg.url, pg.url)
    toast_txt = pg.locator(".toast").all_inner_texts()
    check("SP8 ... with a message saying which character plays it", any("Baleine" in x or "Whale" in x for x in toast_txt), toast_txt)
    # put the whale on: the Jooki plays the preset
    daemon("paused"); J.wait_state("audio.playback.state", "PAUSED")
    n = mark(); J.nfc(WHALE, "105")
    B.poll(lambda: since(n, "/j/spotify/output/play_preset"))
    got = since(n, "/j/spotify/output/play_preset")
    check("SP8 the whale plays the Spotify preset", got and got[0][1] == "PRESET-BYTES", got)
    daemon("playing"); J.wait_state("audio.playback.state", "PLAYING")
    check("SP8 ... and the page shows it as the whale's playlist", np().get("playlistId") == pid and np().get("service") == "SPOTIFY", np())
    n = mark(); J.nfc_off()
    B.poll(lambda: since(n, "/j/spotify/output/pauz"))
    check("SP8 taking the whale off pauses Spotify (a token started it)", since(n, "/j/spotify/output/pauz"), since(n, "/j/"))
    daemon("paused"); J.wait_state("audio.playback.state", "PAUSED")
    # asking while Spotify does not play: a clear message, no playlist
    before = len([v for v in J.pls.values() if v.get("spotify")])
    ne = J.mark_errors(); J.send("PLAYLIST_NEW_SPOTIFY", {"title": "x"})
    J.poll(lambda: any("Not playing spotify" in str(e) for e in J.errors_since(ne)))
    check("SP8 saving while Spotify is paused is refused", len([v for v in J.pls.values() if v.get("spotify")]) == before and any("Not playing spotify" in str(e) for e in J.errors), J.errors[-2:])

    # SP6 the Jooki v2 has NO wired headphone jack, but its ESP32 can still report hp_state=1 with
    # nothing there. That must be IGNORED (config headphone_jack=false), or the sound would be routed
    # to a jack that does not exist and cut from the speaker. So a headphones report moves nothing.
    J.c.publish("/j/esp32/input/knobs/state", json.dumps({"volume": 40, "hp_state": 0, "control": 0})); J.barrier()
    n = mark(); J.c.publish("/j/esp32/input/knobs/state", json.dumps({"volume": 40, "hp_state": 1, "control": 0})); J.barrier()
    check("SP6 v2 has no jack: a headphones report is ignored, Spotify stays on the speaker",
          ("/j/spotify/output/set_output_device", "headphones") not in since(n, "/j/spotify/output/"), since(n, "/j/"))

    # SP9 each Wi-Fi report tells Spotify the Jooki is online (a "no network" at boot must not stick)
    n = mark(); J.c.publish("/j/esp32/input/net/sta/config", json.dumps({"ssid": "Home", "stat": "fail", "ip": ""}))
    B.poll(lambda: since(n, "/j/spotify/output/connection_state"))
    check("SP9 Wi-Fi lost -> Spotify told offline", ("/j/spotify/output/connection_state", "0") in since(n, "/j/spotify/output/"), since(n, "/j/"))
    n = mark(); J.c.publish("/j/esp32/input/net/sta/config", json.dumps({"ssid": "Home", "stat": "success", "ip": "192.168.1.50", "signal": -50, "ch": 6}))
    B.poll(lambda: since(n, "/j/spotify/output/connection_state"))
    check("SP9 Wi-Fi back -> Spotify told online", ("/j/spotify/output/connection_state", "2") in since(n, "/j/spotify/output/"), since(n, "/j/"))

    # SP10 the cover, in a browser that ENFORCES the page's security policy (the context above bypasses
    # it, which is how Spotify's covers stayed blocked unseen: 30/09 the family saw the grey disc).
    # Spotify's image server is faked by a route in both contexts (neither fetches the real one): the
    # request only happens if the policy allows it. The page rebuilds its DOM at each state message, so
    # the <img> is a new element each time: what counts is a load event for the cover's address, not
    # the element of the moment (which may still be loading); the fake answer is cacheable for that.
    COVER = "ab67616d0000b273e8b066f70c206551210d902b"; SRC = SCDN + COVER
    hits = []
    def fake_scdn(r):
        hits.append(r.request.url)
        r.fulfill(status=200, content_type="image/png", body=B.PNG_1x1, headers={"Cache-Control": "max-age=3600"})
    ctx.route(SCDN + "**", fake_scdn)
    ctx2 = b.new_context(viewport={"width": 390, "height": 844}, is_mobile=True, locale="fr-FR")
    ctx2.route(SCDN + "**", fake_scdn)
    ctx2.add_init_script("""window.__img = [];
      document.addEventListener('load', function (e) { if (e.target && e.target.tagName === 'IMG') window.__img.push(['load', e.target.getAttribute('src'), e.target.naturalWidth]); }, true);
      document.addEventListener('error', function (e) { if (e.target && e.target.tagName === 'IMG') window.__img.push(['error', e.target.getAttribute('src'), 0]); }, true);
      document.addEventListener('securitypolicyviolation', function (e) { window.__img.push(['csp', e.blockedURI, 0]); });""")
    pg2 = ctx2.new_page(); csp = []
    pg2.on("console", lambda m: csp.append(m.text) if "Content Security Policy" in m.text else None)
    pg2.goto(URL + "/"); pg2.wait_for_selector(".pl[data-pl]")
    daemon("playing"); B.quiet(0.2, "'playing' on its own first, as the daemon does"); daemon("now_playing", dict(TRACK, track="Primavera", image="spotify:image:" + COVER))
    J.wait_state("audio.nowPlaying.track", "Primavera")
    check("SP10 the core turns spotify:image:<id> into Spotify's image address", np().get("image") == SRC, np().get("image"))
    try: pg2.wait_for_function("s => window.__img.some(function (x) { return x[0] === 'load' && x[1] === s && x[2] > 0; })", arg=SRC, timeout=15000)
    except Exception: pass
    loads = pg2.evaluate("window.__img")
    cur = pg2.evaluate("(function(){var i=document.querySelector('[data-k=player] .cover img');return i?[i.getAttribute('src'),i.naturalWidth]:null;})()")
    check("SP10 the page shows Spotify's cover (security policy enforced), not the generic disc",
          any(x[0] == "load" and x[1] == SRC and x[2] > 0 for x in loads) and bool(cur) and cur[0] == SRC and hits, (cur, loads[-5:], hits, csp))
    viol = [x for x in loads if x[0] == "csp" or (x[0] == "error" and x[1] == SRC)]
    check("SP10 no security-policy refusal in the page", not csp and not viol, (csp, viol))
    ctx2.close()

    # SP11 shuffle and repeat set in the Spotify app do not become the Jooki's own (they shuffled the tokens' playlists)
    J.send("SET_CFG", {"shuffle_mode": False, "repeat_mode": 0}); J.wait(lambda: J.get("audio.config.shuffle_mode") is False)
    daemon("set_cfg", {"shuffle_mode": 1, "repeat_mode": 2}); J.barrier()
    check("SP11 the app's shuffle and repeat leave the Jooki's own setting alone", J.get("audio.config.shuffle_mode") is False
          and J.get("audio.config.repeat_mode") == 0, J.get("audio.config"))

    check("SP7 no page error", not errs, errs)
    b.close()
spy.close(); J.nfc_off(); J.close()
R.finish()
