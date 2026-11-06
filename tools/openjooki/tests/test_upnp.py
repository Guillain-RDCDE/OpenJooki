#!/usr/bin/env python3
"""The Jooki as a UPnP / DLNA player (#29), against the real core.

A fake phone app does what BubbleUPnP or mconnect do, over the real network code:
  - finds the Jooki by SSDP (M-SEARCH on UDP 1900), reads its description and its three services,
  - subscribes to its events (GENA) and receives them on its own little web server,
  - sends a song (SetAVTransportURI + DIDL-Lite), plays, reads the position, seeks, pauses, sets
    the volume, stops; a format the Jooki cannot read is refused,
  - sees STOPPED when a playlist of the Jooki takes over,
and the switch: off by default (no answer, 404), off again = the song stops and the Jooki goes quiet.
The bench's Jooki has the address 10.0.0.2 (setup.sh): the descriptions say it, the requests go to
127.0.0.1.
  python3 test_upnp.py
"""
import http.client, http.server, json, re, socket, threading, time
import xml.etree.ElementTree as ET
import bench as B

R = B.Results(); check = R.check
HTTP = B.HTTP_PORT
SSDP = ("127.0.0.1", 1900)
AVT = "urn:schemas-upnp-org:service:AVTransport:1"
RC = "urn:schemas-upnp-org:service:RenderingControl:1"
CM = "urn:schemas-upnp-org:service:ConnectionManager:1"
SONG = "http://192.168.1.20:9790/minimserver/*/Music/Anne/01%20L'ete.flac"
DIDL = ('<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/"><item id="1" parentID="0" restricted="1">'
        "<dc:title>L'été &amp; co</dc:title><upnp:artist>Anne</upnp:artist><upnp:album>Songs</upnp:album>"
        "<upnp:albumArtURI>http://192.168.1.20/art.jpg</upnp:albumArtURI><upnp:class>object.item.audioItem.musicTrack</upnp:class>"
        '<res protocolInfo="http-get:*:audio/flac:DLNA.ORG_OP=01" duration="0:03:25.000">%s</res></item></DIDL-Lite>')


def xml_escape(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")


def msearch(st, t=1.5):
    """A unicast M-SEARCH (what a phone sends to the group, sent to the Jooki directly); its answers."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(0.3)
    s.sendto(('M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: "ssdp:discover"\r\nMX: 1\r\nST: %s\r\n\r\n' % st).encode(), SSDP)
    out, end = [], time.time() + t
    while time.time() < end:
        try: out.append(s.recv(2048).decode())
        except socket.timeout: pass
    s.close()
    return out


def header(resp, name):
    m = re.search(r"\r\n%s:[ \t]*([^\r\n]*)" % re.escape(name), resp, re.I)
    return m.group(1) if m else None


def req(method, path, body=b"", headers=None):
    c = http.client.HTTPConnection("127.0.0.1", HTTP, timeout=5)
    h = {"Host": "10.0.0.2:%d" % HTTP}
    h.update(headers or {})
    c.request(method, path, body=body, headers=h)
    r = c.getresponse()
    data = r.read().decode("utf-8", "replace")
    hdrs = {k.lower(): v for k, v in r.getheaders()}
    c.close()
    return r.status, data, hdrs


def soap(key, stype, action, args=()):
    """A control request; returns (HTTP status, {out argument: value}, UPnP error code or None)."""
    inner = "".join("<%s>%s</%s>" % (k, xml_escape(v), k) for k, v in args)
    body = ('<?xml version="1.0" encoding="utf-8"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
            's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:%s xmlns:u="%s">%s</u:%s></s:Body></s:Envelope>'
            % (action, stype, inner, action)).encode()
    st, data, _ = req("POST", "/upnp/ctl/" + key, body, {"Content-Type": 'text/xml; charset="utf-8"', "SOAPACTION": '"%s#%s"' % (stype, action)})
    try: root = ET.fromstring(data)
    except ET.ParseError: return st, {"_raw": data}, None
    out, code = {}, None
    for el in root.iter():
        tag = el.tag.split("}")[-1]
        if tag == action + "Response":
            for ch in el: out[ch.tag.split("}")[-1]] = ch.text or ""
        if tag == "errorCode": code = int(el.text)
    return st, out, code


IID = ("InstanceID", "0")
def avt(action, *args): return soap("avt", AVT, action, (IID,) + args)
def state(): return avt("GetTransportInfo")[1].get("CurrentTransportState")


# ------------------------------------------------------------------ the phone app's event server
EVENTS = []
class Ev(http.server.BaseHTTPRequestHandler):
    def do_NOTIFY(s):
        n = int(s.headers.get("Content-Length") or 0)
        EVENTS.append({"path": s.path, "sid": s.headers.get("SID"), "seq": s.headers.get("SEQ"), "nts": s.headers.get("NTS"),
                       "body": s.rfile.read(n).decode("utf-8", "replace")})
        s.send_response(200); s.send_header("Content-Length", "0"); s.end_headers()
    def log_message(s, *a): pass
ev_srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Ev)
EV_PORT = ev_srv.server_address[1]
threading.Thread(target=ev_srv.serve_forever, daemon=True).start()

def last_change(path):
    """The newest LastChange received on `path`, decoded: {variable: value}."""
    for e in reversed(EVENTS):
        if e["path"] != path: continue
        prop = ET.fromstring(e["body"])
        lc = next((x.text for x in prop.iter() if x.tag.split("}")[-1] == "LastChange"), None)
        if not lc: continue
        return {x.tag.split("}")[-1]: x.get("val") for x in ET.fromstring(lc).iter() if x.get("val") is not None}
    return {}


j = B.boot(seed=True)
audio_out = B.Spy("/j/audio/out/#", name="upnp-audio")
# the Wi-Fi chip gives the Jooki its address (SSDP says it in LOCATION; test_net.py does the same)
j.c.publish("/j/esp32/input/net/sta/config", '{"ssid":"Box","signal":-50,"stat":"success","ip":"10.0.0.2"}')
R.expect("U0 the Jooki knows its address", lambda: j.get("net.ip") == "10.0.0.2", 25, lambda: j.get("net"))

# --- U1 off by default
check("U1 off by default: the switch says so", j.get("audio.config.upnp") is False, j.get("audio.config"))
check("U1 off: no answer to a search", msearch("ssdp:all") == [])
check("U1 off: no description (404)", req("GET", "/upnp/desc.xml")[0] == 404)

# --- U2 turned on: found by SSDP
j.send("SET_CFG", {"upnp": True})
R.expect("U2 the switch turns on", lambda: j.get("audio.config.upnp") is True, 5, lambda: j.get("audio.config"))
answers = msearch("ssdp:all")
R.expect("U2 ssdp:all: the root device, the UDN, the renderer and its three services", lambda: len(msearch("ssdp:all")) == 6, 5,
         lambda: answers)
answers = msearch("urn:schemas-upnp-org:device:MediaRenderer:1")
check("U2 a search for a MediaRenderer finds it", len(answers) == 1 and header(answers[0], "ST") == "urn:schemas-upnp-org:device:MediaRenderer:1", answers)
loc = header(answers[0], "LOCATION") if answers else None
check("U2 its description is on the Jooki's own web server", loc == "http://10.0.0.2:%d/upnp/desc.xml" % HTTP, loc)
usn = header(answers[0], "USN") if answers else ""
check("U2 USN = UDN::type", bool(re.match(r"^uuid:4a6f6f6b-6900-4f70-656e-[0-9a-f]{12}::urn:schemas-upnp-org:device:MediaRenderer:1$", usn or "")), usn)
check("U2 a MediaServer search is not answered", msearch("urn:schemas-upnp-org:device:MediaServer:1") == [])

# --- U3 the descriptions are valid XML and agree with each other
st, desc, hd = req("GET", "/upnp/desc.xml")
ns = {"d": "urn:schemas-upnp-org:device-1-0"}
root = ET.fromstring(desc)
dev = root.find("d:device", ns)
check("U3 description: a MediaRenderer, named after the Jooki", st == 200 and hd.get("content-type", "").startswith("text/xml")
      and dev.findtext("d:deviceType", None, ns) == "urn:schemas-upnp-org:device:MediaRenderer:1"
      and dev.findtext("d:friendlyName", None, ns) == "Jooki-bench", (st, desc[:300]))
check("U3 the UDN of the description is the one SSDP gave", usn.startswith(dev.findtext("d:UDN", "", ns) + "::"), (usn, dev.findtext("d:UDN", "", ns)))
svcs = {s.findtext("d:serviceType", None, ns): s for s in dev.find("d:serviceList", ns)}
check("U3 three services", set(svcs) == {AVT, RC, CM}, list(svcs))
sns = {"s": "urn:schemas-upnp-org:service-1-0"}
for stype, s in svcs.items():
    st, x, _ = req("GET", s.findtext("d:SCPDURL", None, ns))
    sc = ET.fromstring(x)
    names = {v.findtext("s:name", None, sns) for v in sc.iter("{urn:schemas-upnp-org:service-1-0}stateVariable")}
    rel = {a.findtext("s:relatedStateVariable", None, sns) for a in sc.iter("{urn:schemas-upnp-org:service-1-0}argument")}
    check("U3 %s: every argument's variable is declared" % stype.split(":")[-2], st == 200 and rel <= names and len(rel) > 0, rel - names)

# --- U4 events: subscribe like an app
cb = "http://127.0.0.1:%d/avt" % EV_PORT
st, _, hd = req("SUBSCRIBE", "/upnp/evt/avt", headers={"CALLBACK": "<%s>" % cb, "NT": "upnp:event", "TIMEOUT": "Second-300"})
sid = hd.get("sid")
check("U4 subscribed: a SID and the timeout", st == 200 and (sid or "").startswith("uuid:") and hd.get("timeout") == "Second-300", (st, hd))
st, _, hd2 = req("SUBSCRIBE", "/upnp/evt/rc", headers={"CALLBACK": "<http://127.0.0.1:%d/rc>" % EV_PORT, "NT": "upnp:event", "TIMEOUT": "Second-300"})
check("U4 subscribed to the volume too", st == 200 and hd2.get("sid"), (st, hd2))
R.expect("U4 the first event comes by itself (SEQ 0, nothing sent yet)",
         lambda: any(e["path"] == "/avt" and e["seq"] == "0" and e["sid"] == sid for e in EVENTS)
         and last_change("/avt").get("TransportState") == "NO_MEDIA_PRESENT", 5, lambda: EVENTS)
check("U4 nothing to play yet: Play is refused (701)", avt("Play", ("Speed", "1"))[2] == 701)

# --- U5 an app sends a song
st, out, code = avt("SetAVTransportURI", ("CurrentURI", SONG), ("CurrentURIMetaData", DIDL % xml_escape(SONG)))
check("U5 SetAVTransportURI accepted", st == 200 and code is None, (st, out, code))
R.expect("U5 the song is known, not playing yet (STOPPED)", lambda: state() == "STOPPED", 5, state)
mi = avt("GetMediaInfo")[1]
check("U5 GetMediaInfo: the address, the duration, the metadata back", mi.get("CurrentURI") == SONG and mi.get("MediaDuration") == "0:03:25"
      and "<dc:title>L'été &amp; co</dc:title>" in (mi.get("CurrentURIMetaData") or ""), mi)

# --- U6 Play: on the Jooki's own player, shown on the page, said by an event
n = audio_out.mark()
check("U6 Play accepted", avt("Play", ("Speed", "1"))[0] == 200)
R.expect("U6 the player is asked to play the address (stream 7)", lambda: ("/j/audio/out/play", "7\t" + SONG) in [(t, p) for t, p in audio_out.since(n)], 5,
         lambda: audio_out.since(n))
R.expect("U6 PLAYING", lambda: state() == "PLAYING", 5, state)
R.expect("U6 the page shows it: title, artist, picture, length",
         lambda: j.np.get("service") == "UPNP" and j.np.get("track") == "L'été & co" and j.np.get("artist") == "Anne"
         and j.np.get("image") == "http://192.168.1.20/art.jpg" and j.np.get("duration_ms") == 205000 and j.pb == "PLAYING", 5, lambda: (j.np, j.pb))
R.expect("U6 the app hears it (event: PLAYING, the song's address)",
         lambda: last_change("/avt").get("TransportState") == "PLAYING" and last_change("/avt").get("AVTransportURI") == SONG, 5, lambda: last_change("/avt"))
seqs = [int(e["seq"]) for e in EVENTS if e["sid"] == sid]
check("U6 events in order (SEQ 0, 1, 2...)", seqs == list(range(len(seqs))), seqs)

# --- U7 position, seek, pause, play on
R.expect("U7 the position moves on", lambda: avt("GetPositionInfo")[1].get("RelTime") not in (None, "0:00:00"), 5, lambda: avt("GetPositionInfo")[1])
pi = avt("GetPositionInfo")[1]
check("U7 GetPositionInfo: track 1, its length and address", pi.get("Track") == "1" and pi.get("TrackDuration") == "0:03:25" and pi.get("TrackURI") == SONG, pi)
n = audio_out.mark()
check("U7 Seek to 1:30", avt("Seek", ("Unit", "REL_TIME"), ("Target", "0:01:30"))[0] == 200)
R.expect("U7 the player seeks to 90 000 ms", lambda: ("/j/audio/out/seek", "7\t90000") in audio_out.since(n), 5, lambda: audio_out.since(n))
R.expect("U7 the app reads the new position", lambda: avt("GetPositionInfo")[1].get("RelTime", "").startswith("0:01:3"), 5, lambda: avt("GetPositionInfo")[1])
check("U7 an unreadable seek target is refused (711)", avt("Seek", ("Unit", "REL_TIME"), ("Target", "soon"))[2] == 711)
check("U7 Pause", avt("Pause")[0] == 200)
R.expect("U7 PAUSED_PLAYBACK, on the page too", lambda: state() == "PAUSED_PLAYBACK" and j.pb == "PAUSED", 5, lambda: (state(), j.pb))
R.expect("U7 the app hears the pause", lambda: last_change("/avt").get("TransportState") == "PAUSED_PLAYBACK", 5, lambda: last_change("/avt"))
check("U7 Play again", avt("Play", ("Speed", "1"))[0] == 200)
R.expect("U7 plays on (PLAYING)", lambda: state() == "PLAYING" and j.pb == "PLAYING", 5, lambda: (state(), j.pb))
j.send("DO_PAUSE", {})
R.expect("U7 the page's pause pauses the app's song; the app sees it", lambda: state() == "PAUSED_PLAYBACK", 5, state)
avt("Play", ("Speed", "1"))
R.expect("U7 and the app plays it on", lambda: state() == "PLAYING", 5, state)

# --- U8 volume
st, out, code = soap("rc", RC, "SetVolume", (IID, ("Channel", "Master"), ("DesiredVolume", "55")))
check("U8 SetVolume 55", st == 200 and code is None, (st, out, code))
R.expect("U8 it is the Jooki's volume (the page's slider)", lambda: j.get("audio.config.volume") == 55, 5, lambda: j.get("audio.config"))
check("U8 GetVolume reads it", soap("rc", RC, "GetVolume", (IID, ("Channel", "Master")))[1].get("CurrentVolume") == "55")
R.expect("U8 the app hears the volume (event)", lambda: last_change("/rc").get("Volume") == "55", 5, lambda: last_change("/rc"))
j.send("SET_VOL", {"vol": 30})
R.expect("U8 the page's volume reaches the app too", lambda: soap("rc", RC, "GetVolume", (IID, ("Channel", "Master")))[1].get("CurrentVolume") == "30"
         and last_change("/rc").get("Volume") == "30", 5, lambda: last_change("/rc"))
check("U8 a volume over 100 is refused (402)", soap("rc", RC, "SetVolume", (IID, ("Channel", "Master"), ("DesiredVolume", "120")))[2] == 402)
check("U8 ConnectionManager lists FLAC and MP3, not AAC",
      all(m in soap("cm", CM, "GetProtocolInfo")[1].get("Sink", "") for m in ("audio/flac", "audio/mpeg")) and "aac" not in soap("cm", CM, "GetProtocolInfo")[1].get("Sink", ""))

# --- U9 refusals
aac = DIDL.replace("audio/flac", "audio/mp4") % xml_escape(SONG)
check("U9 a song the Jooki cannot read (MP4/AAC) is refused (714)", avt("SetAVTransportURI", ("CurrentURI", SONG), ("CurrentURIMetaData", aac))[2] == 714)
check("U9 ... and the song that plays is not touched", state() == "PLAYING" and avt("GetMediaInfo")[1].get("CurrentURI") == SONG)
check("U9 an address that is not http is refused (714)", avt("SetAVTransportURI", ("CurrentURI", "file:///etc/shadow"), ("CurrentURIMetaData", ""))[2] == 714)
check("U9 an unknown action is refused (401)", avt("Record")[2] == 401)
check("U9 another instance is refused (718)", soap("avt", AVT, "Stop", (("InstanceID", "3"),))[2] == 718)
check("U9 an unknown path is 404", req("GET", "/upnp/nope.xml")[0] == 404 and req("POST", "/upnp/ctl/nope", b"x")[0] == 404)

# --- U10 a playlist of the Jooki takes over; the app sees STOPPED and takes it back with Play
pid = j.pl_by_title("Comptines 2")
r = j.v2("playback.play", {"playlist": pid})
R.expect("U10 the Jooki's own playlist plays", lambda: j.np.get("playlistId") == pid and j.pb == "PLAYING", 5, lambda: (r, j.np))
R.expect("U10 the app sees STOPPED (event too)", lambda: state() == "STOPPED" and last_change("/avt").get("TransportState") == "STOPPED", 5,
         lambda: (state(), last_change("/avt")))
n = audio_out.mark()
avt("Pause"); avt("Stop"); B.quiet(1, "a Pause/Stop from the app would have reached the player by now")
check("U10 Pause and Stop from the app do not touch the Jooki's playlist", not [x for x in audio_out.since(n) if x[0] in ("/j/audio/out/pauz", "/j/audio/out/stop")]
      and j.np.get("playlistId") == pid, audio_out.since(n))
avt("Play", ("Speed", "1"))
R.expect("U10 Play from the app takes it back", lambda: state() == "PLAYING" and j.np.get("service") == "UPNP", 5, lambda: (state(), j.np))

# --- U11 a new song while one plays: it plays at once
SONG2 = "http://192.168.1.20:9790/minimserver/*/Music/b.mp3"
avt("SetAVTransportURI", ("CurrentURI", SONG2), ("CurrentURIMetaData", ""))
R.expect("U11 the new song plays at once", lambda: j.np.get("uri") == SONG2 and state() == "PLAYING", 5, lambda: (j.np, state()))

# --- U11b the player cannot play it (audio_ctrl's error): the app sees STOPPED and can move on
j.c.publish("/j/audio/input/error", json.dumps({"id": 7}))
R.expect("U11b a player error: STOPPED, the event says it", lambda: state() == "STOPPED" and last_change("/avt").get("TransportState") == "STOPPED", 5,
         lambda: (state(), last_change("/avt")))
check("U11b https is refused at once (no TLS in the Jooki's player)",
      avt("SetAVTransportURI", ("CurrentURI", "https://cdn.example/a.flac"), ("CurrentURIMetaData", ""))[2] == 714)
avt("Play", ("Speed", "1"))
R.expect("U11b Play again after the error", lambda: state() == "PLAYING", 5, state)

# --- U12 Stop, unsubscribe, then off
check("U12 Stop", avt("Stop")[0] == 200)
R.expect("U12 STOPPED, the Jooki idle", lambda: state() == "STOPPED" and j.pb in ("STOPPED", None), 5, lambda: (state(), j.pb))
st, _, _ = req("UNSUBSCRIBE", "/upnp/evt/avt", headers={"SID": sid})
check("U12 unsubscribed", st == 200)
k = len(EVENTS); avt("Play", ("Speed", "1")); B.quiet(1.5, "an event to an unsubscribed app would have come")
check("U12 no more events after unsubscribing", not [e for e in EVENTS[k:] if e["path"] == "/avt"], EVENTS[k:])
R.expect("U12 playing again before the switch goes off", lambda: j.np.get("service") == "UPNP" and j.pb == "PLAYING", 5, lambda: (j.np, j.pb))
j.send("SET_CFG", {"upnp": False})
R.expect("U12 off: the app's song stops", lambda: j.get("audio.config.upnp") is False and j.pb in ("STOPPED", None), 5, lambda: (j.get("audio.config"), j.pb))
R.expect("U12 off: no answer to a search, the descriptions are gone", lambda: msearch("ssdp:all") == [] and req("GET", "/upnp/desc.xml")[0] == 404, 5)

# --- U13 garbage never hurts the player
j.send("SET_CFG", {"upnp": True})
R.expect("U13 on again", lambda: len(msearch("upnp:rootdevice")) == 1, 5)
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
for p in (b"", b"\xff" * 300, b"M-SEARCH\r\n\r\n", b'M-SEARCH * HTTP/1.1\r\nMAN: "ssdp:discover"\r\n\r\n', b"NOTIFY * HTTP/1.1\r\nNT: x\r\n\r\n"):
    s.sendto(p, SSDP)
s.close()
for body in (b"", b"<not-xml", b"<s:Envelope><s:Body></s:Body></s:Envelope>", b"x" * 70000):
    try: req("POST", "/upnp/ctl/avt", body)
    except Exception: pass
check("U13 subscription without a callback refused (412)", req("SUBSCRIBE", "/upnp/evt/avt", headers={"NT": "upnp:event"})[0] == 412)
check("U13 subscription to an app that does not answer: the Jooki goes on",
      req("SUBSCRIBE", "/upnp/evt/avt", headers={"CALLBACK": "<http://127.0.0.1:9/x>", "NT": "upnp:event"})[0] == 200)
B.quiet(2, "the events to the dead subscriber are tried and dropped")
check("U13 after garbage and a dead subscriber: still found", len(msearch("upnp:rootdevice")) == 1)
check("U13 ... still answering (turned off, it forgot the song: NO_MEDIA_PRESENT)", state() == "NO_MEDIA_PRESENT", state())
check("U13 ... the player is alive", j.alive())
j.send("SET_CFG", {"upnp": False})
R.expect("U13 off again (the switch stays off for the next suites)", lambda: j.get("audio.config.upnp") is False, 5)

B.check_clean_log(R, "U14 no error in the log")
audio_out.close()
ev_srv.shutdown()
j.close()
R.finish()
