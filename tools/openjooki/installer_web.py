#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
OpenJooki — "zero-level" installer with a local web interface (Mac / PC / mobile).

A tiny local server serves a page; the firmware is sent from the browser
(drag-and-drop), then installed by installer.py: writing to the spare
partition, bit-perfect verification, A/B activation with armed rollback. No
OS-specific component (no osascript, no Tk) → the same code everywhere. Standard library.
"""
import os, sys, json, threading, subprocess, tempfile, webbrowser
from urllib.parse import urlparse, parse_qs
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jooki, installer

STATE = {"host": jooki.DEFAULT_HOST, "host_ok": None, "firmware": None,
         "fw_label": None, "running": False, "percent": 0, "step": "Ready.",
         "log": [], "result": None}
LOCK = threading.Lock()


def set_step(m):
    with LOCK:
        STATE["step"] = m
        STATE["log"].append(m)


def set_prog(p):
    with LOCK:
        STATE["percent"] = int(p)


def do_check():
    try:
        ok = jooki.is_jooki(STATE["host"])
    except Exception:
        ok = False
    with LOCK:
        STATE["host_ok"] = bool(ok)


def _set_firmware(path, name):
    try:
        sz = installer.human(installer._uncompressed_size(path))
    except Exception:
        sz = "?"
    with LOCK:
        STATE["firmware"] = path
        STATE["fw_label"] = "%s — %s%s" % (name, sz, " (compressed)" if name.endswith(".gz") else "")


def do_install():
    with LOCK:
        if STATE["running"] or not STATE["firmware"]:
            return
        STATE["running"] = True
        STATE["result"] = None
        STATE["percent"] = 0
        STATE["log"] = []
    try:
        res = installer.install_firmware(STATE["host"], STATE["firmware"],
                                         on_step=set_step, on_progress=set_prog)
        with LOCK:
            STATE["result"] = ("ok" if (res.get("ok") and res.get("switched"))
                               else "okns" if res.get("ok") else "rollback")
    except installer.InstallError as e:
        set_step("FAILED: " + str(e))
        with LOCK:
            STATE["result"] = "fail:" + str(e)
    except Exception as e:
        set_step("Error: " + str(e))
        with LOCK:
            STATE["result"] = "fail:" + str(e)
    finally:
        with LOCK:
            STATE["running"] = False


PAGE = r"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>OpenJooki — Safe install</title>
<style>
 :root{--ink:#1b1f27;--sub:#6b7280;--line:#e3e6ec;--acc:#2f7d5b;--acc2:#3aa76d;
       --ok:#1a7f37;--err:#b3261e;--warn:#9a6700;--bg:#f4f5f7;--card:#fff;}
 *{box-sizing:border-box}
 body{margin:0;background:var(--bg);color:var(--ink);
      font:15px -apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif}
 .wrap{max-width:680px;margin:32px auto;padding:0 20px}
 h1{margin:0 0 2px;font-size:30px}
 .sub{color:var(--sub);margin:0 0 20px}
 .card{background:var(--card);border:1px solid var(--line);border-radius:14px;
       padding:20px;margin-bottom:16px;box-shadow:0 1px 2px rgba(0,0,0,.04)}
 .row{display:flex;align-items:center;gap:12px;margin:6px 0;flex-wrap:wrap}
 .row .lbl{width:80px;color:var(--sub)}
 button{font:inherit;border:0;border-radius:10px;padding:9px 16px;cursor:pointer}
 .ghost{background:#eef0f4;color:var(--ink)} .ghost:hover{background:#e5e8ee}
 .primary{background:var(--acc);color:#fff;font-weight:700;font-size:17px;
          padding:14px;width:100%;margin-top:6px}
 .primary:hover{background:var(--acc2)} .primary:disabled{background:#c7cdd6;cursor:not-allowed}
 .dot{font-weight:600}
 .dot.on{color:var(--ok)} .dot.off{color:var(--err)} .dot.wait{color:var(--sub)}
 #drop{margin-top:12px;border:2px dashed var(--line);border-radius:12px;padding:18px;
       text-align:center;color:var(--sub);transition:.15s}
 #drop.hot{border-color:var(--acc2);background:#f0faf4;color:var(--ink)}
 .barbg{height:16px;background:#e6e9ef;border-radius:9px;overflow:hidden;margin:8px 0}
 .barfl{height:100%;width:0;background:linear-gradient(90deg,var(--acc),var(--acc2));transition:width .3s}
 .step{margin:8px 0 0;font-weight:600}
 pre.log{background:#0f1420;color:#c7d0e0;border-radius:10px;padding:12px;height:170px;
         overflow:auto;font:12px ui-monospace,Menlo,monospace;white-space:pre-wrap;margin:12px 0 0}
 .banner{border-radius:10px;padding:12px 14px;font-weight:700;margin-top:12px;display:none}
 .banner.ok{display:block;background:#e7f6ec;color:var(--ok)}
 .banner.warn{display:block;background:#fdf3e3;color:var(--warn)}
 .banner.err{display:block;background:#fbe9e7;color:var(--err)}
 .note{color:var(--sub);font-size:13px;margin-top:10px}
 .shield{color:var(--acc);font-weight:700}
</style></head><body>
<div class="wrap">
 <h1>OpenJooki</h1>
 <p class="sub">Install a firmware in complete safety — <span class="shield">it cannot brick your Jooki.</span></p>
 <div class="card">
   <div class="row"><span class="lbl">Jooki</span>
     <span id="hostval"></span><span id="hostdot" class="dot wait">searching…</span>
     <button class="ghost" onclick="check()">Check</button></div>
   <div id="drop">
     <input type="file" id="file" style="display:none" onchange="if(this.files[0])upload(this.files[0])">
     <b>Drag your firmware here</b>, or <button class="ghost" onclick="document.getElementById('file').click()">Choose file…</button>
     <div id="fw" style="margin-top:8px;color:var(--sub)">(no file)</div>
   </div>
 </div>
 <button id="go" class="primary" disabled onclick="install()">Install safely</button>
 <p id="step" class="step">Ready.</p>
 <div class="barbg"><div id="bar" class="barfl"></div></div>
 <pre id="log" class="log"></pre>
 <div id="banner" class="banner"></div>
 <p class="note">Writing goes to the spare partition; the current one stays intact.
   The transfer is verified bit for bit. The Jooki reboots once; if it doesn't start,
   it returns on its own to the previous version. Do not unplug during the operation.</p>
</div>
<script>
let uploading=false;
async function post(u){try{await fetch(u,{method:"POST"})}catch(e){}}
function check(){const d=document.getElementById("hostdot");d.className="dot wait";d.textContent="searching…";post("/check");}
async function upload(file){
  if(uploading)return;uploading=true;
  document.getElementById("fw").textContent="Sending "+file.name+" …";
  try{await fetch("/upload?name="+encodeURIComponent(file.name),{method:"POST",body:file});}
  catch(e){document.getElementById("fw").textContent="upload failed";}
  uploading=false;
}
function install(){
  if(!confirm("Install this firmware on your Jooki?\n\nIt is written to the spare partition, verified bit for bit, then activated. The Jooki reboots once; if it doesn't start it returns on its own. Do not unplug."))return;
  post("/install");
}
const drop=document.getElementById("drop");
["dragenter","dragover"].forEach(e=>drop.addEventListener(e,ev=>{ev.preventDefault();drop.classList.add("hot");}));
["dragleave","drop"].forEach(e=>drop.addEventListener(e,ev=>{ev.preventDefault();drop.classList.remove("hot");}));
drop.addEventListener("drop",ev=>{if(ev.dataTransfer.files[0])upload(ev.dataTransfer.files[0]);});
function render(s){
  document.getElementById("hostval").textContent=s.host||"";
  const d=document.getElementById("hostdot");
  if(s.host_ok===true){d.className="dot on";d.textContent="online ✓";}
  else if(s.host_ok===false){d.className="dot off";d.textContent="not found ✕";}
  else{d.className="dot wait";d.textContent="searching…";}
  if(s.fw_label && !uploading){const fw=document.getElementById("fw");fw.textContent=s.fw_label;fw.style.color="var(--ink)";}
  document.getElementById("bar").style.width=(s.percent||0)+"%";
  document.getElementById("step").textContent=s.step||"";
  const lg=document.getElementById("log");lg.textContent=(s.log||[]).join("\n");lg.scrollTop=1e9;
  const go=document.getElementById("go");
  go.disabled=!(s.firmware && s.host_ok===true && !s.running);
  go.textContent=s.running?"Installing…":"Install safely";
  const b=document.getElementById("banner");b.className="banner";
  if(s.result==="ok"){b.className="banner ok";b.textContent="✓  Done — your Jooki is running the new firmware.";}
  else if(s.result==="okns"){b.className="banner ok";b.textContent="✓  Firmware written and verified (not activated).";}
  else if(s.result==="rollback"){b.className="banner warn";b.textContent="↩  The new version didn't start — automatic rollback. Nothing broken.";}
  else if(s.result && s.result.indexOf("fail:")===0){b.className="banner err";b.textContent="⚠  "+s.result.slice(5)+"  (your Jooki was not modified)";}
}
async function poll(){try{const r=await fetch("/state");render(await r.json());}catch(e){}setTimeout(poll,600);}
poll();
</script></body></html>"""


class H(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="application/json"):
        b = body.encode("utf-8") if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype + "; charset=utf-8")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        try:
            self.wfile.write(b)
        except Exception:
            pass

    def log_message(self, *a):
        pass

    def do_GET(self):
        if self.path == "/":
            return self._send(200, PAGE, "text/html")
        if self.path == "/state":
            with LOCK:
                s = dict(STATE)
            s["log"] = s["log"][-60:]
            return self._send(200, json.dumps(s))
        self._send(404, "{}")

    def do_POST(self):
        if self.path == "/check":
            threading.Thread(target=do_check, daemon=True).start()
            return self._send(200, "{}")
        if self.path.startswith("/upload"):
            q = parse_qs(urlparse(self.path).query)
            name = os.path.basename(q.get("name", ["firmware.bin"])[0]) or "firmware.bin"
            length = int(self.headers.get("Content-Length", "0") or 0)
            tmpdir = tempfile.mkdtemp(prefix="openjooki_")
            path = os.path.join(tmpdir, name)
            remaining = length
            with open(path, "wb") as f:
                while remaining > 0:
                    chunk = self.rfile.read(min(1024 * 1024, remaining))
                    if not chunk:
                        break
                    f.write(chunk); remaining -= len(chunk)
            if os.path.getsize(path) > 0:
                _set_firmware(path, name)
            return self._send(200, json.dumps({"fw_label": STATE.get("fw_label")}))
        if self.path == "/install":
            threading.Thread(target=do_install, daemon=True).start()
            return self._send(200, "{}")
        if self.path == "/quit":
            self._send(200, "{}")
            threading.Thread(target=lambda: os._exit(0), daemon=True).start()
            return
        self._send(404, "{}")


def open_browser(url):
    try:
        if webbrowser.open(url):
            return
    except Exception:
        pass
    for cmd in (["open", url], ["xdg-open", url], ["cmd", "/c", "start", "", url]):
        try:
            subprocess.Popen(cmd)
            return
        except Exception:
            pass


def main():
    if len(sys.argv) > 1 and os.path.isfile(sys.argv[1]):
        _set_firmware(sys.argv[1], os.path.basename(sys.argv[1]))
    port = int(os.environ.get("OPENJOOKI_PORT", "0"))
    lan = ("--lan" in sys.argv) or (os.environ.get("OPENJOOKI_LAN") == "1")
    bind = "0.0.0.0" if lan else "127.0.0.1"
    srv = ThreadingHTTPServer((bind, port), H)
    p = srv.server_address[1]
    url = "http://127.0.0.1:%d/" % p
    threading.Thread(target=do_check, daemon=True).start()
    if lan:
        ip = _lan_ip()
        lanurl = "http://%s:%d/" % (ip, p)
        print("OpenJooki Installer (local network):", lanurl)
        print("  → open this address from your phone (same WiFi).")
        open_browser(url)
    else:
        open_browser(url)
        print("OpenJooki Installer ready:", url)
    srv.serve_forever()


def _lan_ip():
    import socket
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("192.168.1.1", 80)); return s.getsockname()[0]
    except Exception:
        return "127.0.0.1"
    finally:
        s.close()


if __name__ == "__main__":
    main()
