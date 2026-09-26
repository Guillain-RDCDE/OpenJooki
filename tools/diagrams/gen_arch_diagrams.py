# -*- coding: utf-8 -*-
"""Generates the functional diagrams of docs/21-architecture-2.0.md as plain SVG
(readable on GitHub and in VS Code, no tooling needed to view them)."""
import os, html
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "docs", "img", "arch")
os.makedirs(OUT, exist_ok=True)

OURS, KEPT, DATA, NOTE = "#fbe3cf", "#e9e9e9", "#dfeef8", "#fff8d6"
STYLE = """<style>
text{font-family:system-ui,-apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;font-size:14px;fill:#222}
.t{font-weight:700;font-size:15px}.s{font-size:12px;fill:#555}.h{font-weight:700;font-size:17px}
.box{stroke:#333;stroke-width:1.2}.dash{stroke-dasharray:6 4}
.arrow{stroke:#333;stroke-width:1.6;fill:none;marker-end:url(#a)}
.arrow2{stroke:#333;stroke-width:1.6;fill:none;marker-end:url(#a);marker-start:url(#b)}
</style>
<defs><marker id="a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="#333"/></marker>
<marker id="b" viewBox="0 0 10 10" refX="1" refY="5" markerWidth="8" markerHeight="8" orient="auto"><path d="M10 0L0 5L10 10z" fill="#333"/></marker></defs>"""

class D:
    def __init__(s, w, h): s.w, s.h, s.el = w, h, []
    def box(s, x, y, w, h, title, sub=None, fill=OURS, dash=False, r=10):
        s.el.append('<rect x="%d" y="%d" width="%d" height="%d" rx="%d" fill="%s" class="box%s"/>' % (x, y, w, h, r, fill, " dash" if dash else ""))
        lines = title.split("\n")
        ty = y + h / 2 - (len(lines) - 1) * 9 - (8 if sub else 0)
        for i, l in enumerate(lines):
            s.el.append('<text x="%d" y="%d" text-anchor="middle" class="t">%s</text>' % (x + w / 2, ty + i * 18, html.escape(l)))
        if sub:
            for i, l in enumerate(sub.split("\n")):
                s.el.append('<text x="%d" y="%d" text-anchor="middle" class="s">%s</text>' % (x + w / 2, ty + len(lines) * 18 - 2 + i * 15, html.escape(l)))
    def text(s, x, y, t, cls="", anchor="start"):
        for i, l in enumerate(t.split("\n")):
            s.el.append('<text x="%d" y="%d" text-anchor="%s" class="%s">%s</text>' % (x, y + i * 17, anchor, cls, html.escape(l)))
    def arrow(s, pts, label=None, both=False, lx=None, ly=None):
        d = "M" + " L".join("%d %d" % p for p in pts)
        s.el.append('<path d="%s" class="%s"/>' % (d, "arrow2" if both else "arrow"))
        if label:
            mx, my = pts[len(pts) // 2] if len(pts) > 2 else ((pts[0][0] + pts[1][0]) / 2, (pts[0][1] + pts[1][1]) / 2)
            lines = label.split("\n"); w = max(len(l) for l in lines) * 6.4 + 10; h = len(lines) * 15 + 4
            X, Y = (lx or mx), (ly or my - 6)
            s.el.append('<rect x="%d" y="%d" width="%d" height="%d" fill="#fff" rx="3"/>' % (X - w / 2, Y - 12, w, h))
            for i, l in enumerate(lines):
                s.el.append('<text x="%d" y="%d" text-anchor="middle" class="s">%s</text>' % (X, Y + i * 15, html.escape(l)))
    def line(s, x1, y1, x2, y2, dash=True):
        s.el.append('<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="#999" stroke-width="1" %s/>' % (x1, y1, x2, y2, 'stroke-dasharray="6 4"' if dash else ""))
    def legend(s, x, y, items):
        for i, (fill, label) in enumerate(items):
            s.el.append('<rect x="%d" y="%d" width="16" height="16" rx="3" fill="%s" class="box"/>' % (x + i * 215, y, fill))
            s.el.append('<text x="%d" y="%d" class="s">%s</text>' % (x + i * 215 + 22, y + 13, html.escape(label)))
    def save(s, name, title):
        svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" width="%d" height="%d" role="img" aria-label="%s">%s<rect width="%d" height="%d" fill="#fff"/>%s</svg>' % (
            s.w, s.h, s.w, s.h, html.escape(title), STYLE, s.w, s.h, "\n".join(s.el))
        open(os.path.join(OUT, name), "w", encoding="utf-8").write(svg)

# 1. Context ------------------------------------------------------------------
d = D(960, 545)
d.text(20, 30, "The Jooki v2 at runtime: what we own, what we keep", "h")
d.box(360, 60, 240, 90, "Web page", "phone or computer\n(ours, 1.x → 2.0)")
d.arrow([(480, 150), (480, 205)], "MQTT over WebSocket :8000\n+ HTTP /upload", both=True, ly=170)
d.box(300, 205, 360, 120, "THE CORE (2.0)", "player.lib — application logic\nplaylists · tokens · playback · bedtime · network\nreadable open-source Lua, built into the Jooki format")
d.box(40, 430, 880, 34, "MQTT bus — mosquitto :1883 (open on the LAN today; localhost in 2.0)", fill=KEPT, r=6)
d.arrow([(565, 325), (565, 430)], "commands ↓   events ↑", both=True, lx=680, ly=352)
kept = [("esp32_ctrl", "Wi-Fi · Bluetooth · NFC\n(ESP32 chip)"), ("gpio_ctrl", "buttons"), ("ht_ctrl", "lights"), ("audio_ctrl", "sound output\n(GStreamer, ALSA)"), ("web_ctrl", "HTTP server\nstatic files, /upload")]
for i, (n, sub) in enumerate(kept):
    x = 40 + i * 178
    d.box(x, 370, 160, 50, n, fill=KEPT, r=8)
    d.text(x + 80, 484, sub, "s", "middle")
for i in range(5):
    x = 120 + i * 178
    d.arrow([(x, 430), (x, 420)])
d.box(40, 60, 260, 90, "C host `player`", "loads player.lib (zlib, 200 KiB)\ngives 4 functions: ALSA volume,\nsyslog, terminating?, sd_notify", fill=KEPT, dash=True)
d.arrow([(300, 105), (380, 205)], "runs")
d.box(700, 60, 220, 90, "Data partition", "/jooki/external/jooki\nmusic files + JSON databases", fill=DATA)
d.arrow([(700, 105), (620, 205)], "reads / writes", both=True)
d.legend(30, 520, [(OURS, "ours (open source)"), (KEPT, "kept as is (closed, works)"), (DATA, "family data")])
d.save("01-context.svg", "Context: what we own, what we keep")

# 2. Event loop ---------------------------------------------------------------
d = D(960, 380)
d.text(20, 30, "One loop, one clock, one queue: how the core runs", "h")
d.box(30, 70, 190, 60, "Bus messages", "from daemons and page", fill=KEPT)
d.box(30, 150, 190, 60, "Timers", "bedtime tick, health,\nautosave, inactivity", fill=KEPT)
d.box(30, 230, 190, 60, "Signals", "stop request from host", fill=KEPT)
d.box(290, 130, 170, 100, "Queue", "events, in order\nnothing runs in parallel")
for y in (100, 180, 260): d.arrow([(220, y), (290, 180 if y == 180 else (150 if y == 100 else 210))])
d.box(530, 110, 200, 140, "Dispatcher", "one handler per event type\neach call protected (pcall)\nfailure → logged + isolated\nnever stops the loop")
d.arrow([(460, 180), (530, 180)])
d.box(790, 70, 150, 60, "Commands", "to daemons (bus)", fill=KEPT)
d.box(790, 150, 150, 60, "State", "revision n+1, published\nto the page", fill=DATA)
d.box(790, 230, 150, 60, "Files", "atomic writes", fill=DATA)
for y in (100, 180, 260): d.arrow([(730, 180), (790, y)])
d.text(30, 330, "Rule: a handler is a pure function of (state, event) → (new state, commands). No handler reads the clock, the files\nor the network directly: it receives what it needs and returns what must be done. That is what makes it testable.", "s")
d.save("02-loop.svg", "Event loop")

# 3. Modules and dependency rule ---------------------------------------------
d = D(960, 545)
d.text(20, 30, "Modules and the only dependency rule: arrows go down, never up", "h")
d.box(30, 60, 900, 70, "api  —  the contract with the page (v2, and v1 kept for compatibility)", "validates every message, maps it to a core command, publishes state and typed errors")
d.box(30, 160, 900, 190, "", fill="#fdf1e6", dash=True)
d.text(45, 182, "core services (plain Lua tables + functions, no I/O)", "t")
mods = [("library", "playlists, tracks,\ntokens, unused"), ("playback", "state machine,\nqueue, resume"), ("tokens", "NFC → character\n→ playlist"), ("bedtime", "timer, fade,\nnight window"), ("device", "volume & limits,\nlights, power,\nbuttons"), ("network", "Wi-Fi manager,\nhealth, mDNS"), ("update", "check, start,\nrollback info")]
for i, (n, sub) in enumerate(mods):
    x = 45 + i * 126
    d.box(x, 200, 116, 130, n, sub)
d.box(30, 380, 430, 110, "ports & adapters (all I/O lives here)", "bus (MQTT)  ·  files (atomic JSON)  ·  clock  ·  host (ALSA, syslog)\nshell (the few scripts we still call)  ·  mdns (UDP socket)", fill=KEPT)
d.box(500, 380, 430, 110, "kernel", "event loop, timers, dispatcher, structured log,\nconfig, schema versions & migrations")
d.arrow([(480, 130), (480, 160)])
d.arrow([(245, 350), (245, 380)])
d.arrow([(715, 350), (715, 380)])
d.text(30, 512, "Test rule: a core service is tested with fake adapters (fake clock, fake bus, in-memory files).\nAdapters are tested alone against the real thing (mosquitto, disk).", "s")
d.save("03-modules.svg", "Modules")

# 4. Playback state machine ---------------------------------------------------
d = D(960, 400)
d.text(20, 30, "Playback: one state machine, five states, no surprises", "h")
d.box(40, 120, 130, 60, "idle")
d.box(240, 120, 130, 60, "starting", "command sent,\nwaiting for audio")
d.box(440, 120, 130, 60, "playing")
d.box(440, 230, 130, 60, "paused")
d.box(640, 120, 130, 60, "ended", "track finished")
d.arrow([(170, 150), (240, 150)], "play(track)")
d.arrow([(370, 150), (440, 150)], "audio: playing")
d.arrow([(505, 180), (505, 230)], "pause", lx=470)
d.arrow([(540, 230), (540, 180)], "resume", lx=580)
d.arrow([(570, 150), (640, 150)], "audio: ended")
d.arrow([(705, 120), (705, 80), (305, 80), (305, 120)], "next track (if any)", ly=74)
d.arrow([(770, 150), (840, 150), (840, 290), (105, 290), (105, 180)], "no next track / stop", lx=300, ly=284)
d.text(40, 330, "Every transition saves the resume position (audiobooks), updates the lights and publishes the state.\nAnything else (a message that does not fit the current state) is logged and ignored — never applied.", "s")
d.save("04-playback.svg", "Playback state machine")

# 5. Token tap sequence -------------------------------------------------------
d = D(960, 350)
d.text(20, 30, "A token is put on the Jooki: what happens, in order (< 1 s)", "h")
steps = [("esp32_ctrl", "token UID +\ncharacter code", KEPT), ("tokens", "character → playlist\nunknown one: learn it", OURS), ("library", "tracks of the playlist\n(audiobook? shuffle?)", OURS), ("playback", "resume position?\nbuild play command", OURS), ("bedtime", "night? → timer,\nvolume limit", OURS), ("audio_ctrl", "plays the file", KEPT)]
for i, (n, sub, f) in enumerate(steps):
    x = 30 + i * 155
    d.box(x, 90, 140, 80, n, sub, fill=f)
    if i < 5: d.arrow([(x + 140, 130), (x + 155, 130)])
d.box(30, 220, 900, 60, "state published to the page: nowPlaying, playback, bedtime.sleep  —  lights: playing", fill=DATA)
d.arrow([(480, 170), (480, 220)])
d.text(30, 310, "Empty playlist → the \"empty\" sound, no error beep.   Unknown character → learned, shown on the page, nothing plays.\nAny failure → logged, lights show an error, the loop goes on.", "s")
d.save("05-token.svg", "Token sequence")

# 6. Storage ------------------------------------------------------------------
d = D(960, 360)
d.text(20, 30, "Data: same files as 1.x, written so that a power cut can never lose them", "h")
files = [("playlists.json", "v1 → v2 migration"), ("tracks.json", "one entry per file"), ("tokens.json", "UID → character"), ("audiocfg.json", "volume, modes"), ("bedtime.json", "night settings"), ("resume.json", "audiobook positions")]
for i, (n, sub) in enumerate(files):
    d.box(30 + i * 155, 70, 140, 60, n, sub, fill=DATA, r=6)
d.text(30, 160, "/jooki/external/jooki/  (data partition, untouched by firmware updates — 1.x and 2.0 read the same files, so a rollback keeps the library)", "s")
d.box(30, 200, 170, 60, "1. write .tmp")
d.box(230, 200, 170, 60, "2. fsync")
d.box(430, 200, 170, 60, "3. rename over\nthe old file")
d.box(630, 200, 170, 60, "4. keep .bak\n(previous version)")
for x in (200, 400, 600): d.arrow([(x, 230), (x + 30, 230)])
d.box(830, 190, 100, 80, "on load", "schema version\n→ migrate", fill=NOTE)
d.text(30, 300, "Read: file → if unreadable, .bak → if unreadable, empty database + loud log line (never a crash).\nWrite: only when something changed, at most once per second, and always before power-off.", "s")
d.save("06-storage.svg", "Storage")

# 7. Delivery pipeline --------------------------------------------------------
d = D(960, 300)
d.text(20, 30, "From a source change to a child's Jooki: every step checked, every step reversible", "h")
steps = [("sources", "readable Lua\nmodules + tests", OURS), ("build", "bundle · strip\n≤ 176 KiB check\ndeterministic", OURS), ("bench (CI)", "179+ checks on\nevery push\nreal mosquitto", OURS), ("release", "image + sha256\n+ version.json\nfrom a green commit", OURS), ("Jooki (A/B)", "spare partition\nrollback armed\nold core kept", KEPT)]
for i, (n, sub, f) in enumerate(steps):
    x = 30 + i * 186
    d.box(x, 80, 170, 100, n, sub, fill=f)
    if i < 4: d.arrow([(x + 170, 130), (x + 186, 130)])
d.text(30, 220, "Red at any step = nothing goes further. A release is a script run, never a manual copy.\nOn the Jooki, the previous version stays bootable: one command (or an automatic rollback) brings it back.", "s")
d.save("07-pipeline.svg", "Delivery pipeline")

# 8. Wi-Fi safe switch --------------------------------------------------------
d = D(960, 300)
d.text(20, 30, "Changing access point without ever losing the Jooki", "h")
steps = [("1. keep", "the working network\nstays configured"), ("2. add", "the new network is\nadded, not swapped"), ("3. try", "when idle: connect\nto the new one"), ("4. prove", "IP + page reachable\nfor 2 minutes"), ("5. prefer", "new one becomes\nthe first choice")]
for i, (n, sub) in enumerate(steps):
    x = 30 + i * 186
    d.box(x, 80, 170, 90, n, sub)
    if i < 4: d.arrow([(x + 170, 125), (x + 186, 125)])
d.arrow([(680, 170), (680, 220), (300, 220), (300, 170)], "not proved → back to the old one, nothing lost", ly=214)
d.text(30, 270, "Still offline? Bluetooth rescue: the Jooki advertises its provisioning service; a computer or Android phone scans and gives it a network (docs/20).", "s")
d.save("08-wifi-switch.svg", "Wi-Fi safe switch")
print("ok", sorted(os.listdir(OUT)))
