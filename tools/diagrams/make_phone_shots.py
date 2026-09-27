#!/usr/bin/env python3
"""The README's picture of the page on a phone (docs/img/openjooki-web.png), made on the test bench.

    cd tools/openjooki/tests && ./up.sh && python3 seed_demo.py && ./start_player.sh core
    python3 ../../diagrams/make_phone_shots.py            (Playwright + Pillow, the fonts-roboto package)

Demo data only (seed_demo.py), never a family's. Three screens of an Android-sized phone at 3x,
in the phone's own font (Roboto; the bench's default one draws everything too bold), something
playing, then framed side by side on the page's warm background.
"""
import json, os, sys, time, tempfile
from playwright.sync_api import sync_playwright
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "docs", "img", "openjooki-web.png")
URL = "http://127.0.0.1:8080"
W, H, SCALE = 360, 720, 3
# Roboto first for every generic family, as on an Android phone
FONTS = """<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "fonts.dtd"><fontconfig>
<include ignore_missing="yes">/etc/fonts/fonts.conf</include>
<alias><family>system-ui</family><prefer><family>Roboto</family></prefer></alias>
<alias><family>sans-serif</family><prefer><family>Roboto</family></prefer></alias>
<alias><family>-apple-system</family><prefer><family>Roboto</family></prefer></alias>
</fontconfig>"""


def shots(tmp):
    conf = os.path.join(tmp, "fonts.conf")
    open(conf, "w").write(FONTS)
    os.environ["FONTCONFIG_FILE"] = conf
    files = []
    with sync_playwright() as p:
        b = p.chromium.launch()
        ctx = b.new_context(viewport={"width": W, "height": H}, device_scale_factor=SCALE, locale="fr-FR",
                            color_scheme="light", is_mobile=True, has_touch=True)
        pg = ctx.new_page()
        pg.goto(URL + "/#/"); pg.wait_for_selector(".pl:not(.newpl)", timeout=30000); time.sleep(1)
        # something playing: the second track of "Pierre et le Loup"
        pid = pg.evaluate("Object.keys(window.OJ.state.db.playlists).find(k => window.OJ.state.db.playlists[k].title === 'Pierre et le Loup')")
        pg.evaluate("id => window.OJ.send('PLAYLIST_PLAY', {playlistId: id, trackIndex: 3})", pid); time.sleep(3)
        for name, route in (("home", "#/"), ("playlist", "#/p/" + pid), ("tokens", "#/tokens")):
            pg.goto(URL + "/" + route); time.sleep(2)
            f = os.path.join(tmp, name + ".png"); pg.screenshot(path=f); files.append(f)
        b.close()
    return files


def frame(files):
    pad, gap, radius, border = 48, 40, 34 * SCALE // 2, 6
    phones = [Image.open(f).convert("RGB") for f in files]
    pw, ph = phones[0].size
    k = 1.0 / 2                                     # the final picture at 1.5x the phone's CSS size
    pw2, ph2 = int(pw * k), int(ph * k)
    cw = pad * 2 + len(phones) * (pw2 + 2 * border) + gap * (len(phones) - 1)
    ch = pad * 2 + ph2 + 2 * border
    bg = Image.new("RGB", (cw, ch), (246, 236, 224))
    shade = Image.new("L", (cw, ch), 0)
    sd = ImageDraw.Draw(shade)
    x = pad
    for _ in phones:
        sd.rounded_rectangle((x + 4, pad + 10, x + pw2 + 2 * border + 4, pad + ph2 + 2 * border + 10), radius + border, fill=90)
        x += pw2 + 2 * border + gap
    bg.paste((200, 170, 140), mask=shade.filter(ImageFilter.GaussianBlur(14)))
    x = pad
    for im in phones:
        im = im.resize((pw2, ph2), Image.LANCZOS)
        body = Image.new("RGB", (pw2 + 2 * border, ph2 + 2 * border), (255, 255, 255))
        m = Image.new("L", body.size, 0); ImageDraw.Draw(m).rounded_rectangle((0, 0, body.size[0] - 1, body.size[1] - 1), radius + border, fill=255)
        bg.paste(body, (x, pad), m)
        m2 = Image.new("L", im.size, 0); ImageDraw.Draw(m2).rounded_rectangle((0, 0, pw2 - 1, ph2 - 1), radius, fill=255)
        bg.paste(im, (x + border, pad + border), m2)
        x += pw2 + 2 * border + gap
    bg.save(OUT, optimize=True)
    print("wrote", os.path.normpath(OUT), bg.size, os.path.getsize(OUT), "bytes")


if __name__ == "__main__":
    with tempfile.TemporaryDirectory() as tmp:
        frame(shots(tmp))
