"""Network-health tests on the bench: the real Jooki program (patched).
Log cleanup at boot, Wi-Fi state published for the page, "<hostname>.local" answered.  python3 test_net.py"""
import os, socket, struct
import bench as B
LD = "/jooki/external/logs/syslog-ng"
R = B.Results(); check = R.check

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

def pre():   # what the core finds at boot: a big syslog, a Papertrail queue, the Wi-Fi chip's log
    os.makedirs(LD, exist_ok=True)
    open(LD + "/syslog-ng.log", "w").write("".join("old line %d\n" % i for i in range(5000)))
    open(LD + "/syslog-ng-00000.qf", "wb").write(b"x" * 100000)      # logs queued for Papertrail
    open("/tmp/oj-wifi.log", "w").write(
        "Sep 26 11:22:44 j esp_tty[1]: I (1) wifi:connected with Salon, aid = 1, channel 8, BW20, bssid = 02:00:00:00:00:01\n"
        "Sep 26 11:30:00 j esp_tty[1]: I (2) wifi:bcn_timout,ap_probe_send_start\n"
        "Sep 26 11:30:04 j esp_tty[1]: I (3) wifi:state: run -> init (c800)\n"
        "Sep 26 11:30:09 j esp_tty[1]: I (4) wifi:connected with Box, aid = 2, channel 1, BW20, bssid = 02:00:00:00:00:02\n")
j = B.boot(pre=pre)
check("N1 Papertrail queue removed at boot", not os.path.exists(LD + "/syslog-ng-00000.qf"))
old = open(LD + "/syslog-ng.old.log").read().splitlines() if os.path.exists(LD + "/syslog-ng.old.log") else []
check("N1 old log kept short (last 3000 lines), big file removed", len(old) == 3000 and old[-1] == "old line 4999" and not os.path.exists(LD + "/syslog-ng.log"), len(old))
R.expect("N2 Wi-Fi state for the page: access point, drops, beacon losses",
         lambda: j.get("net.ap") == "Box" and j.get("net.drops") == 1 and j.get("net.beacons") == 1, 10, lambda: j.get("net"))
with open("/tmp/oj-wifi.log", "a") as f:
    f.write("Sep 26 12:00:00 j esp_tty[1]: I (5) wifi:state: run -> init (c800)\n"
            "Sep 26 12:00:05 j esp_tty[1]: I (6) wifi:connected with Salon, aid = 1, channel 8, BW20, bssid = 02:00:00:00:00:01\n")
R.expect("N2 updated when the Wi-Fi changes", lambda: j.get("net.ap") == "Salon" and j.get("net.drops") == 2, 25, lambda: j.get("net"))
# the Wi-Fi chip may stay connected across a reboot (no event in the log): the name comes from its status
os.remove("/tmp/oj-wifi.log")
j.c.publish("/j/esp32/input/net/sta/config", '{"ssid":"Box","signal":-80,"stat":"success","ip":"10.0.0.2"}')
R.expect("N2 access point known without any log event", lambda: j.get("net.ap") == "Box", 25, lambda: j.get("net"))
d = query("jooki-bench.local")
ok = d and struct.unpack("!H", d[:2])[0] == 0x1234 and struct.unpack("!H", d[6:8])[0] == 1 and d[-4:] == socket.inet_aton("10.0.0.2")
check("N3 '<hostname>.local' answered with the Jooki's address", ok, d)
check("N3 name shown to the page", j.get("net.name") == "jooki-bench.local", j.get("net"))
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
s.close(); B.quiet(1, "the garbage must have been read (and survived) before the player is asked again")
check("N4 malformed mDNS packets: player still answers", query("jooki-bench.local") is not None and j.alive())
B.check_clean_log(R, "N5 no error in the network code")
j.close()
R.finish()
