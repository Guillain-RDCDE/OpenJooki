"""Security switches over the bus, against the real core (docs/adr/0007):
SSH one-hour toggle, MQTT-on-the-LAN toggle, the other addresses of the page (#45), and the
parent-code gate.
  python3 test_security_backend.py"""
import http.client
import bench as B
R = B.Results(); check = R.check

j = B.boot()        # setup.sh leaves no parent code, no LAN flag, no key behind
maint = lambda: j.maint

# --- SSH one-hour toggle ---
j.send("OJ_SSH_ON", {})
R.expect("SSH on: state reflects it, with an end time", lambda: maint().get("ssh") is True and isinstance(maint().get("ssh_until"), (int, float)), 5, maint)
j.send("OJ_SSH_OFF", {})
R.expect("SSH off", lambda: maint().get("ssh") is False, 5, maint)

# --- MQTT on the LAN toggle ---
j.send("OJ_MQTT_LAN", {"on": True})
R.expect("MQTT on the LAN: on", lambda: maint().get("mqtt_lan") is True, 5, maint)
j.send("OJ_MQTT_LAN", {"on": False})
R.expect("MQTT on the LAN: off", lambda: maint().get("mqtt_lan") is False, 5, maint)

# --- other addresses for the page (#45): the core's own web server, over real HTTP ---
def host_status(host):
    c = http.client.HTTPConnection("127.0.0.1", B.HTTP_PORT, timeout=5)
    try:
        c.request("GET", "/", headers={"Host": host}); return c.getresponse().status
    finally: c.close()
REFUSED = 421
check("no names listed at first start", maint().get("web_names") == [], maint())
check("someone's domain is refused (DNS rebinding)", host_status("jooki.example.com") == REFUSED, host_status("jooki.example.com"))
for h in ("jooki.lan", "jooki.home.arpa:8090", "jooki.internal", "jooki.local", "127.0.0.1:8090"):
    check("a home-network name is taken: " + h, host_status(h) != REFUSED, host_status(h))
j.send("OJ_WEB_NAMES", {"names": ["Jooki.Example.com", "kids-room"]})
R.expect("other addresses saved, cleaned", lambda: maint().get("web_names") == ["jooki.example.com", "kids-room"], 5, maint)
check("a listed name is taken at once", host_status("jooki.example.com:8090") != REFUSED and host_status("KIDS-ROOM") != REFUSED,
      (host_status("jooki.example.com:8090"), host_status("KIDS-ROOM")))
check("a name not listed is still refused", host_status("evil.example.com") == REFUSED and host_status("jooki.example.com.evil.com") == REFUSED)
n = j.mark_errors()
j.send("OJ_WEB_NAMES", {"names": ["ok.example.com", "evil.com:80"]}); j.barrier()
check("one bad name refuses the lot, the list stays", maint().get("web_names") == ["jooki.example.com", "kids-room"] and j.errors_since(n), (maint(), j.errors_since(n)))
j = B.restart(j); maint = lambda: j.maint
R.expect("the list comes back after a restart", lambda: maint().get("web_names") == ["jooki.example.com", "kids-room"], 5, maint)
check("and the name is still taken", host_status("jooki.example.com") != REFUSED, host_status("jooki.example.com"))
j.send("OJ_WEB_NAMES", {"names": []})
R.expect("an empty list forgets them", lambda: maint().get("web_names") == [], 5, maint)
check("the forgotten name is refused again", host_status("jooki.example.com") == REFUSED, host_status("jooki.example.com"))

# --- parent code gate (v1 messages and v2 commands alike) ---
j.send("PLAYLIST_NEW", {"title": "Gate test"}); j.poll(lambda: j.pl_by_title("Gate test"), 5)
pid = j.pl_by_title("Gate test")
check("a playlist exists before the code is set", pid is not None, sorted(j.pls))
r = j.v2("playlist.new", {"title": "Gate test v2"}); j.poll(lambda: j.pl_by_title("Gate test v2"), 5)
pid2 = j.pl_by_title("Gate test v2")
check("v2 creates a playlist before the code is set", pid2 is not None and r.get("ok") is True, (sorted(j.pls), r))

j.send("OJ_PARENT_SET", {"code": "1234"})
R.expect("parent code set: enabled", lambda: maint().get("parent") is True, 5, maint)

n = j.mark_errors()
j.send("OJ_WEB_NAMES", {"names": ["evil.example.com"]})
refused = j.poll(lambda: any(isinstance(e, dict) and e.get("msg") == "PARENT_CODE_REQUIRED" for e in j.errors_since(n)), 5)
check("other addresses need the parent code", refused and maint().get("web_names") == [], (refused, maint()))
j.send("OJ_WEB_NAMES", {"names": ["jooki.example.com"], "code": "1234"})
R.expect("with the code they are saved", lambda: maint().get("web_names") == ["jooki.example.com"], 5, maint)
j.send("OJ_WEB_NAMES", {"names": [], "code": "1234"})
R.expect("and forgotten", lambda: maint().get("web_names") == [], 5, maint)

n = j.mark_errors()
j.send("PLAYLIST_DELETE", {"playlistId": pid})
refused = j.poll(lambda: any(isinstance(e, dict) and e.get("msg") == "PARENT_CODE_REQUIRED" for e in j.errors_since(n)), 5)
check("delete without the code is refused", refused and pid in j.pls, (refused, pid in j.pls))

n = j.mark_errors()
j.send("DO_PLAY", {}); j.barrier()      # a refusal would have come back before the state does
check("playing music is never gated (no code required)", not any(isinstance(e, dict) and e.get("msg") == "PARENT_CODE_REQUIRED" for e in j.errors_since(n)), j.errors_since(n))

r = j.v2("playlist.delete", {"id": pid2})
check("v2: delete without the code is refused with a typed error", r.get("ok") is False and (r.get("error") or {}).get("message") == "PARENT_CODE_REQUIRED" and pid2 in j.pls, (r, pid2 in j.pls))
r = j.v2("playlist.delete", {"id": pid2}, code="0000")
check("v2: a wrong code is refused too", r.get("ok") is False and (r.get("error") or {}).get("code") == "forbidden", r)
r = j.v2("playback.pause")
check("v2: pausing is never gated", r.get("ok") is True, r)
r = j.v2("playlist.delete", {"id": pid2}, code="1234")
R.expect("v2: delete with the code works", lambda: pid2 not in j.pls and r.get("ok") is True, 5, lambda: (sorted(j.pls), r))

j.send("PLAYLIST_DELETE", {"playlistId": pid, "code": "1234"})
R.expect("delete with the code works", lambda: pid not in j.pls, 5, lambda: sorted(j.pls))

j.send("OJ_PARENT_CLEAR", {"current": "1234"})
R.expect("parent code cleared with the current code", lambda: maint().get("parent") is False, 5, maint)

j.close()
R.finish()
