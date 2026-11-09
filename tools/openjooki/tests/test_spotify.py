"""Spotify on the bench: a fake spotify_ctrl talks to the real core, the real page is checked in a browser.

What the family saw on 29/09/2026 with Spotify started from the phone: the page said "Nothing playing",
and a token put on played on top of Spotify. Here, the daemon's messages are sent in the order that
broke it ("playing" before "now_playing"), then a token, then Spotify again, then the headphones.
"""
import json, os, struct
from playwright.sync_api import sync_playwright
import bench as B
from jk import PAGE
URL = PAGE
FOX = "04000000F00001"
R = B.Results(lead=""); check = R.check
# the daemon's saved account (spotify_ctrl's credentials.bin: the name, NUL, then its blob)
CRED = "/tmp/oj-spotify-credentials.bin"
open(CRED, "wb").write(b"alice\0" + b"\0" * 27 + b"\x01\x02not-a-real-blob")
J = B.boot(seed=True, ui=True, config=B.core_config({"spotify_credentials_file": CRED}, "spotify"))

# what the core says to the Spotify daemon and to the local audio engine (and the engine's answers)
spy = B.Spy("/j/spotify/output/#", "/j/audio/out/#", "/j/audio/input/#", name="spy-spotify")
mark, since = spy.mark, spy.since
def daemon(kind, payload=""):
    J.c.publish("/j/spotify/input/" + kind, payload if isinstance(payload, str) else json.dumps(payload))
def resume_file():
    try: return json.load(open(B.DB + "/resume.json"))
    except (OSError, ValueError): return {}
def vols(): return [int(x) for x in open(B.VOL_LOG).read().split()] if os.path.exists(B.VOL_LOG) else []
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
    check("SP3 Spotify offers an end-of-song timer", pg.locator("[data-sleep-min='track']").inner_text() == "Fin du morceau")
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
    # SP12 the whale's playlist set to pick up where it stopped: put back on, Spotify continues
    pg.goto(URL + "/#/p/" + pid); pg.wait_for_selector("[data-k=spresume]")
    check("SP12 the Spotify playlist's page has the switch, off", not pg.is_checked("[data-k=spresume]"))
    pg.locator("[data-k=spresume]").check()
    J.poll(lambda: J.pls[pid].get("resume") is True)
    check("SP12 the switch sets the playlist's resume", J.pls[pid].get("resume") is True, J.pls[pid])
    n = mark(); J.nfc(WHALE, "105")
    B.poll(lambda: since(n, "/j/spotify/output/cont"))
    check("SP12 the whale put back on continues Spotify", since(n, "/j/spotify/output/cont") and not since(n, "/j/spotify/output/play_preset"), since(n, "/j/"))
    daemon("playing"); J.wait_state("audio.playback.state", "PLAYING")
    daemon("position", "96824"); J.poll(lambda: J.get("audio.playback.position_ms") == 96824)
    # taking it off asks Spotify where it is before pausing; the answer goes to resume.json
    n = mark(); J.nfc_off()
    B.poll(lambda: since(n, "/j/spotify/output/pauz"))
    got = [t for t, _ in since(n, "/j/spotify/output/")]
    check("SP12 the whale taken off asks for a preset, then pauses", got[:2] == ["/j/spotify/output/save_preset", "/j/spotify/output/pauz"], got)
    daemon("new_preset", "WHERE-IT-WAS"); daemon("paused"); J.wait_state("audio.playback.state", "PAUSED")
    B.poll(lambda: resume_file().get(pid, {}).get("preset"))
    sp = resume_file().get(pid, {})
    # the time is the last report plus the moment since, while it played
    check("SP12 ... and resume.json keeps that preset and the time", sp.get("preset") == "WHERE-IT-WAS".encode().hex().upper()
          and 96824 <= sp.get("pos", 0) < 96824 + 3000, sp)
    # another character in between, then the whale: Spotify is asked to continue; with no answer, the
    # saved preset, and the seek once Spotify plays the whale's playlist
    J.nfc(FOX, "101"); J.wait_state("audio.playback.state", "PLAYING"); J.nfc_off(); J.wait_state("audio.playback.state", "PAUSED")
    n = mark(); J.nfc(WHALE, "105")
    B.poll(lambda: since(n, "/j/spotify/output/play_preset"), 10)   # after the 5 s wait for Spotify to continue
    got = since(n, "/j/spotify/output/play_preset")
    check("SP12 after another character the whale asks Spotify to continue first", since(n, "/j/spotify/output/cont"), since(n, "/j/"))
    check("SP12 ... then, with no answer, plays where it stopped", got and got[0][1] == "WHERE-IT-WAS", got)
    n = mark(); daemon("now_playing", TRACK); daemon("playing")
    B.poll(lambda: since(n, "/j/spotify/output/seek"))
    got = since(n, "/j/spotify/output/seek")
    check("SP12 ... and seeks to its time, 15 s back", got and got[0][1] == str(sp.get("pos", 0) - 15000), (got, sp))
    J.wait_state("audio.playback.state", "PLAYING")
    n = mark(); J.nfc_off()
    B.poll(lambda: since(n, "/j/spotify/output/pauz"))
    daemon("new_preset", "WHERE-IT-WAS"); daemon("paused"); J.wait_state("audio.playback.state", "PAUSED")
    # SP13 the same switch on the whale's sheet in Tokens, not on a character with files
    pg.goto(URL + "/#/tokens"); pg.click("[data-char='Jooki.Whale']"); pg.wait_for_selector(".sheet [data-k=spresume]")
    check("SP13 the whale's sheet has the switch, on", pg.is_checked(".sheet [data-k=spresume]"))
    pg.locator(".sheet [data-k=spresume]").uncheck()
    J.poll(lambda: "resume" not in J.pls[pid])
    check("SP13 switching it off on the sheet clears the playlist's resume", "resume" not in J.pls[pid], J.pls[pid])
    pg.locator(".sheet [data-k=spresume]").check()
    J.poll(lambda: J.pls[pid].get("resume") is True)
    check("SP13 ... and on again sets it", J.pls[pid].get("resume") is True, J.pls[pid])
    pg.click("[data-k=charclose]")
    fox = J.tokens[FOX]["starId"]
    pg.click("[data-char='%s']" % fox); pg.wait_for_selector(".sheet [data-char-select]")
    check("SP13 a character with files has no such switch", pg.locator(".sheet [data-k=spresume]").count() == 0)
    pg.click("[data-k=charclose]")
    # asking while Spotify does not play: a clear message, no playlist
    before = len([v for v in J.pls.values() if v.get("spotify")])
    ne = J.mark_errors(); J.send("PLAYLIST_NEW_SPOTIFY", {"title": "x"})
    J.poll(lambda: any("Not playing spotify" in str(e) for e in J.errors_since(ne)))
    check("SP8 saving while Spotify is paused is refused", len([v for v in J.pls.values() if v.get("spotify")]) == before and any("Not playing spotify" in str(e) for e in J.errors), J.errors[-2:])

    # SP6 wired headphones through the USB-C port (a passive adapter). The ESP32's reading is only
    # trusted once usb_mux pulls the detection line up, and a change needs two readings in a row:
    # one stray "plugged" (what made 2.1.3 switch the detection off) never mutes the speaker.
    def knobs(hp):
        J.c.publish("/j/esp32/input/knobs/state", json.dumps({"volume": 40, "hp_state": hp, "control": 0})); J.barrier()
    def hp_out(n): return [p for t, p in since(n, "/j/spotify/output/") if t == "/j/spotify/output/set_output_device"]
    for _ in range(3): knobs(0)                 # battery or charger: usb_mux up and settled, still the speaker
    n = mark(); knobs(1); knobs(0)
    check("SP6 one stray headphones reading moves nothing", not hp_out(n), since(n, "/j/"))
    n = mark(); knobs(1); knobs(1)
    B.poll(lambda: hp_out(n))
    check("SP6 headphones plugged (two readings): Spotify follows them", hp_out(n) == ["headphones"], since(n, "/j/"))
    J.wait_state("audio.config.headphones_en", True)
    pg.goto(URL + "/#/settings/sound"); pg.wait_for_selector("[data-k=hprow]")
    check("SP6 Settings shows the headphones detected", "Oui" in pg.locator("[data-k=hprow]").inner_text(), pg.locator("[data-k=hprow]").inner_text())
    n = mark(); knobs(0); knobs(0)
    B.poll(lambda: hp_out(n))
    check("SP6 headphones out: back to the speaker", hp_out(n) == ["speaker"], since(n, "/j/"))
    J.wait_state("audio.config.headphones_en", False)
    B.poll(lambda: "Non" in pg.locator("[data-k=hprow]").inner_text())
    check("SP6 ... and Settings says so", "Non" in pg.locator("[data-k=hprow]").inner_text(), pg.locator("[data-k=hprow]").inner_text())

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
    # another playlist than the whale's: the whale's, set to resume, played from the phone counts as the whale's
    daemon("playing"); B.quiet(0.2, "'playing' on its own first, as the daemon does"); daemon("now_playing", dict(TRACK, source_uri="spotify:playlist:0cover", track="Primavera", image="spotify:image:" + COVER))
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

    # SP12 the Jooki's own Spotify account (19/10/2026, a parent's report): Spotify keeps only the first account that
    # sets the Jooki up; another one is a guest until the next restart. The page says which, and can change it.
    check("SP12 the core reads the saved account at boot", J.get("spotify.saved") == "alice", J.get("spotify"))
    pg.goto(URL + "/#/settings"); pg.wait_for_selector("[data-k=sprow]")
    check("SP12 the settings row says Spotify is set up", "Configuré" in pg.locator("[data-k=sprow]").inner_text(), pg.locator("[data-k=sprow]").inner_text())
    pg.click("[data-k=sprow]"); pg.wait_for_selector("[data-k=spcard]")
    check("SP12 its page: set up, and the account", "Spotify est configuré" in pg.locator("[data-k=spcard]").inner_text()
          and "alice" in pg.locator("[data-k=spsaved]").inner_text(), pg.locator(".settings").inner_text())
    daemon("login", {"username": "bob", "firstLogin": True}); J.wait(lambda: J.get("spotify.username") == "bob")
    try: pg.wait_for_selector("[data-k=spnow]", timeout=5000)
    except Exception: pass
    txt = pg.locator(".settings").inner_text()
    check("SP12 a guest account playing: the page says so, the saved one stays (the daemon did not save bob)",
          "Un autre compte joue" in txt and "bob" in pg.locator("[data-k=spnow]").inner_text() and J.get("spotify.saved") == "alice", txt)
    pg.click("[data-k=spchange]"); pg.wait_for_selector("[data-k=ok]"); pg.click("[data-k=ok]")
    J.wait(lambda: J.get("spotify.saved") is False)
    B.poll(lambda: not B.os.path.exists(CRED))
    check("SP12 'Forget the account': the daemon's file is gone, the Jooki has no account any more",
          not B.os.path.exists(CRED) and J.get("spotify.saved") is False and not J.get("spotify.username"), (J.get("spotify"), B.os.path.exists(CRED)))
    try: pg.wait_for_function("document.querySelector('[data-k=spstate]').textContent.indexOf('Pas encore') >= 0", timeout=5000)
    except Exception: pass
    check("SP12 the page asks to pick the Jooki in the Spotify app", "Pas encore de compte Spotify" in pg.locator("[data-k=spcard]").inner_text()
          and pg.locator("[data-k=spchange]").count() == 0, pg.locator(".settings").inner_text())
    # the next account that picks the Jooki: the daemon saves it (it reached a Jooki with none), the core reads it back
    open(CRED, "wb").write(b"carol\0" + b"\0" * 27 + b"blob")
    daemon("login", {"username": "carol", "firstLogin": True}); J.wait(lambda: J.get("spotify.saved") == "carol")
    try: pg.wait_for_function("document.querySelector('[data-k=spstate]').textContent.indexOf('configuré') >= 0", timeout=5000)
    except Exception: pass
    check("SP12 the new account is the Jooki's own, and the page says so", J.get("spotify.saved") == "carol"
          and "Spotify est configuré" in pg.locator("[data-k=spcard]").inner_text(), (J.get("spotify"), pg.locator(".settings").inner_text()))

    check("SP7 no page error", not errs, errs)
    b.close()

# SP14 the whale playing when the Jooki goes off (no token off: the button, the battery, inactivity):
# while it plays its place is noted and saved, and after the restart the whale starts there
TRACK2 = dict(TRACK, track="Gymnopedie No. 1", duration_ms=600000)
J.nfc_off(); B.quiet(0.5, "the token off settles")
n = mark(); J.nfc(WHALE, "105")
B.poll(lambda: since(n, "/j/spotify/output/cont") or since(n, "/j/spotify/output/play_preset"))
daemon("playing"); daemon("now_playing", TRACK2); J.wait_state("audio.playback.state", "PLAYING")
daemon("position", "200000"); J.poll(lambda: J.get("audio.playback.position_ms") == 200000)
B.poll(lambda: since(n, "/j/spotify/output/save_preset"), 40)
check("SP14 while the whale plays a new track, the Jooki asks Spotify for its preset", since(n, "/j/spotify/output/save_preset"), since(n, "/j/spotify/output/"))
daemon("new_preset", "MID-TRACK")
B.poll(lambda: resume_file().get(pid, {}).get("preset") == "MID-TRACK".encode().hex().upper(), 75)
check("SP14 ... and saves it to resume.json within the save timer's minute", resume_file().get(pid, {}).get("preset") == "MID-TRACK".encode().hex().upper(), resume_file())
B.run("pkill", "-9", "-f", "harness.lua", check=False)       # power cut: no flush at exit
saved = resume_file().get(pid, {})
check("SP14 ... with the time in the track, counted on from Spotify's last report", saved.get("id") == "Gymnopedie No. 1" and saved.get("pos", 0) >= 200000, saved)
J = B.restart(J)
n = mark(); J.nfc(WHALE, "105")
B.poll(lambda: since(n, "/j/spotify/output/play_preset"), 10)   # after the 5 s wait for Spotify to continue
got = since(n, "/j/spotify/output/play_preset")
check("SP14 after the restart the whale plays the saved preset", got and got[0][1] == "MID-TRACK", got)
n = mark(); daemon("now_playing", TRACK2); daemon("playing")
B.poll(lambda: since(n, "/j/spotify/output/seek"))
got = since(n, "/j/spotify/output/seek")
check("SP14 ... and seeks to the saved time, 15 s back", got and got[0][1] == str(saved.get("pos", 0) - 15000), (got, saved))
J.wait_state("audio.playback.state", "PLAYING")
n = mark(); J.nfc_off()
B.poll(lambda: since(n, "/j/spotify/output/pauz"))
daemon("new_preset", "MID-TRACK"); daemon("paused"); J.wait_state("audio.playback.state", "PAUSED")
# SP15 the whale's playlist listened to on the phone since: Spotify continues it there, and the saved
# place is not played over it
J.nfc(FOX, "101"); J.wait_state("audio.playback.state", "PLAYING"); J.nfc_off(); J.wait_state("audio.playback.state", "PAUSED")
n = mark(); J.nfc(WHALE, "105")
B.poll(lambda: since(n, "/j/spotify/output/cont"))
daemon("now_playing", dict(TRACK, track="Part 24")); daemon("playing"); J.wait_state("audio.playback.state", "PLAYING")
B.quiet(6, "longer than the wait for Spotify's answer")
check("SP15 the whale continues the phone's place", J.get("audio.nowPlaying.track") == "Part 24" and not since(n, "/j/spotify/output/play_preset"),
      (J.get("audio.nowPlaying"), since(n, "/j/spotify/output/")))
# SP16 spotify_ctrl patched, and two chapters added at the top of the whale's playlist since its place
# was saved: the place starts at its saved index, where another chapter now is; that one is skipped,
# muted, until the saved chapter, which then plays from its time at the volume it had
J.nfc_off(); B.poll(lambda: since(n, "/j/spotify/output/pauz")); daemon("paused"); J.wait_state("audio.playback.state", "PAUSED"); J.close()
B.run("pkill", "-9", "-f", "harness.lua", check=False)
DIRECT = "/tmp/oj-spotify-direct"; open(DIRECT, "w").close()
ctx_uri = TRACK["source_uri"].encode()
def field(n, b): return bytes([n * 8 + 2, len(b)]) + b
preset = (bytes.fromhex("088180FCFFFFFFFFFFFF01") + field(2, ctx_uri) + bytes.fromhex("1A0408001029") + bytes.fromhex("2206080010001800")
          + field(5, b"spotify:track:0ExampleTrack000000041"))
places = resume_file(); places[pid] = {"id": "Chapter 14", "album": "Episode 103", "pos": 96824, "preset": preset.hex().upper()}
places["_"] = {"version": 1}   # written by hand: no sum, as 1.x wrote it
json.dump(places, open(B.DB + "/resume.json", "w"))
J = B.restart(config=B.core_config({"spotify_credentials_file": CRED, "spotify_direct_file": DIRECT}, "spotify-direct"))
n = mark(); J.nfc(WHALE, "105")
B.poll(lambda: since(n, "/j/spotify/output/play_preset"), 10)   # after the 5 s wait for Spotify to continue
got = since(n, "/j/spotify/output/play_preset")
req = ctx_uri + b"\0" * (64 - len(ctx_uri)) + struct.pack("<5I", 41, 0, 96824 - 15000, 0, 0)
check("SP16 patched: the saved place goes as one request for its index and time", got and got[0][1] == req.decode(errors="replace"), got)   # the spy reads payloads as text
CH = dict(TRACK, album="Episode 103")
n = mark(); daemon("playing"); daemon("now_playing", dict(CH, track="Chapter 12"))
B.poll(lambda: since(n, "/j/spotify/output/next"))
check("SP16 another chapter at that index is skipped", since(n, "/j/spotify/output/next"), since(n, "/j/spotify/output/"))
check("SP16 ... muted", vols()[-1:] == [0], vols()[-3:])
n = mark(); daemon("now_playing", dict(CH, track="Chapter 13"))
B.poll(lambda: since(n, "/j/spotify/output/next"))
check("SP16 ... and the next one", since(n, "/j/spotify/output/next"), since(n, "/j/spotify/output/"))
n = mark(); daemon("now_playing", dict(CH, track="Chapter 14"))
B.poll(lambda: since(n, "/j/spotify/output/seek"))
got = since(n, "/j/spotify/output/seek")
check("SP16 the saved chapter plays from its time, 15 s back", got and got[0][1] == "81824" and not since(n, "/j/spotify/output/next"), since(n, "/j/spotify/output/"))
B.poll(lambda: vols()[-1:] != [0])
check("SP16 ... at the volume it had", vols()[-1:] not in ([], [0]), vols()[-3:])
os.remove(DIRECT)
spy.close(); J.nfc_off(); J.close()
R.finish()
