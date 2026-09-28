"""Security checks on the bench (docs/adr/0007-security-model): the broker's
WebSocket (8000) needs the per-Jooki password; local clients stay anonymous on
1883; the page reads the password at its own origin only.  python3 test_security.py

Run after e2e.py: it relies on the page files (oj-auth.json) being deployed and
symlinked into what web_ctrl serves, which start_player.sh / the core do."""
import sys, time, json, urllib.request
import paho.mqtt.client as mqtt

R = []
def check(n, c, info=""):
    R.append((n, bool(c))); print(("PASS " if c else "FAIL ") + n + ("" if c else "  -> " + str(info)[:300]))

def _client(transport):
    try:
        return mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, transport=transport)
    except Exception:
        return mqtt.Client(transport=transport)   # paho 1.x

def try_connect(transport, port, user=None, pw=None, path="/mqtt", timeout=6):
    """Return (connected_bool, reason)."""
    got = {}
    c = _client(transport)
    if transport == "websockets":
        c.ws_set_options(path=path)
    if user is not None:
        c.username_pw_set(user, pw)
    def on_connect(cl, u, flags, reason_code, props=None):
        got["rc"] = int(getattr(reason_code, "value", reason_code)); got["done"] = True
    c.on_connect = on_connect
    try:
        c.connect("127.0.0.1", port, 10); c.loop_start()
    except Exception as e:
        return False, "connect error: " + str(e)
    end = time.time() + timeout
    while time.time() < end and not got.get("done"):
        time.sleep(0.05)
    connected = got.get("rc") == 0
    try: c.loop_stop(); c.disconnect()
    except Exception: pass
    return connected, got.get("rc", "timeout")

ok, rc = try_connect("websockets", 8000)
check("S1 WebSocket 8000 refuses an anonymous page", not ok, rc)
ok, rc = try_connect("websockets", 8000, "jooki", "benchsecret")
check("S2 WebSocket 8000 accepts the per-Jooki password", ok, rc)
ok, rc = try_connect("websockets", 8000, "jooki", "wrong")
check("S3 WebSocket 8000 refuses a wrong password", not ok, rc)
ok, rc = try_connect("tcp", 1883)
check("S4 local 1883 stays anonymous for the core and the closed daemons", ok, rc)

try:
    with urllib.request.urlopen("http://127.0.0.1:8080/oj-auth.json", timeout=5) as r:
        hdr = r.headers.get("Access-Control-Allow-Origin")
        body = json.loads(r.read().decode())
except Exception as e:
    hdr, body = "ERROR", {"err": str(e)}
check("S5 oj-auth.json has no Access-Control-Allow-Origin (a website cannot read it)", hdr is None, hdr)
check("S5 oj-auth.json carries the WebSocket password for the same-origin page", body.get("mqttPass") == "benchsecret", body)

bad = [n for n, ok in R if not ok]
print("\n%d/%d passed" % (len(R) - len(bad), len(R))); sys.exit(1 if bad else 0)
