#!/usr/bin/env python3
"""docs/tokens.html: a sticker becomes a Jooki token (Web NFC on Android Chrome, or the address to
write with an app), in a headless Chromium with a scripted NDEFReader.

The tokens it computes are checked against the format's own decoder, written here from Muuselabs'
README-NFC.md (Muuselabs' C decoder, nfc_ctrl/lib_decrypt.c, gave the same answers for 501 tokens
when the page was written, October 2026), and against their published example L9XYQwDTxUP3q5XI.

  python3 test_tokens_page.py        (Playwright + Chromium, like test_wifi_page.py)
"""
import base64, functools, http.server, os, threading
from playwright.sync_api import sync_playwright
import bench as B

DOCS = os.path.join(B.REPO, "docs")
R = B.Results(); check = R.check

KEY = bytes([0x03, 0x9c, 0x25, 0x6f, 0xb9, 0x2e, 0xe8, 0x08, 0x09, 0x83, 0xd9, 0x33, 0x56])


def decode(url):
    """What the Jooki reads in a token's address: (salt, code, uid), as lib_decrypt.c's decode()."""
    b = base64.b64decode(url.split("?s=", 1)[1])
    r = [b[i] ^ KEY[i] for i in range(3)]
    s = [KEY[3] ^ b[3] ^ r[0], KEY[4] ^ b[4] ^ r[1]]
    t = [KEY[5 + i] ^ b[5 + i] ^ r[(i + 2) % 3] for i in range(7)]
    return bytes(r).hex().upper(), s[0] << 8 | s[1], bytes(t).hex().upper()


# the scripted NFC reader: the test hands it stickers (window.__nfc.tap) and reads what was written
MOCK = r"""
(() => {
  const nfc = window.__nfc = { writes: [], readers: 0, failWrite: false, denyScan: false };
  const enc = s => new TextEncoder().encode(s).buffer;
  class NDEFReader {
    constructor() { nfc.readers++; nfc.current = this; }
    scan(opts) {
      if (nfc.denyScan) return Promise.reject(Object.assign(new Error('no'), { name: 'NotAllowedError' }));
      nfc.scanning = true;
      if (opts && opts.signal) opts.signal.addEventListener('abort', () => { nfc.scanning = false; });
      return Promise.resolve();
    }
    write(msg, opts) {
      if (nfc.failWrite) return Promise.reject(Object.assign(new Error('io'), { name: 'NetworkError' }));
      nfc.writes.push({ uid: nfc.inRange, records: msg.records, overwrite: !!(opts && opts.overwrite) });
      return Promise.resolve();
    }
  }
  window.NDEFReader = NDEFReader;
  // a sticker comes in range: its serial number and the URL records it holds (or other data)
  nfc.tap = (serial, urls, other) => {
    nfc.inRange = serial.replace(/:/g, '').toUpperCase();
    const records = (urls || []).map(u => ({ recordType: 'url', data: enc(u) }));
    if (other) records.push({ recordType: 'mime', mediaType: 'application/octet-stream', data: enc('x') });
    nfc.current.onreading({ serialNumber: serial, message: { records } });
  };
})();
"""

class Quiet(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a):
        pass


srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Quiet, directory=DOCS))
threading.Thread(target=srv.serve_forever, daemon=True).start()
URL = "http://127.0.0.1:%d/tokens.html" % srv.server_address[1]
STICKER, OTHER = "04:a1:b2:c3:d4:9c:41", "04:11:22:33:44:55:66"

with sync_playwright() as p:
    b = p.chromium.launch()
    errs = []

    def page(mock=True, query=""):
        pg = b.new_page()
        pg.on("pageerror", lambda e: errs.append("PAGEERROR " + str(e)))
        if mock:
            pg.add_init_script(MOCK)
        pg.goto(URL + query)
        return pg

    # T0 the format: Muuselabs' example, and a token for a sticker read back by the decoder
    pg = page(mock=False)
    check("T0 Muuselabs' example L9XYQwDTxUP3q5XI reads as code 0x00F0, UID 00010203040506",
          pg.evaluate("OJT.readToken('https://s.jooki.rocks/s/?s=L9XYQwDTxUP3q5XI')") == {"code": 0xF0, "uid": "00010203040506"})
    url = pg.evaluate("OJT.tokenUrl('04A1B2C3D49C41')")
    check("T0 a sticker's token: https://s.jooki.rocks/s/?s= + 16 characters, the flat-token code 512 and its own UID",
          url.startswith("https://s.jooki.rocks/s/?s=") and len(url.split("?s=")[1]) == 16
          and decode(url) == ("807751", 512, "04A1B2C3D49C41"), (url, decode(url)))
    other_codes = pg.evaluate("[0x103, 0x210, 260].map(c => OJT.tokenUrl('04112233445566', c))")
    check("T0 any token code is written as the Jooki reads it", [decode(u)[1:] for u in other_codes] == [(0x103, "04112233445566"), (0x210, "04112233445566"), (260, "04112233445566")])

    # T1 without Web NFC (an iPhone, a computer): said plainly; the address for a typed number
    check("T1 without Web NFC: the page says only Chrome on Android writes, and hides the button",
          pg.locator("#nonfc").is_visible() and pg.locator("#go").is_hidden() and "Android" in pg.inner_text("#nonfc"))
    pg.fill("#uid", "04 a1 b2 c3 d4 9c 41")
    check("T1 a number typed in (spaces, lower case): the address to write, the same token",
          pg.locator("#manual").is_visible() and pg.inner_text("#url") == url and pg.locator("#baduid").is_hidden())
    pg.fill("#uid", "04A1B2")
    check("T1 a wrong number: said, no address", pg.locator("#manual").is_hidden() and pg.locator("#baduid").is_visible())
    pg.close()
    pg = page(mock=False, query="?uid=04A1B2C3D49C41")
    check("T1 opened from OpenJooki's page (?uid=): the number is filled in and the address shown",
          pg.input_value("#uid") == "04A1B2C3D49C41" and pg.inner_text("#url") == url)
    pg.close()

    # T2 a blank sticker on Android: read, written with its own token, done
    pg = page()
    check("T2 with Web NFC: the button is there, no warning", pg.locator("#go").is_visible() and pg.locator("#nonfc").is_hidden())
    pg.click("#go")
    check("T2 'hold the sticker' while it waits", pg.locator("#wait").is_visible())
    pg.evaluate("__nfc.tap(%r, [])" % STICKER)
    pg.wait_for_selector("#done:not([hidden])")
    w = pg.evaluate("__nfc.writes")
    check("T2 one URL record written, to that sticker, with its own token",
          len(w) == 1 and w[0]["uid"] == "04A1B2C3D49C41" and len(w[0]["records"]) == 1
          and w[0]["records"][0] == {"recordType": "url", "data": url}, w)
    check("T2 done, with the sticker's number, and the scan stopped",
          "04A1B2C3D49C41" in pg.inner_text("#doneuid") and not pg.evaluate("__nfc.scanning"))

    # T3 a genuine Jooki token is never written over; the same token again is just "done"
    pg.click("#again")
    pg.evaluate("__nfc.tap(%r, [%r])" % (OTHER, "https://s.jooki.rocks/s/?s=" + other_codes[0].split("?s=")[1]))
    pg.wait_for_selector("#err:not([hidden])")
    check("T3 a real Jooki token (a character): refused, nothing written",
          "already a Jooki token" in pg.inner_text("#etitle") and len(pg.evaluate("__nfc.writes")) == 1)
    pg.click("#retry")
    pg.evaluate("__nfc.tap(%r, [%r])" % (STICKER, url))
    pg.wait_for_selector("#done:not([hidden])")
    check("T3 a sticker that already is its token: done, nothing written again",
          "already was" in pg.inner_text("#doneuid") and len(pg.evaluate("__nfc.writes")) == 1)

    # T4 a sticker holding something else: asked first; written only to that same sticker
    pg.click("#again")
    pg.evaluate("__nfc.tap(%r, ['https://example.com/'])" % STICKER)
    pg.wait_for_selector("#ask:not([hidden])")
    check("T4 a sticker with another address: the page asks, and says what it holds",
          "https://example.com/" in pg.inner_text("#asktext") and len(pg.evaluate("__nfc.writes")) == 1)
    pg.click("#erase")
    pg.evaluate("__nfc.tap(%r, [])" % OTHER)
    B.quiet(0.3, "a write to the wrong sticker, had the page made one, would follow the tap at once")
    w = pg.evaluate("__nfc.writes")
    check("T4 'replace', then ANOTHER sticker comes: that one gets its own token, not the first one's",
          len(w) == 2 and w[1]["uid"] == "04112233445566" and decode(w[1]["records"][0]["data"])[2] == "04112233445566", w[-1:])
    pg.click("#again")
    pg.evaluate("__nfc.tap(%r, [], true)" % STICKER)
    pg.wait_for_selector("#ask:not([hidden])")
    pg.click("#erase")
    pg.evaluate("__nfc.tap(%r, [], true)" % STICKER)
    pg.wait_for_selector("#done:not([hidden])")
    w = pg.evaluate("__nfc.writes")
    check("T4 'replace', the same sticker again: written over (overwrite), with its own token",
          len(w) == 3 and w[2]["uid"] == "04A1B2C3D49C41" and w[2]["overwrite"] and w[2]["records"][0]["data"] == url, w[-1:])
    pg.click("#again")
    pg.evaluate("__nfc.tap(%r, ['https://example.com/'])" % STICKER)
    pg.wait_for_selector("#ask:not([hidden])")
    pg.click("#keep")
    check("T4 'keep it': back to the start, nothing written", pg.locator("#ready").is_visible() and len(pg.evaluate("__nfc.writes")) == 3)

    # T5 a sticker the Jooki cannot read (not 7 bytes), a failed write, NFC not allowed
    pg.click("#go")
    pg.evaluate("__nfc.tap('04:a1:b2:c3', [])")
    pg.wait_for_selector("#err:not([hidden])")
    check("T5 a 4-byte sticker: refused (NTAG213/215/216 said), nothing written",
          "NTAG213" in pg.inner_text("#etext") and len(pg.evaluate("__nfc.writes")) == 3)
    pg.evaluate("__nfc.failWrite = true")
    pg.click("#retry")
    pg.evaluate("__nfc.tap(%r, [])" % STICKER)
    pg.wait_for_selector("#err:not([hidden])")
    check("T5 a write that fails: said, with what to do", "could not be written" in pg.inner_text("#etitle"))
    pg.close()
    pg = page()
    pg.evaluate("__nfc.denyScan = true")
    pg.click("#go")
    pg.wait_for_selector("#err:not([hidden])")
    check("T5 NFC not allowed for the page: said, with where to allow it", "not allowed" in pg.inner_text("#etitle"))
    pg.close()

    check("T6 no page error", not errs, errs)
    b.close()
R.finish()
