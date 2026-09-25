"""End-to-end tests of the new web UI against the bench (real Lua app + mosquitto)."""
import sys, time, json, os, subprocess
from playwright.sync_api import sync_playwright
from jk import Jooki
LUA = os.environ.get("PLAYER_LUA", "player.patched.lua")
URL = "http://127.0.0.1:8080"
R = []
def check(n, c, info=""):
    R.append((n, bool(c))); print(("PASS " if c else "FAIL ") + n + ("" if c else "  -> " + str(info)[:300]))
subprocess.run(["bash", "setup.sh"], capture_output=True)
subprocess.run(["python3", "seed_demo.py"], capture_output=True)
subprocess.run(["./deploy_ui.sh"], capture_output=True)
subprocess.run(["./start_player.sh", LUA], capture_output=True); time.sleep(1)
J = Jooki()
def pl_by_title(t):
    for k, v in J.pls.items():
        if v.get("title") == t: return k
with sync_playwright() as p:
    b = p.chromium.launch()
    ctx = b.new_context(viewport={"width": 390, "height": 844}, is_mobile=True, has_touch=True, locale="fr-FR", bypass_csp=True)
    pg = ctx.new_page(); errs = []
    pg.on("console", lambda m: errs.append(m.text) if m.type == "error" and "ERR_CONNECTION_REFUSED" not in m.text else None)
    pg.on("pageerror", lambda e: errs.append("PAGEERROR " + str(e)))
    toasts = []
    pg.goto(URL + "/"); pg.wait_for_selector(".pl[data-pl]")
    check("E0 home lists the 6 playlists", pg.locator(".pl[data-pl]").count() == 6, pg.locator(".pl[data-pl]").count())
    # E1 create
    pg.click("[data-k=newpl]"); pg.fill("[data-k=plname]", "  Histoires du soir "); pg.keyboard.press("Enter")
    pg.wait_for_url("**/#/p/*", timeout=5000)
    pid = pg.url.split("/#/p/")[1]
    J.wait(lambda: pid in J.pls)
    check("E1 playlist created and opened (trimmed name)", J.pls.get(pid, {}).get("title") == "Histoires du soir", J.pls.get(pid))
    # E2 upload from the file picker (phone path)
    pg.set_input_files("input[type=file]", ["media/song4.mp3", "media/song5.mp3", "media/notaudio.mp3", "media/garbage.mp3"])
    pg.wait_for_function("document.querySelectorAll('.up.done, .up.error').length >= 4", timeout=60000)
    done = pg.locator(".up.done").count(); err = pg.locator(".up.error").count()
    J.wait(lambda: len(J.pls[pid]["tracks"]) == 2)
    check("E2 upload: 2 added, 2 refused with a reason", done == 2 and err == 2 and len(J.pls[pid]["tracks"]) == 2, (done, err, J.pls[pid]))
    txt = pg.locator(".uploads").inner_text()
    check("E2 upload errors are explained in French", "trop petit" in txt and ("format audio" in txt), txt)
    # E3 rename
    pg.click("[data-k=renamebtn]"); pg.fill("[data-k=title]", "Histoires"); pg.keyboard.press("Enter")
    J.wait(lambda: J.pls[pid].get("title") == "Histoires")
    check("E3 rename with Enter", J.pls[pid].get("title") == "Histoires", J.pls[pid])
    # E4 character: take the Dragon (used by Pierre et le Loup) -> warning, then moved
    pierre = pl_by_title("Pierre et le Loup")
    pg.click("[data-k=tokbtn]"); pg.click("[data-char='Jooki.Dragon']")
    warn = pg.locator(".sheet .banner").inner_text()
    pg.click("[data-k=charsave]")
    J.wait(lambda: J.pls[pid].get("star") == "Jooki.Dragon")
    check("E4 moving a character warns and moves it", "Pierre et le Loup" in warn and J.pls[pid].get("star") == "Jooki.Dragon" and not J.pls[pierre].get("star"), (warn, J.pls[pid], J.pls[pierre]))
    pg.click("[data-k=tokbtn]"); pg.click("[data-char='none']"); pg.click("[data-k=charsave]")
    J.wait(lambda: not J.pls[pid].get("star"))
    check("E4 unlink character", not J.pls[pid].get("star"), J.pls[pid])
    J.send("PLAYLIST_UPDATE", {"playlist": {"id": pierre, "star": "Jooki.Dragon"}}); J.settle()
    # E5 add from library
    pg.click("text=Depuis la bibliothèque"); pg.fill("[data-k=libq]", "cygne")
    pg.locator(".sheet li").first.click()
    pg.fill("[data-k=libq]", "hémiones"); pg.locator(".sheet li").first.click()
    pg.click("[data-k=libadd]")
    J.wait(lambda: len(J.pls[pid]["tracks"]) == 4)
    names = [J.tracks[x]["title"] for x in J.pls[pid]["tracks"]]
    check("E5 add 2 tracks from the library (search)", len(names) == 4 and "Le Cygne" in names and "Hémiones" in names, names)
    # E7 remove + undo
    before = list(J.pls[pid]["tracks"])
    pg.locator("[data-remove='0']").click()
    J.wait(lambda: len(J.pls[pid]["tracks"]) == 3)
    pg.locator(".toast button").click()
    J.wait(lambda: J.pls[pid]["tracks"] == before)
    check("E7 remove then undo", J.pls[pid]["tracks"] == before, J.pls[pid]["tracks"])
    # E8 radio
    pg.click("text=Radio web"); pg.fill("[data-k=rname]", "FIP"); pg.fill("[data-k=rurl]", "fip.fr"); pg.keyboard.press("Enter")
    bad = pg.locator(".sheet .banner").inner_text()
    pg.fill("[data-k=rurl]", "https://icecast.radiofrance.fr/fip-hifi.aac"); pg.keyboard.press("Enter")
    J.wait(lambda: len(J.pls[pid]["tracks"]) == 5)
    check("E8 radio: bad URL explained, good URL added", "http" in bad and len(J.pls[pid]["tracks"]) == 5, bad)
    # E9 audiobook
    pg.click("[data-k=audiobook]"); J.wait(lambda: J.pls[pid].get("audiobook") is True)
    check("E9 audiobook toggle", J.pls[pid].get("audiobook") is True, J.pls[pid])
    # E13 play from a track row + player bar + sheet
    pg.locator("li[data-i='1']").click(); time.sleep(1.5)
    np = J.state["audio"]["nowPlaying"]
    check("E13 tap a track plays it", np.get("playlistId") == pid and np.get("trackIndex") == 2, np)
    bar = pg.locator(".player .t").inner_text()
    check("E13 player bar shows the track", bar.strip() == J.tracks[J.pls[pid]["tracks"][1]]["title"], bar)
    pg.click("[data-k=pp]"); J.wait(lambda: J.state["audio"]["playback"].get("state") == "PAUSED")
    check("E13 pause from the bar", J.state["audio"]["playback"].get("state") == "PAUSED", J.state["audio"]["playback"])
    pg.click(".player .info"); pg.wait_for_selector(".np")
    pg.click("[data-k=nppp]"); J.wait(lambda: J.state["audio"]["playback"].get("state") == "PLAYING")
    check("E13 play from the sheet", J.state["audio"]["playback"].get("state") == "PLAYING")
    pg.keyboard.press("Escape")
    # E6 reorder by drag (pointer events) on desktop-size page
    dctx = b.new_context(viewport={"width": 1200, "height": 900}, locale="fr-FR", bypass_csp=True); dp = dctx.new_page()
    dp.on("pageerror", lambda e: errs.append("PAGEERROR " + str(e)))
    dp.goto(URL + "/#/p/" + pid); dp.wait_for_selector("li[data-i='0']")
    order = list(J.pls[pid]["tracks"])
    h0 = dp.locator("li[data-i='0'] .handle").bounding_box(); h2 = dp.locator("li[data-i='2']").bounding_box()
    dp.mouse.move(h0["x"] + 10, h0["y"] + 10); dp.mouse.down()
    for k in range(1, 11): dp.mouse.move(h0["x"] + 10, h0["y"] + 10 + (h2["y"] - h0["y"]) * k / 10)
    dp.mouse.up()
    exp = order[1:3] + order[0:1] + order[3:]
    J.wait(lambda: J.pls[pid]["tracks"] == exp)
    check("E6 drag to reorder", J.pls[pid]["tracks"] == exp, (order, J.pls[pid]["tracks"]))
    # E10 delete playlist -> tracks become unused -> delete forever
    pg.goto(URL + "/#/p/" + pid); pg.wait_for_selector("text=Supprimer la playlist")
    pg.click("text=Supprimer la playlist"); pg.click("[data-k=ok]")
    J.wait(lambda: pid not in J.pls)
    pg.wait_for_url("**/#/")
    un = J.pls.get("TRASH", {}).get("tracks", [])
    check("E10 deleting a playlist keeps its songs (in Unused)", pid not in J.pls and len(un) == 3, un)  # 2 uploads + test tone; library tracks still used
    pg.goto(URL + "/#/library/unused"); pg.wait_for_selector("li[data-track]")
    victims = [x for x in un if J.tracks[x].get("userFilename") in ("song4.mp3", "song5.mp3")]
    for v in victims: pg.locator("li[data-track='%s']" % v).click()
    pg.click("text=Supprimer du Jooki"); pg.click("[data-k=ok]")
    J.wait(lambda: all(v not in J.tracks for v in victims))
    check("E10 delete forever from Unused (files erased)", all(v not in J.tracks and not os.path.exists("/jooki/external/jooki/uploads/" + v) for v in victims), victims)
    # E11 tokens
    pg.goto(URL + "/#/tokens"); pg.wait_for_selector("[data-char]")
    tag = "04000000D00002"  # unnamed dragon
    inp = pg.locator("[data-k='name-%s']" % tag)
    inp.fill("Dragon de Léo"); inp.press("Enter")
    J.wait(lambda: J.tokens[tag].get("name") == "Dragon de Léo")
    inp = pg.locator("[data-k='name-%s']" % tag); inp.fill("Dragon de Léo"); inp.press("Enter"); time.sleep(0.8)
    errtoast = pg.locator(".toast.error").count()
    check("E11 naming a token (twice) works, no error", J.tokens[tag].get("name") == "Dragon de Léo" and errtoast == 0, (J.tokens[tag], errtoast))
    check("E11 naming does not steal the playlist", J.pls[pierre].get("star") == "Jooki.Dragon" and not J.pls[pierre].get("tagId"), J.pls[pierre])
    tri = pl_by_title("Chansons de marins")
    pg.select_option("[data-char-select='Jooki.Black.Whale']", tri)
    J.wait(lambda: J.pls[tri].get("star") == "Jooki.Black.Whale")
    check("E11 link a character to a playlist from the tokens page", J.pls[tri].get("star") == "Jooki.Black.Whale", J.pls[tri])
    pg.locator("[data-tag='04000000B00002'] button").click(); pg.click("[data-k=ok]")
    J.wait(lambda: "04000000B00002" not in J.tokens)
    check("E11 forget a token keeps the character's playlist", "04000000B00002" not in J.tokens and J.pls[tri].get("star") == "Jooki.Black.Whale", J.pls[tri])
    # E12 settings
    pg.goto(URL + "/#/settings"); pg.wait_for_selector("[data-k=shuffle]")
    pg.click("[data-k=shuffle]"); J.wait(lambda: J.state["audio"]["config"].get("shuffle_mode") is True)
    check("E12 shuffle toggle", J.state["audio"]["config"].get("shuffle_mode") is True, J.state["audio"]["config"])
    pg.click("text=English"); pg.wait_for_selector("text=Settings")
    check("E12 language switch to English", pg.locator("h1").inner_text() == "Settings")
    pg.click("text=Français")
    # E16 update from the page (the Jooki checks GitHub itself; bench has no GitHub Pages access -> failure path)
    pg.goto(URL + "/#/settings"); pg.wait_for_selector("[data-k=updcheck], [data-k=updnow]", timeout=15000)
    ver = pg.locator(".kv b").nth(5).inner_text()
    check("E16 settings shows the installed OpenJooki version", "OpenJooki 1.0.0" in ver, ver)
    pg.wait_for_selector("[data-k=updnow]", timeout=60000)
    txt = pg.locator("main").inner_text()
    check("E16 a newer GitHub release is offered", "Nouvelle version" in txt, txt[-300:])
    pg.goto(URL + "/#/"); pg.wait_for_selector("[data-k=updbanner]", timeout=5000)
    check("E16 update banner on the home page", pg.locator("[data-k=updbanner]").count() == 1)
    pg.goto(URL + "/#/settings"); pg.wait_for_selector("[data-k=updnow]")
    pg.click("[data-k=updnow]"); pg.click("[data-k=ok]")
    pg.wait_for_selector("text=Mise à jour en cours", timeout=5000)
    pg.wait_for_selector("text=n'a pas pu se faire", timeout=90000)
    check("E16 update start: progress shown, failure reported clearly (no GitHub Pages here)", True)
    # E14 offline / reconnect
    subprocess.run(["pkill", "-f", "^mosquitto -c"]); time.sleep(2.5)
    off = pg.locator(".conn").inner_text()
    subprocess.Popen(["mosquitto","-c","mosquitto.conf"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True); time.sleep(1)
    subprocess.run(["./start_player.sh", LUA], capture_output=True)
    pg.wait_for_function("document.querySelector('.conn') && document.querySelector('.conn').classList.contains('on')", timeout=20000)
    check("E14 shows offline and reconnects by itself", "Hors ligne" in off and pg.locator(".conn").inner_text().strip() == "Connecté", off)
    check("E15 no JavaScript errors", not errs, errs)
    b.close()
bad = [n for n, ok in R if not ok]
print("\n%d/%d passed" % (len(R) - len(bad), len(R))); sys.exit(1 if bad else 0)
