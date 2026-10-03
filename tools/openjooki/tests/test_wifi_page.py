"""The Wi-Fi page (docs/wifi.html) against a scripted Jooki: a fake navigator.bluetooth that
answers the Espressif provisioning protocol with the bytes a real Jooki sent on 28/09/2026.
Needs Playwright's Chromium only (no Bluetooth, no Jooki).      python3 test_wifi_page.py

Covers: no Web Bluetooth, find + scan (sorted, one per name, open network, empty name dropped),
remembered networks, password guard, good password, wrong password (chip says AuthError), network
not found, chip silent (timeout), a Bluetooth read failing once, the handshake before every set-up,
forget (confirmed / cancelled), Bluetooth off."""
import os, threading, http.server, functools
from playwright.sync_api import sync_playwright
import bench as B

DOCS = os.path.join(B.REPO, "docs")
R = B.Results(); check = R.check

MOCK = r"""
(function () {
  var enc = new TextEncoder(), dec = new TextDecoder();
  var PROV = 'b3562d79-1a6f-6c59-368a-599ca5481a90', WCM = '5bf49f8c-3491-218c-ae4f-db0580debd00';
  var J = window.__jooki = {
    name: 'JOOKI2_TEST01', password: 'goodpassword', failMode: 'auth', dropOnce: false,
    known: ['Old box', 'Home'],
    nets: [{ssid: 'Home', rssi: -80, ch: 6, auth: 3}, {ssid: 'Cafe', rssi: -70, ch: 1, auth: 0}, {ssid: '', rssi: -40, ch: 1, auth: 3},
           {ssid: 'Home', rssi: -50, ch: 6, auth: 3}, {ssid: 'Far', rssi: -85, ch: 11, auth: 3}],
    session: false, sessions: 0, attempts: [], polls: 0, state: 1, reason: null, connected: null, log: []
  };
  function varint(n) { var out = []; do { var b = n % 128; n = Math.floor(n / 128); out.push(n ? b | 0x80 : b); } while (n); return out; }
  function fv(num, v) { return varint(num * 8).concat(varint(v)); }
  function fneg(num, v) { var big = BigInt.asUintN(64, BigInt(v)), out = []; do { var b = Number(big & 0x7fn); big >>= 7n; out.push(big ? b | 0x80 : b); } while (big); return varint(num * 8).concat(out); }
  function fb(num, bytes) { bytes = Array.from(bytes); return varint(num * 8 + 2).concat(varint(bytes.length), bytes); }
  function rv(b, i) { var n = 0n, s = 0n, x; do { x = b[i++]; n |= BigInt(x & 0x7f) << s; s += 7n; } while (x & 0x80); return [Number(n), i]; }
  function decode(b) { var i = 0, out = {}, r, key, num, wt, v, ln; while (i < b.length) { r = rv(b, i); key = r[0]; i = r[1]; num = key >> 3; wt = key & 7;
    if (wt === 0) { r = rv(b, i); v = r[0]; i = r[1]; } else if (wt === 2) { r = rv(b, i); ln = r[0]; i = r[1]; v = b.slice(i, i + ln); i += ln; } else throw new Error('wt'); (out[num] = out[num] || []).push(v); } return out; }
  function one(m, f, d) { return m && m[f] && m[f].length ? m[f][0] : d; }
  function err(name, msg) { var e = new Error(msg); e.name = name; return e; }
  function handle(uuid, buf) {   // -> the bytes the next read returns
    var m, short = uuid.slice(4, 8);
    if (uuid === PROV.replace('b3562d79', 'b356ff53')) return enc.encode('{"prov":{"ver":"v1.1","cap":["no_sec","wifi_scan"]}}');
    if (short === 'ff51') { J.session = true; J.sessions++; return [0x52, 0x05, 0x08, 0x01, 0xaa, 0x01, 0x00]; }
    if (short === 'ff50') {
      m = decode(buf); var msg = one(m, 1, 0);
      if (msg === 0) return [0x08, 0x01, 0x5a, 0x00];
      if (msg === 2) return fv(1, 3).concat(fb(13, fv(1, 1).concat(fv(2, J.nets.length))));
      if (msg === 4) { var q = decode(one(m, 14)), start = one(q, 1, 0), count = one(q, 2, 0), entries = [];
        J.nets.slice(start, start + count).forEach(function (n) { entries = entries.concat(fb(1, fb(1, enc.encode(n.ssid)).concat(fv(2, n.ch), fneg(3, n.rssi), fb(4, [1, 2, 3, 4, 5, 6]), fv(5, n.auth)))); });
        return fv(1, 5).concat(fb(15, entries)); }
    }
    if (short === 'ff52') {
      m = decode(buf); var t = one(m, 1, 0);
      if (t === 2) { if (!J.session) return fv(1, 3).concat(fb(13, fv(1, 7)));    // InvalidSession
        var c = decode(one(m, 12)); J.pending = { ssid: dec.decode(one(c, 1, new Uint8Array(0))), pw: dec.decode(one(c, 2, new Uint8Array(0))) }; return fv(1, 3).concat(fb(13, [])); }
      if (t === 4) { if (!J.session || !J.pending) return fv(1, 5).concat(fb(15, fv(1, 7)));
        J.attempts.push(J.pending); J.session = false; J.state = 1; J.reason = null; J.connected = null; J.polls = 0; J.armed = J.pending; J.pending = null; return fv(1, 5).concat(fb(15, [])); }
      if (t === 0) { J.polls++;
        if (J.armed && J.polls >= 3) { var a = J.armed; J.armed = null;
          if (a.pw === J.password && J.nets.some(function (n) { return n.ssid === a.ssid; })) { J.state = 0; J.connected = a.ssid; if (J.known.indexOf(a.ssid) < 0) J.known.push(a.ssid); }
          else if (J.failMode === 'auth') { J.state = 3; J.reason = 0; }
          else if (J.failMode === 'notfound') { J.state = 3; J.reason = 1; }
          else { J.state = 1; } }
        var s = fv(2, J.state); if (J.reason !== null) s = s.concat(fv(10, J.reason));
        if (J.state === 0) s = s.concat(fb(11, fb(1, enc.encode('255.255.63.179')).concat(fv(2, 3), fb(3, enc.encode(J.connected)), fb(4, [1, 2, 3, 4, 5, 6]), fv(5, 8))));
        return fv(1, 1).concat(fb(11, s)); }
    }
    throw err('NotSupportedError', 'GATT operation failed for unknown reason.');
  }
  function chr(uuid) {
    var last = null;
    return { uuid: uuid,
      writeValueWithResponse: async function (buf) {
        buf = new Uint8Array(buf.buffer || buf); J.log.push(uuid.slice(4, 8) + '>' + buf.length);
        if (uuid.slice(-3) === 'd02') { var s = dec.decode(buf), mm = /^"(.*)"$/.exec(s); if (!mm || J.known.indexOf(mm[1]) < 0) throw err('NotSupportedError', 'GATT Protocol Error: Application-specific Error 0x85'); J.known.splice(J.known.indexOf(mm[1]), 1); return; }
        last = handle(uuid, buf); },
      readValue: async function () {
        if (uuid.slice(-3) === 'd03') return new DataView(enc.encode(J.known.map(function (s) { return '"' + s + '"'; }).join(',')).buffer);
        if (J.dropOnce && uuid.slice(4, 8) === 'ff52' && J.polls === 1) { J.dropOnce = false; throw err('NetworkError', 'GATT Server is disconnected.'); }
        if (!last) throw err('NotSupportedError', 'GATT operation failed for unknown reason.');
        var v = new Uint8Array(last); last = null; return new DataView(v.buffer); } };
  }
  var device = { name: J.name, addEventListener: function () {}, gatt: { connected: false,
    connect: async function () { this.connected = true; return { getPrimaryService: async function (u) { if (u !== PROV && u !== WCM) throw err('NotFoundError', 'no such service'); return { getCharacteristic: async function (c) { return chr(c); } }; } }; },
    disconnect: function () { this.connected = false; } } };
  var bt = { available: true,
    getAvailability: async function () { return bt.available; },
    requestDevice: async function (opts) { J.request = opts; if (J.cancel) throw err('NotFoundError', 'User cancelled the requestDevice() chooser.'); return device; } };
  Object.defineProperty(navigator, 'bluetooth', { value: bt, configurable: true });   // over the real one, if any
})();
"""

srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(http.server.SimpleHTTPRequestHandler, directory=DOCS))
srv.RequestHandlerClass.log_message = lambda *a, **k: None
threading.Thread(target=srv.serve_forever, daemon=True).start()
URL = "http://127.0.0.1:%d/wifi.html" % srv.server_address[1]

with sync_playwright() as p:
    b = p.chromium.launch()
    # W0: a browser without Web Bluetooth (Playwright's headless shell has none)
    pg0 = b.new_page(); pg0.add_init_script("Object.defineProperty(navigator, 'bluetooth', {value: undefined, configurable: true})"); pg0.goto(URL)
    check("W0 without Web Bluetooth the page says which browsers to use and disables the button",
          pg0.locator("#nobt").is_visible() and pg0.locator("#find").is_disabled() and "Chrome" in pg0.locator("#nobt").inner_text(),
          (pg0.evaluate("typeof navigator.bluetooth"), pg0.locator("#nobt").is_visible(), pg0.locator("#find").is_disabled()))
    pg0.close()

    ctx = b.new_context(viewport={"width": 420, "height": 900}, is_mobile=True, has_touch=True)
    ctx.add_init_script(MOCK); ctx.add_init_script("window.OJ_TIMEOUT = 6000;")
    pg = ctx.new_page(); errs = []; dialogs = []
    pg.on("pageerror", lambda e: errs.append("PAGEERROR " + str(e)))
    pg.on("console", lambda m: errs.append(m.text) if m.type == "error" and "favicon" not in m.text else None)
    accept = {"v": True}
    def on_dialog(d): dialogs.append(d.message); d.accept() if accept["v"] else d.dismiss()
    pg.on("dialog", on_dialog)
    pg.goto(URL)
    check("W1 with Web Bluetooth the button is offered", pg.locator("#find").is_enabled() and pg.locator("#nobt").is_hidden())
    pg.click("#find")
    # first what the Jooki remembers, with no set-up session: a Jooki on its Wi-Fi stays on it (29/09/2026)
    pg.wait_for_selector("[data-forget]")
    check("W14 finding the Jooki shows what it remembers and opens no set-up session (it stays on its Wi-Fi)",
          pg.evaluate("window.__jooki.sessions") == 0 and pg.locator("#scanbtn").is_visible() and pg.locator(".net[data-ssid]").count() == 0,
          (pg.evaluate("window.__jooki.sessions"), pg.locator("#scanbtn").is_visible()))
    check("W14 ... and says that looking for networks takes it off its Wi-Fi until it gets one",
          "leaves its Wi-Fi" in pg.locator("#scanwarn").inner_text() and "ten minutes" in pg.locator("#scanwarn").inner_text())
    check("W14 the remembered list says the Jooki does not pick the strongest network (keep only the near one)",
          "does not pick the strongest" in pg.locator("#knownbox").inner_text())
    pg.click("#scanbtn")
    try: pg.wait_for_selector(".net[data-ssid]")
    except Exception:
        print("W1 the page never listed the networks\n  err:", pg.locator("#etitle").inner_text(), "/", pg.locator("#etext").inner_text(), "\n  console:", errs, "\n  mock log:", pg.evaluate("window.__jooki.log"), flush=True); raise
    req = pg.evaluate("window.__jooki.request")
    check("W1 the chooser is asked for JOOKI2_ names and both services", req["filters"][0]["namePrefix"] == "JOOKI2_" and set(req["optionalServices"]) == {"b3562d79-1a6f-6c59-368a-599ca5481a90", "5bf49f8c-3491-218c-ae4f-db0580debd00"}, req)
    names = pg.locator(".net[data-ssid]").evaluate_all("els => els.map(e => e.getAttribute('data-ssid'))")
    check("W1 networks: strongest first, one per name, empty name dropped", names == ["Home", "Cafe", "Far"], names)
    sig = pg.locator(".net[data-ssid='Home'] .sig").inner_text()
    check("W1 the strongest 'Home' is kept (good signal), 'Cafe' is marked open", "good" in sig and "open" in pg.locator(".net[data-ssid='Cafe'] .sig").inner_text(), sig)
    check("W1 the Jooki's name is shown", "JOOKI2_TEST01" in pg.locator("#who").inner_text())
    pg.wait_for_selector("[data-forget]")
    known = pg.locator("[data-forget]").evaluate_all("els => els.map(e => e.getAttribute('data-forget'))")
    check("W1 remembered networks listed", known == ["Old box", "Home"], known)
    check("W1 connect disabled until a network is chosen", pg.locator("#connect").is_disabled())
    # W2 open network
    pg.click(".net[data-ssid='Cafe']")
    check("W2 an open network needs no password", pg.locator("#pw").is_disabled() and pg.locator("#connect").is_enabled() and "none" in pg.locator("#pwlabel").inner_text())
    # W3 hidden network
    pg.click("#hiddenbtn"); pg.fill("#ssid", "Hidden one")
    check("W3 a hidden network can be typed", pg.locator("#connect").is_enabled() and "Hidden one" in pg.locator("#pwlabel").inner_text() and pg.locator(".net.on").count() == 0)
    # W4 guard
    pg.click(".net[data-ssid='Home']"); pg.fill("#pw", "abc"); pg.click("#connect")
    check("W4 a short password is refused before anything is sent", pg.locator("#err").is_visible() and pg.evaluate("window.__jooki.attempts.length") == 0)
    # W5 good password
    pg.fill("#pw", "goodpassword"); pg.press("#pw", "Enter")
    pg.wait_for_selector("#result:not([hidden])", timeout=20000)
    att = pg.evaluate("window.__jooki.attempts")
    check("W5 Enter sends exactly the chosen network and password", att == [{"ssid": "Home", "pw": "goodpassword"}], att)
    check("W5 a new session was opened before the set-up (handshake)", pg.evaluate("window.__jooki.sessions") >= 2, pg.evaluate("window.__jooki.sessions"))
    check("W5 success card names the network and offers the Jooki's page", "ok" in pg.locator("#result").get_attribute("class") and "Home" in pg.locator("#rtitle").inner_text() and pg.locator("#openpage").is_visible() and "jooki.local" in pg.locator("#openpage").get_attribute("href"))
    check("W5 progress card shown the network while connecting", "Home" in pg.locator("#ptitle").inner_text(), pg.locator("#ptitle").inner_text())
    # W6 wrong password -> AuthError
    pg.click("#again"); pg.wait_for_selector("#step2:not([hidden])")
    pg.click(".net[data-ssid='Home']"); pg.fill("#pw", "wrongpassword"); pg.click("#connect")
    pg.wait_for_selector("#result:not([hidden])", timeout=20000)
    txt = pg.locator("#rtext").inner_text()
    check("W6 a wrong password is reported as such, and that the Jooki stays off Wi-Fi", "bad" in pg.locator("#result").get_attribute("class") and "password is wrong" in txt and "off Wi-Fi" in txt, txt)
    # W7 network not found
    pg.evaluate("window.__jooki.failMode = 'notfound'")
    pg.click("#again"); pg.click("#hiddenbtn"); pg.fill("#ssid", "Nowhere"); pg.fill("#pw", "goodpassword"); pg.click("#connect")
    pg.wait_for_selector("#result:not([hidden])", timeout=20000)
    txt = pg.locator("#rtext").inner_text()
    check("W7 'not found' explains distance and 2.4 GHz", "cannot find" in txt and "2.4" in txt, txt)
    check("W7 the typed (hidden) name was the one sent", pg.evaluate("window.__jooki.attempts.slice(-1)[0]") == {"ssid": "Nowhere", "pw": "goodpassword"})
    # W8 chip stays silent -> timeout (shortened by OJ_TIMEOUT)
    pg.evaluate("window.__jooki.failMode = 'silent'")
    pg.click("#again"); pg.click(".net[data-ssid='Far']"); pg.fill("#pw", "wrongpassword"); pg.click("#connect")
    pg.wait_for_selector("#result:not([hidden])", timeout=20000)
    txt = pg.locator("#rtext").inner_text()
    check("W8 no verdict from the chip: the page says what to check and to try again", "bad" in pg.locator("#result").get_attribute("class") and "password" in txt and "try again" in txt, txt)
    # W9 a read fails once during the attempt -> still a success
    pg.evaluate("window.__jooki.failMode = 'auth'; window.__jooki.dropOnce = true")
    pg.click("#again"); pg.click(".net[data-ssid='Home']"); pg.fill("#pw", "goodpassword"); pg.click("#connect")
    pg.wait_for_selector("#result:not([hidden])", timeout=20000)
    check("W9 one failed Bluetooth read does not end the attempt", "ok" in pg.locator("#result").get_attribute("class") and not pg.evaluate("window.__jooki.dropOnce"))
    # W10 forget: cancelled, then confirmed
    before = pg.locator("[data-forget]").evaluate_all("els => els.map(e => e.getAttribute('data-forget'))")
    accept["v"] = False
    pg.click("[data-forget='Old box']")
    B.quiet(0.3, "cancelled: nothing must change, so there is nothing to wait for")
    known = pg.locator("[data-forget]").evaluate_all("els => els.map(e => e.getAttribute('data-forget'))")
    check("W10 forget asks first; cancelled = nothing changes", len(dialogs) == 1 and "Old box" in dialogs[0] and known == before and "Old box" in before, (dialogs, known, before))
    accept["v"] = True
    pg.click("[data-forget='Old box']")
    pg.wait_for_function("document.querySelectorAll('[data-forget]').length === %d" % (len(before) - 1))
    known = pg.locator("[data-forget]").evaluate_all("els => els.map(e => e.getAttribute('data-forget'))")
    check("W10 confirmed: the Jooki forgot it (list re-read from the Jooki)", known == [k for k in before if k != "Old box"] and pg.evaluate("window.__jooki.known") == known, known)
    # W11 the chooser closed without a choice: no error shown
    pg.evaluate("window.__jooki.cancel = true"); pg.click("#again"); pg.evaluate("document.getElementById('device') || null")
    pg2 = ctx.new_page(); pg2.on("pageerror", lambda e: errs.append("PAGEERROR " + str(e)))
    pg2.goto(URL); pg2.evaluate("window.__jooki.cancel = true"); pg2.click("#find")
    pg2.wait_for_function("!!window.__jooki.request")        # the chooser was asked (and closed by the mock)
    B.quiet(0.3, "an error, had the page shown one, would follow the closed chooser at once")
    check("W11 closing the chooser shows no error", pg2.locator("#err").is_hidden() and pg2.locator("#step1").is_visible())
    # W12 Bluetooth off
    pg3 = ctx.new_page(); pg3.add_init_script("navigator.bluetooth.available = false")
    pg3.goto(URL); pg3.wait_for_selector("#err:not([hidden])")
    check("W12 Bluetooth off is said plainly", "Bluetooth is off" in pg3.locator("#etitle").inner_text())
    check("W13 no page error", not errs, errs)
    b.close()
R.finish()
