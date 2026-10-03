"""Test client for the Jooki MQTT web protocol (bench or real device)."""
import json, time, random, threading, urllib.request, os
import paho.mqtt.client as mqtt
# Where the page is served, as on the device: since 2.1.0 the core serves it itself (adapters.httpd,
# port 8090 on the bench, see start_player.sh).
PAGE = os.environ.get("OJ_PAGE_URL") or "http://127.0.0.1:8090"
PLAYER_LOG = "/tmp/player.log"
ANY = object()          # wait_state: any truthy value

class WaitTimeout(AssertionError):
    """A wait that did not come true: the message says what was waited for and what the core shows."""

def _where(fn):
    c = getattr(fn, "__code__", None)
    return "%s:%d" % (os.path.basename(c.co_filename), c.co_firstlineno) if c else repr(fn)

def _log_tail(n=12):
    try:
        with open(PLAYER_LOG, errors="replace") as f: lines = f.read().splitlines()
        return "--- %s (last %d lines)\n%s" % (PLAYER_LOG, n, "\n".join(lines[-n:]))
    except OSError: return "(no %s)" % PLAYER_LOG

# the exceptions a condition raises while the state is not there yet (a missing key, an empty part)
_NOT_YET = (KeyError, IndexError, TypeError, AttributeError)

def wait_until(cond, t=5, what=None, every=0.05):
    """Poll `cond` until it is truthy; raise WaitTimeout after `t` seconds. Returns cond's value."""
    end = time.time() + t; last = None
    while True:
        try:
            v = cond()
            if v: return v
        except _NOT_YET as e: last = e
        if time.time() >= end: break
        time.sleep(every)
    raise WaitTimeout("%s: not true within %gs%s" % (what or "condition at " + _where(cond), t, " (last: %r)" % (last,) if last else ""))

def poll(cond, t=5, every=0.05):
    """Like wait_until, but answers False instead of raising."""
    try: return bool(wait_until(cond, t, every=every))
    except WaitTimeout: return False

class Jooki:
    def __init__(s, host="127.0.0.1", port=1883, http=PAGE, transport="tcp", user=None, pw=None, timeout=10, need_state=True, merge="parts"):
        s.host, s.http, s.merge = host, http, merge
        s.state, s.errors, s.replies, s.events, s.lock = {}, [], [], [], threading.RLock()
        s.n_full = 0                      # full states received (GET_STATE answers)
        s._subbed = threading.Event()
        s.c = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, "test%d" % random.randint(0, 10**6), transport=transport)
        if user: s.c.username_pw_set(user, pw)
        s.c.on_connect = s._connected; s.c.on_subscribe = lambda *a: s._subbed.set(); s.c.on_message = s._msg
        s.c.connect(host, port); s.c.loop_start()
        if not s._subbed.wait(timeout):
            s.close(); raise WaitTimeout("broker %s:%d: no subscription acknowledged in %gs" % (host, port, timeout))
        if need_state:
            end = time.time() + timeout
            while True:        # the core may still be connecting to the broker: ask again every 0.5 s
                s.send("GET_STATE", {})
                if poll(lambda: "db" in s.state, 0.5): break
                if time.time() >= end:
                    s.close(); raise WaitTimeout("the core did not answer GET_STATE in %gs\n%s" % (timeout, _log_tail()))
    def _connected(s, c, u, flags, rc, props=None):
        # subscribed here, so a broker restart gives the subscription back with the connection
        c.subscribe([("/j/web/output/#", 0), ("/j/web/v2/reply", 0), ("/j/web/v2/event", 0)])
    def _msg(s, c, u, m):
        try: d = json.loads(m.payload.decode())
        except Exception: d = m.payload
        with s.lock:
            if m.topic.endswith("/state") and isinstance(d, dict):
                s._merge(s.state, d)
                if "mender" in d: s.n_full += 1          # only the full answer carries the 1.x stubs
            elif m.topic.endswith("/error"): s.errors.append(d)
            elif m.topic == "/j/web/v2/reply": s.replies.append(d)
            elif m.topic == "/j/web/v2/event": s.events.append(d)
    def _merge(s, a, b):
        # the core re-sends whole top-level parts (api/v1.lua partial): replace them, so a key it
        # dropped (ssh_until, sleep) disappears here too. merge="deep" keeps the old recursive merge.
        for k, v in b.items():
            if s.merge == "parts" or k in ("db", "bedtime") or not isinstance(v, dict) or not isinstance(a.get(k), dict): a[k] = v
            else: s._merge(a[k], v)
    def send(s, typ, payload):
        s.c.publish("/j/web/input/" + typ, payload if isinstance(payload, str) else json.dumps(payload))
    # ---- reading the state
    def get(s, path, default=None):
        """s.get("audio.nowPlaying.playlistId"): walk the state; an empty part comes as [] and reads as {}."""
        with s.lock: v = s.state
        for k in path.split("."):
            if isinstance(v, list) and not v: v = {}
            if not isinstance(v, dict) or k not in v: return default
            v = v[k]
        return {} if v == [] and not isinstance(default, list) else v
    def _d(s, k):
        v = s.state.get("db", {}).get(k, {})
        return v if isinstance(v, dict) else {}
    @property
    def pls(s): return s._d("playlists")
    @property
    def tracks(s): return s._d("tracks")
    @property
    def tokens(s): return s._d("tokens")
    @property
    def np(s): return s.get("audio.nowPlaying") or {}
    @property
    def pb(s): return s.get("audio.playback.state")
    @property
    def maint(s): return s.get("maintenance") or {}
    @property
    def bt(s): return s.get("bedtime") or {}
    @property
    def nfc_state(s): return s.get("nfc") or {}      # (s.nfc() is the method that puts a token on)
    def pl_by_title(s, title):
        for k, v in s.pls.items():
            if v.get("title") == title: return k
    def excerpt(s):
        d = {"playback": s.get("audio.playback"), "nowPlaying": s.np, "nfc": s.nfc_state, "maintenance": s.maint,
             "sleep": s.get("bedtime.sleep"), "errors": s.errors[-3:]}
        return "--- state: " + json.dumps(d, default=str)[:600]
    # ---- waiting
    def wait(s, cond, t=5, what=None):
        """Wait for cond() (read under the lock); raise WaitTimeout with a state excerpt. Returns cond's value."""
        end = time.time() + t; last = None
        while True:
            try:
                with s.lock: v = cond()
                if v: return v
            except _NOT_YET as e: last = e
            if time.time() >= end: break
            time.sleep(0.05)
        raise WaitTimeout("%s: not true within %gs%s\n%s" % (what or "condition at " + _where(cond), t, " (last: %r)" % (last,) if last else "", s.excerpt()))
    def poll(s, cond, t=5):
        try: return bool(s.wait(cond, t))
        except WaitTimeout: return False
    def wait_state(s, path, value=ANY, t=5, pred=None):
        """Wait for s.get(path) == value (ANY: truthy), or for pred(value) to hold."""
        if pred: return s.wait(lambda: pred(s.get(path)), t, "%s to satisfy %s" % (path, _where(pred)))
        if value is ANY: return s.wait(lambda: s.get(path), t, "%s to be set" % path)
        s.wait(lambda: s.get(path) == value, t, "%s == %r (is %r)" % (path, value, s.get(path)))
        return value
    def refresh(s, t=5):
        """Ask the whole state again and wait for the answer: s.state is then the core's document at
        the time it read our request, every command we sent before included (the coalesced partials
        may lag by state_publish_min_interval_s; this answer does not)."""
        n = s.n_full; s.send("GET_STATE", {})
        s.wait(lambda: s.n_full > n, t, "a full state after GET_STATE")
    barrier = refresh
    def alive(s, t=5):
        """Does the core still answer? (a bool, for a check)"""
        try: s.refresh(t); return True
        except WaitTimeout: return False
    def v2(s, typ, payload=None, code=None, t=5):
        """A v2 command; returns its reply (ADR-0008)."""
        ident = "t%d" % random.randint(0, 10**9)
        msg = {"v": 2, "id": ident, "type": typ, "payload": payload or {}}
        if code: msg["code"] = code
        s.c.publish("/j/web/v2/cmd", json.dumps(msg))
        return s.wait(lambda: next((r for r in s.replies if isinstance(r, dict) and r.get("id") == ident), None), t, "reply to v2 %s" % typ)
    def mark_errors(s): return len(s.errors)
    def errors_since(s, n): return s.errors[n:]
    # ---- library helpers
    def newpl(s, title, files=(), audiobook=None, star=None, t=15):
        """PLAYLIST_NEW, the uploads one by one, then the audiobook flag / character; returns the id."""
        before = set(s.pls); payload = {"title": title}
        if audiobook is not None: payload["audiobook"] = audiobook
        s.send("PLAYLIST_NEW", payload)
        p = s.wait(lambda: len(set(s.pls) - before) == 1 and (set(s.pls) - before).pop(), 5, "PLAYLIST_NEW %r" % title)
        for i, f in enumerate(files):
            s.upload(f, p)
            s.wait(lambda: len(s.pls[p]["tracks"]) == i + 1, t, "upload %d of %r in %r" % (i + 1, f, title))
        upd = {"id": p}
        if audiobook is not None: upd["audiobook"] = audiobook
        if star: upd["star"] = star
        if len(upd) > 1:
            s.send("PLAYLIST_UPDATE", {"playlist": upd})
            s.wait(lambda: (audiobook is None or bool(s.pls[p].get("audiobook")) == audiobook) and (not star or s.pls[p].get("star") == star), 5, "PLAYLIST_UPDATE %r" % upd)
        return p
    def upload(s, path, playlistId=None, wait=False, t=15):
        uid = str(random.randint(1, 9999999)); data = open(path, "rb").read(); name = os.path.basename(path)
        b = "----jk%d" % random.randint(0, 1 << 30)
        body = ("--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\nContent-Type: audio/mpeg\r\n\r\n" % (b, uid, name)).encode() + data + ("\r\n--%s--\r\n" % b).encode()
        n0 = len(s.pls.get(playlistId, {}).get("tracks") or []) if playlistId else len(s.tracks)
        r = urllib.request.urlopen(urllib.request.Request(s.http + "/upload", data=body, method="POST", headers={"Content-Type": "multipart/form-data; boundary=" + b}), timeout=60)
        assert r.status == 200
        p = {"uploadId": uid, "filename": name}
        if playlistId: p["playlistId"] = playlistId
        s.send("PLAYLIST_ADD_UPLOAD", p)
        if wait:
            if playlistId: s.wait(lambda: len(s.pls[playlistId]["tracks"]) > n0, t, "upload of %r into %s" % (name, playlistId))
            else: s.wait(lambda: len(s.tracks) > n0, t, "upload of %r" % name)
        return uid
    # ---- the hardware side
    def nfc(s, tag, star_hex):
        s.c.publish("/j/nfc/input/tag", "%s,%s" % (tag, star_hex))
    def nfc_off(s): s.c.publish("/j/nfc/input/tag_removed", "")
    def nfc_foreign(s, tag):
        # what syslog-ng publishes when the ESP32 rejects a tag that is not a Jooki token (2.x only)
        s.c.publish("/j/nfc/input/foreign", "\x1b[0;33mW (3031532) [1:0x3ffd356c] NFC: EVT_BAD_TAG: tagId=%s - missing prefix\x1b[0m" % tag)
    def close(s): s.c.loop_stop(); s.c.disconnect()
