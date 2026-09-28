"""Security switches over the bus, against the real core (docs/adr/0007):
SSH one-hour toggle, MQTT-on-the-LAN toggle, and the parent-code gate.
  python3 test_security_backend.py"""
import os, subprocess, sys, time
from jk import Jooki
LUA = os.environ.get("PLAYER_LUA", "player.patched.lua")
R = []
def check(n, c, info=""):
    R.append((n, bool(c))); print(("PASS " if c else "FAIL ") + n + ("" if c else "  -> " + str(info)[:300]))

subprocess.run(["bash", "setup.sh"], capture_output=True)
os.makedirs("/data/openjooki", exist_ok=True)
# start from no parent code
try: os.remove("/data/openjooki/parent_code")
except OSError: pass
subprocess.run(["./start_player.sh", LUA], capture_output=True); time.sleep(2)
j = Jooki()

def maint(): return j.state.get("maintenance", {}) if isinstance(j.state.get("maintenance"), dict) else {}

# --- SSH one-hour toggle ---
j.send("OJ_SSH_ON", {}); j.wait(lambda: maint().get("ssh") is True, 5)
check("SSH on: state reflects it, with an end time", maint().get("ssh") is True and isinstance(maint().get("ssh_until"), (int, float)), maint())
j.send("OJ_SSH_OFF", {}); j.wait(lambda: maint().get("ssh") is False, 5)
# (the core drops ssh_until; the test client's recursive merge keeps stale keys, so we only check ssh)
check("SSH off", maint().get("ssh") is False, maint())

# --- MQTT on the LAN toggle ---
j.send("OJ_MQTT_LAN", {"on": True}); j.wait(lambda: maint().get("mqtt_lan") is True, 5)
check("MQTT on the LAN: on", maint().get("mqtt_lan") is True, maint())
j.send("OJ_MQTT_LAN", {"on": False}); j.wait(lambda: maint().get("mqtt_lan") is False, 5)
check("MQTT on the LAN: off", maint().get("mqtt_lan") is False, maint())

# --- parent code gate ---
j.send("PLAYLIST_NEW", {"title": "Gate test"}); j.wait(lambda: any(v.get("title") == "Gate test" for v in j.pls.values()), 5)
pid = next((k for k, v in j.pls.items() if v.get("title") == "Gate test"), None)
check("a playlist exists before the code is set", pid is not None, sorted(j.pls))

j.send("OJ_PARENT_SET", {"code": "1234"}); j.wait(lambda: maint().get("parent") is True, 5)
check("parent code set: enabled", maint().get("parent") is True, maint())

j.errors[:] = []
j.send("PLAYLIST_DELETE", {"playlistId": pid}); time.sleep(1)
refused = any(isinstance(e, dict) and e.get("msg") == "PARENT_CODE_REQUIRED" for e in j.errors)
check("delete without the code is refused", refused and pid in j.pls, (refused, pid in j.pls))

j.errors[:] = []
j.send("DO_PLAY", {}); time.sleep(0.8)
check("playing music is never gated (no code required)", not any(isinstance(e, dict) and e.get("msg") == "PARENT_CODE_REQUIRED" for e in j.errors), j.errors)

j.send("PLAYLIST_DELETE", {"playlistId": pid, "code": "1234"}); j.wait(lambda: pid not in j.pls, 5)
check("delete with the code works", pid not in j.pls, sorted(j.pls))

j.send("OJ_PARENT_CLEAR", {"current": "1234"}); j.wait(lambda: maint().get("parent") is False, 5)
check("parent code cleared with the current code", maint().get("parent") is False, maint())

j.close()
bad = [n for n, ok in R if not ok]
print("\n%d/%d passed" % (len(R) - len(bad), len(R))); sys.exit(1 if bad else 0)
