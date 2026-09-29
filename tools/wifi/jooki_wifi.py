#!/usr/bin/env python3
"""Connect a Jooki 2 to a Wi-Fi network over Bluetooth, from a computer.

The Jooki's Wi-Fi chip offers, over Bluetooth, the same set-up the old app used at the
first start (Espressif's provisioning, protocol v1.1, no security) plus Muuselabs' list of
remembered networks. This tool speaks it. It is what https://guillain-rdcde.github.io/OpenJooki/wifi.html
does in Chrome, for people who prefer a terminal or have no Chrome.

    pip install bleak
    python3 jooki_wifi.py                      # guided: pick a network, type the password
    python3 jooki_wifi.py scan                 # the networks the Jooki can see
    python3 jooki_wifi.py connect "My box"     # asks for the password (hidden)
    python3 jooki_wifi.py connect "My box" "the password"
    python3 jooki_wifi.py status               # what the Jooki is on
    python3 jooki_wifi.py list                 # the networks it remembers
    python3 jooki_wifi.py forget "Old box"     # make it forget one

Options: --name JOOKI2_XXXXXX (when several Jookis are around), --timeout seconds.
Windows, macOS and Linux (BlueZ). Bluetooth must be on. Python 3.8+.
"""
import argparse, asyncio, getpass, sys, time

try:
    from bleak import BleakClient, BleakScanner
except ImportError:
    sys.exit("This tool needs the 'bleak' library:  pip install bleak")

PROV = "b3562d79-1a6f-6c59-368a-599ca5481a90"
WCM = "5bf49f8c-3491-218c-ae4f-db0580debd00"
CH_SCAN = "b356ff50-1a6f-6c59-368a-599ca5481a90"
CH_SESSION = "b356ff51-1a6f-6c59-368a-599ca5481a90"
CH_CONFIG = "b356ff52-1a6f-6c59-368a-599ca5481a90"
CH_VERSION = "b356ff53-1a6f-6c59-368a-599ca5481a90"
CH_REMOVE = "5bf49f8c-3491-218c-ae4f-db0580debd02"
CH_LIST = "5bf49f8c-3491-218c-ae4f-db0580debd03"
NAME_PREFIX = "JOOKI2_"
STATES = ["connected", "connecting", "disconnected", "failed"]
AUTH = ["open", "WEP", "WPA", "WPA2", "WPA/WPA2", "WPA2 enterprise", "WPA3", "WPA2/WPA3"]
LEAVES_WIFI = ("Note: while the Jooki talks to this computer it leaves its Wi-Fi, until it is given a network.")
COMES_BACK = ("The Jooki has left its Wi-Fi. It goes back to it once you give it a network (connect), or by\n"
              "itself within about 10 minutes if it is on the charger (OpenJooki 2.0.8 or later); or switch\n"
              "it off and on again.")


# ---------------------------------------------------------------- protobuf, just enough
def varint(n):
    out = b""
    while True:
        b, n = n & 0x7F, n >> 7
        if n:
            out += bytes([b | 0x80])
        else:
            return out + bytes([b])


def fv(num, v):
    return varint(num << 3) + varint(v)


def fb(num, b):
    return varint((num << 3) | 2) + varint(len(b)) + b


def _rv(b, i):
    n = s = 0
    while True:
        x = b[i]; i += 1; n |= (x & 0x7F) << s; s += 7
        if not x & 0x80:
            return n, i


def decode(buf):
    """-> {field: [values]}; varints as int (64-bit two's complement), bytes kept raw."""
    i, out = 0, {}
    while i < len(buf):
        key, i = _rv(buf, i); num, wt = key >> 3, key & 7
        if wt == 0:
            v, i = _rv(buf, i)
            if v >= 1 << 63:
                v -= 1 << 64
        elif wt == 2:
            ln, i = _rv(buf, i); v = buf[i:i + ln]; i += ln
        elif wt == 5:
            v = buf[i:i + 4]; i += 4
        elif wt == 1:
            v = buf[i:i + 8]; i += 8
        else:
            raise ValueError("wire type %d" % wt)
        out.setdefault(num, []).append(v)
    return out


def one(m, f, d=None):
    return m[f][0] if m.get(f) else d


def sub(m, f):
    v = one(m, f)
    return decode(v) if v else {}


# ---------------------------------------------------------------- the link
class Jooki:
    def __init__(self, client):
        self.c = client

    @classmethod
    async def find(cls, name=None, timeout=25.0):
        """The nearest Jooki advertising its set-up service (or the one called `name`)."""
        found = {}

        def cb(d, adv):
            n = d.name or adv.local_name or ""
            if n.startswith(NAME_PREFIX) and (name is None or n.upper() == name.upper()):
                found[d.address] = (adv.rssi or -999, d, n)

        async with BleakScanner(cb):
            t0 = time.time()
            while time.time() - t0 < timeout:
                await asyncio.sleep(0.5)
                if found and time.time() - t0 > 3:
                    break
        if not found:
            return None, None
        rssi, dev, n = sorted(found.values(), key=lambda x: -x[0])[0]
        return dev, n

    async def xfer(self, uuid, data):
        await self.c.write_gatt_char(uuid, data, response=True)
        return bytes(await self.c.read_gatt_char(uuid))

    async def session(self, on_wait=None):
        """The handshake every talker does first: proto-ver, then a security-0 session."""
        for attempt in range(6):
            try:
                # proto-ver: write "ESP", read {"prov":{"ver":"v1.1","cap":["no_sec","wifi_scan"]}}.
                # Without this first exchange the Jooki refuses the session (application error 0x85).
                ver = await self.xfer(CH_VERSION, b"ESP")
                if b"prov" not in ver:
                    raise RuntimeError("this is not a Jooki's set-up service (%r)" % ver[:60])
                # security 0: SessionData{ sec0{ sc{} } } -> sec0{ sr{ status } }
                r = decode(await self.xfer(CH_SESSION, fb(10, fb(20, b""))))
                break
            except Exception as e:
                if ("0x85" not in str(e) and "Application" not in str(e)) or attempt == 5:
                    raise
                if on_wait:
                    on_wait(attempt)
                await asyncio.sleep(2.5)
        if one(sub(sub(r, 10), 21), 1, 0) != 0:
            raise RuntimeError("the Jooki refused the session")

    async def scan(self):
        """The networks the Jooki can see: [{ssid, rssi, channel, auth}], strongest first, one per name."""
        await self.xfer(CH_SCAN, fb(10, fv(1, 1) + fv(4, 120)))            # CmdScanStart{blocking, period_ms}
        st = {}
        for _ in range(40):
            st = sub(decode(await self.xfer(CH_SCAN, fv(1, 2) + fb(12, b""))), 13)
            if one(st, 1, 0):
                break
            await asyncio.sleep(0.4)
        n, got, seen = one(st, 2, 0), 0, {}
        while got < n:
            k = min(4, n - got)
            r = sub(decode(await self.xfer(CH_SCAN, fv(1, 4) + fb(14, fv(1, got) + fv(2, k)))), 15)
            for raw in r.get(1, []):
                e = decode(raw)
                ssid = one(e, 1, b"").decode("utf-8", "replace")
                if not ssid:
                    continue
                net = {"ssid": ssid, "rssi": one(e, 3, -100), "channel": one(e, 2, 0), "auth": one(e, 5, 0)}
                if ssid not in seen or seen[ssid]["rssi"] < net["rssi"]:
                    seen[ssid] = net
            got += k
        return sorted(seen.values(), key=lambda x: -x["rssi"])

    async def known(self):
        """The networks the Jooki remembers (Muuselabs' list: "a","b")."""
        txt = bytes(await self.c.read_gatt_char(CH_LIST)).decode("utf-8", "replace")
        out, i = [], 0
        while True:
            a = txt.find('"', i)
            if a < 0:
                return out
            j, s = a + 1, ""
            while j < len(txt) and txt[j] != '"':
                if txt[j] == "\\" and j + 1 < len(txt):
                    j += 1
                s += txt[j]; j += 1
            out.append(s); i = j + 1

    async def forget(self, ssid):
        quoted = '"' + ssid.replace("\\", "\\\\").replace('"', '\\"') + '"'
        await self.c.write_gatt_char(CH_REMOVE, quoted.encode("utf-8"), response=True)

    async def status(self):
        s = sub(decode(await self.xfer(CH_CONFIG, fb(10, b""))), 11)   # CmdGetStatus -> RespGetStatus
        c = sub(s, 11)
        st = one(s, 2, 0)
        return {"state": STATES[st] if st < 4 else "unknown", "reason": one(s, 10),
                "ssid": c[3][0].decode("utf-8", "replace") if c.get(3) else None}

    async def connect(self, ssid, password, on_step=None, timeout=45.0):
        """Give the Jooki a network and wait until it is on it. -> status dict (state connected/failed/timeout)."""
        r = sub(decode(await self.xfer(CH_CONFIG, fv(1, 2) + fb(12, fb(1, ssid.encode()) + fb(2, password.encode())))), 13)
        if one(r, 1, 0) != 0:
            raise RuntimeError("the Jooki refused the network")
        r = sub(decode(await self.xfer(CH_CONFIG, fv(1, 4) + fb(14, b""))), 15)
        if one(r, 1, 0) != 0:
            raise RuntimeError("the Jooki refused to apply it")
        # The status is the chip's last event: a failure is believed only once the attempt has had
        # time to run (3 s) and it is reported twice in a row, so a stale answer never ends a real attempt.
        t0, failures, errors = time.time(), 0, 0
        st = {"state": "connecting", "reason": None, "ssid": None}
        while time.time() - t0 < timeout:
            await asyncio.sleep(1.5)
            try:                      # a read can fail while the chip switches network: not the verdict
                st = await self.status(); errors = 0
            except Exception:
                errors += 1
                if errors >= 6:
                    raise
                continue
            if on_step:
                on_step(int(time.time() - t0), st)
            if st["state"] == "connected" and st["ssid"] == ssid:
                return st
            failures = failures + 1 if st["state"] == "failed" else 0
            if failures >= 2 and time.time() - t0 >= 3:
                return st
        st["state"] = "timeout"
        return st


# ---------------------------------------------------------------- the command line
def signal_words(rssi):
    return "good" if rssi >= -65 else "fair" if rssi >= -75 else "weak"


def say_result(st, ssid):
    if st["state"] == "connected":
        print('\nDone: the Jooki is on "%s".' % ssid)
        print("From a phone or computer on that Wi-Fi, open http://jooki.local (with the http://),")
        print("or the address your box shows for it. The Jooki remembers this network from now on.")
        return 0
    if st["state"] == "failed":
        why = {0: "the Jooki says the password is wrong (capitals, spaces and symbols count); it stays off Wi-Fi until you try again",
               1: "the Jooki cannot find that network (too far, or 5 GHz only: it needs 2.4 GHz)"}.get(st["reason"], "the Jooki could not join it")
        print("\nNot connected: %s." % why)
    elif st["state"] == "timeout":
        print("\nThe Jooki could not join it in 45 seconds. Most often the password is wrong (capitals, spaces")
        print("and symbols count), or the network is out of reach or 5 GHz only. It stays off Wi-Fi until it joins one: try again.")
    else:
        print("\nNot connected (%s)." % st["state"])
    return 1


async def run(a):
    if a.cmd == "connect" and a.ssid and a.password is None:
        a.password = getpass.getpass('Password for "%s" (typing is hidden): ' % a.ssid)
    print("Looking for a Jooki over Bluetooth…", end=" ", flush=True)
    try:
        dev, name = await Jooki.find(a.name, a.timeout)
    except Exception as e:      # no adapter, Bluetooth off, BlueZ not running…
        print("\nBluetooth is not available on this computer: %s" % e)
        print("Turn Bluetooth on (or plug an adapter in) and try again.")
        return 2
    if not dev:
        print("none found.")
        print("Put the Jooki next to the computer, switched on, and try again. It shows up as JOOKI2_… while it is on.")
        return 2
    print("found %s." % name)
    async with BleakClient(dev, timeout=30) as c:
        j = Jooki(c)
        # The list and "forget" are Muuselabs' own endpoints: no set-up session needed, and none is
        # opened, because opening one makes the Wi-Fi chip leave its network until it is given one
        # (seen on a Jooki on 29/09/2026: one "list" with a session left it offline for good).
        if a.cmd == "list":
            k = await j.known()
            print("The Jooki remembers: %s" % (", ".join('"%s"' % s for s in k) if k else "no network"))
            return 0
        if a.cmd != "forget":
            print(LEAVES_WIFI, flush=True)
            await j.session(lambda n: print("  the Jooki did not answer the handshake, trying again…", flush=True))
        if a.cmd == "status":
            st = await j.status()
            print("Wi-Fi: %s%s" % (st["state"], (' to "%s"' % st["ssid"]) if st["ssid"] else ""))
            print(COMES_BACK)
            return 0
        if a.cmd == "forget":
            k = await j.known()
            if a.ssid not in k:
                print('The Jooki does not remember "%s" (it remembers: %s).' % (a.ssid, ", ".join(k) or "nothing"))
                return 1
            await j.forget(a.ssid)
            k = await j.known()
            print(('Forgotten "%s". ' % a.ssid if a.ssid not in k else 'Still there: "%s". ' % a.ssid) + "It now remembers: %s" % (", ".join(k) or "nothing"))
            return 0 if a.ssid not in k else 1
        if a.cmd in ("scan", None):
            print("Asking the Jooki which networks it can see…", flush=True)
            nets = await j.scan()
            if not nets:
                print("It sees no 2.4 GHz network from here. Bring it closer to the box.")
            for i, n in enumerate(nets, 1):
                print("  %2d. %-32s %-4s (%d dBm, ch %d, %s)" % (i, n["ssid"], signal_words(n["rssi"]), n["rssi"], n["channel"], AUTH[n["auth"]] if n["auth"] < len(AUTH) else "?"))
            k = await j.known()
            print("It remembers: %s" % (", ".join('"%s"' % s for s in k) if k else "no network"))
            if a.cmd == "scan":
                print(COMES_BACK)
                return 0
            # guided
            choice = input("\nWhich network? (number, or type a hidden network's name; empty = quit) ").strip()
            if not choice:
                print(COMES_BACK)
                return 0
            if choice.isdigit() and 1 <= int(choice) <= len(nets):
                net = nets[int(choice) - 1]; ssid = net["ssid"]
            else:
                net = None; ssid = choice
            pw = "" if (net and net["auth"] == 0) else getpass.getpass('Password for "%s" (typing is hidden): ' % ssid)
            a.ssid, a.password = ssid, pw
        # connect
        if a.password and len(a.password) < 8:
            print("A Wi-Fi password has at least 8 characters.")
            return 1
        print('Sending "%s" to the Jooki…' % a.ssid, flush=True)

        def step(secs, st):
            print("  %2d s: %s" % (secs, st["state"]), flush=True)
        st = await j.connect(a.ssid, a.password or "", step)
        return say_result(st, a.ssid)


def main():
    ap = argparse.ArgumentParser(description="Connect a Jooki 2 to Wi-Fi over Bluetooth.")
    ap.add_argument("cmd", nargs="?", choices=["scan", "connect", "status", "list", "forget"], help="what to do (none = guided)")
    ap.add_argument("ssid", nargs="?", help="network name (connect, forget)")
    ap.add_argument("password", nargs="?", help="password (connect); asked if omitted")
    ap.add_argument("--name", help="the Jooki to talk to, e.g. JOOKI2_0426E8 (default: the nearest)")
    ap.add_argument("--timeout", type=float, default=25, help="seconds to look for the Jooki (25: it can take a while to show up again after a previous talker)")
    a = ap.parse_args()
    if a.cmd in ("connect", "forget") and not a.ssid:
        ap.error("%s needs the network name" % a.cmd)
    try:
        sys.exit(asyncio.run(run(a)))
    except KeyboardInterrupt:
        sys.exit(130)


if __name__ == "__main__":
    main()
