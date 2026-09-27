"""Draws the home-screen icons of the OpenJooki page (no external art: our own drawing).

    python tools/openjooki/webui/make_icons.py

The Jooki seen from above (body, big button, power mark, prev/next arrows) in white on the
page's orange, full bleed: iOS rounds the corners itself, Android crops its own shape
(the drawing stays inside the 80 % safe zone of a "maskable" icon). Drawn at 4x, then reduced.
"""
import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ORANGE, WHITE = (232, 116, 28, 255), (255, 255, 255, 255)
S = 2048                      # drawing size (4x the largest icon)


def draw():
    im = Image.new("RGBA", (S, S), ORANGE)
    d = ImageDraw.Draw(im)
    c = S // 2
    half, w = int(S * 0.27), int(S * 0.034)            # body: 54 % of the side, inside the safe zone
    d.rounded_rectangle((c - half, c - half, c + half, c + half), radius=int(half * 0.46), outline=WHITE, width=w)
    r = int(S * 0.13)                                    # the big button
    d.ellipse((c - r, c - r + int(S * 0.02), c + r, c + r + int(S * 0.02)), outline=WHITE, width=int(S * 0.028))
    pr, py = int(S * 0.034), c - int(S * 0.175)          # power mark: an open ring and its bar
    d.arc((c - pr, py - pr, c + pr, py + pr), start=-50, end=230, fill=WHITE, width=int(S * 0.012))
    d.line((c, py - pr - int(S * 0.006), c, py - int(S * 0.004)), fill=WHITE, width=int(S * 0.012))
    a, ay = int(S * 0.022), c + int(S * 0.02)            # prev / next: two small double arrows, between
    for side in (-1, 1):                                 # the button and the body
        x0 = c + side * int(S * 0.157)
        for k in (0, 1):
            x = x0 + side * k * int(a * 0.95)
            tip = x + side * a
            d.polygon([(x, ay - a), (x, ay + a), (tip, ay)], fill=WHITE)
    return im


def main():
    big = draw()
    for name, size in (("icon-512.png", 512), ("icon-192.png", 192), ("apple-touch-icon.png", 180)):
        out = big.resize((size, size), Image.LANCZOS).convert("RGB")   # no transparency: iOS would paint it black
        out.save(os.path.join(HERE, name), optimize=True)
        print(name, size, os.path.getsize(os.path.join(HERE, name)), "B")


if __name__ == "__main__":
    main()
