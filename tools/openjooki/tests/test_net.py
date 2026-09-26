"""Network-health tests on the bench: the real Jooki program (patched).
Log cleanup at boot, Wi-Fi state published for the page, "<hostname>.local" answered.  python3 test_net.py"""
import os, socket, struct, subprocess, sys, time
from jk import Jooki
LUA = os.environ.get("PLAYER_LUA", "player.patched.lua")
LD = "/jooki/external/logs/syslog-ng"
R = []
def check(n, c, info=""):
    R.append((n, bool(c))); print(("PASS " if c else "FAIL ") + n + ("" if c else "  -> " + str(info)[:300]))

def query(name, qtype=1, port=5353):
    """Legacy unicast mDNS query (source port != 5353): the answer comes back to us."""
    q = b"".join(bytes([len(p)]) + p.encode() for p in name.split(".")) + b"\0" + struct.pack("!HH", qtype, 1)
    pkt = struct.pack("!HHHHHH", 0x1234, 0, 1, 0, 0, 0) + q
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(2)
    s.sendto(pkt, ("127.0.0.1", port))
    try: data = s.recv(512)
    except socket.timeout: return None
    finally: s.close()
    return data

subprocess.run(["bash", "setup.sh"], capture_output=True)
os.makedirs(LD, exist_ok=True)
open(LD + "/syslog-ng.log", "w").write("".join("old line %d\n" % i for i in range(5000)))
open(LD + "/syslog-ng-00000.qf", "wb").write(b"x" * 100000)      # logs queued for Papertrail
open("/tmp/oj-wifi.log", "w").write(
    "Sep 26 11:22:44 j esp_tty[1]: I (1) wifi:connected with Salon, aid = 1, channel 8, BW20, bssid = 02:00:00:00:00:01\n"
    "Sep 26 11:30:00 j esp_tty[1]: I (2) wifi:bcn_timout,ap_probe_send_start\n"
    "Sep 26 11:30:04 j esp_tty[1]: I (3) wifi:state: run -> init (c800)\n"
    "Sep 26 11:30:09 j esp_tty[1]: I (4) wifi:connected with Box, aid = 2, channel 1, BW20, bssid = 02:00:00:00:00:02\n")
subprocess.run(["./start_player.sh", LUA], capture_output=True); time.sleep(2)
j = Jooki()
check("N1 Papertrail queue removed at boot", not os.path.exists(LD + "/syslog-ng-00000.qf"))
old = open(LD + "/syslog-ng.old.log").read().splitlines() if os.path.exists(LD + "/syslog-ng.old.log") else []
check("N1 old log kept short (last 3000 lines), big file removed", len(old) == 3000 and old[-1] == "old line 4999" and not os.path.exists(LD + "/syslog-ng.log"), len(old))
net = j.state.get("net", {})
check("N2 Wi-Fi state for the page: access point, drops, beacon losses", net.get("ap") == "Box" and net.get("drops") == 1 and net.get("beacons") == 1, net)
with open("/tmp/oj-wifi.log", "a") as f:
    f.write("Sep 26 12:00:00 j esp_tty[1]: I (5) wifi:state: run -> init (c800)\n"
            "Sep 26 12:00:05 j esp_tty[1]: I (6) wifi:connected with Salon, aid = 1, channel 8, BW20, bssid = 02:00:00:00:00:01\n")
j.wait(lambda: j.state.get("net", {}).get("drops") == 2, 25)
net = j.state.get("net", {})
check("N2 updated when the Wi-Fi changes", net.get("ap") == "Salon" and net.get("drops") == 2, net)
# the Wi-Fi chip may stay connected across a reboot (no event in the log): the name comes from its status
os.remove("/tmp/oj-wifi.log")
j.c.publish("/j/esp32/input/net/sta/config", '{"ssid":"Box","signal":-80,"stat":"success","ip":"10.0.0.2"}')
j.wait(lambda: j.state.get("net", {}).get("ap") == "Box", 25)
check("N2 access point known without any log event", j.state.get("net", {}).get("ap") == "Box", j.state.get("net"))
d = query("jooki-bench.local")
ok = d and struct.unpack("!H", d[:2])[0] == 0x1234 and struct.unpack("!H", d[6:8])[0] == 1 and d[-4:] == socket.inet_aton("10.0.0.2")
check("N3 '<hostname>.local' answered with the Jooki's address", ok, d)
check("N3 name shown to the page", j.state.get("net", {}).get("name") == "jooki-bench.local", j.state.get("net"))
d = query("JOOKI-BENCH.local")
check("N3 any case", d and d[-4:] == socket.inet_aton("10.0.0.2"), d)
check("N3 other names ignored ('jooki.local' would hit web_ctrl's dead redirect)", query("printer.local") is None and query("jooki.local") is None)
d = query("jooki-bench.local", qtype=28)
check("N3 IPv6 query: 'IPv4 only' (NSEC) answer, no waiting", d is not None and (bytes([0, 47, 0, 1]) in d or bytes([0, 47, 128, 1]) in d) and d.endswith(bytes([0, 1, 64])), d)
check("N3 other record types ignored", query("jooki-bench.local", qtype=16) is None)
# garbage on the mDNS port never hurts the player
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
for p in (b"", b"\x00" * 5, b"\xff" * 40, b"\x12\x34\x00\x00\x00\x05" + b"\x00" * 6 + b"\x3fabc"):
    s.sendto(p, ("127.0.0.1", 5353))
s.close(); time.sleep(1)
j.send("GET_STATE", {}); time.sleep(0.5)
check("N4 malformed mDNS packets: player still answers", query("jooki-bench.local") is not None and "db" in j.state)
log = open("/tmp/player.log").read()
check("N5 no error in the network code", "OJ_TICK" not in log and "ERR_HANDLER" not in log, [l for l in log.splitlines() if "OJ_TICK" in l][:3])
j.close()
bad = [n for n, ok in R if not ok]
print("\n%d/%d passed" % (len(R) - len(bad), len(R))); sys.exit(1 if bad else 0)
