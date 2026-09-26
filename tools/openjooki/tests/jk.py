"""Test client for the Jooki MQTT web protocol (bench or real device)."""
import json, time, random, threading, urllib.request, os
import paho.mqtt.client as mqtt
class Jooki:
    def __init__(s, host="127.0.0.1", port=1883, http="http://127.0.0.1:8080", transport="tcp", user=None, pw=None):
        s.host, s.http = host, http
        s.state, s.errors, s.lock = {}, [], threading.Lock()
        s.c = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, "test%d"%random.randint(0,10**6), transport=transport)
        if user: s.c.username_pw_set(user, pw)
        s.c.on_message = s._msg
        s.c.connect(host, port); s.c.subscribe("/j/web/output/#"); s.c.loop_start(); time.sleep(0.3)
        s.send("GET_STATE", {}); s.wait(lambda: "db" in s.state, 5)
    def _msg(s, c, u, m):
        try: d = json.loads(m.payload.decode())
        except Exception: d = m.payload
        with s.lock:
            if m.topic.endswith("/state") and isinstance(d, dict): s._merge(s.state, d)
            elif m.topic.endswith("/error"): s.errors.append(d)
    def _merge(s, a, b):
        for k, v in b.items():
            if k in ("db", "bedtime") or not isinstance(v, dict) or not isinstance(a.get(k), dict): a[k] = v
            else: s._merge(a[k], v)
    def send(s, typ, payload):
        s.c.publish("/j/web/input/"+typ, payload if isinstance(payload,str) else json.dumps(payload))
    def wait(s, cond, t=5):
        end = time.time()+t
        while time.time() < end:
            with s.lock:
                try:
                    if cond(): return True
                except Exception: pass
            time.sleep(0.05)
        return False
    def settle(s, t=0.6): time.sleep(t)
    def _d(s,k):
        v=s.state.get("db",{}).get(k,{})
        return v if isinstance(v,dict) else {}
    @property
    def pls(s): return s._d("playlists")
    @property
    def tracks(s): return s._d("tracks")
    @property
    def tokens(s): return s._d("tokens")
    def upload(s, path, playlistId=None):
        uid = str(random.randint(1, 9999999)); data = open(path,"rb").read(); name = os.path.basename(path)
        b = "----jk%d"%random.randint(0,1<<30)
        body = ("--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\nContent-Type: audio/mpeg\r\n\r\n"%(b,uid,name)).encode()+data+("\r\n--%s--\r\n"%b).encode()
        r = urllib.request.urlopen(urllib.request.Request(s.http+"/upload", data=body, method="POST", headers={"Content-Type":"multipart/form-data; boundary="+b}), timeout=60)
        assert r.status == 200
        p = {"uploadId": uid, "filename": name}
        if playlistId: p["playlistId"] = playlistId
        s.send("PLAYLIST_ADD_UPLOAD", p)
        return uid
    def nfc(s, tag, star_hex):
        s.c.publish("/j/nfc/input/tag", "%s,%s"%(tag, star_hex))
    def nfc_off(s): s.c.publish("/j/nfc/input/tag_removed", "")
    def close(s): s.c.loop_stop(); s.c.disconnect()
