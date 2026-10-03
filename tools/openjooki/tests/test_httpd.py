#!/usr/bin/env python3
"""adapters.httpd: our own web server that replaces web_ctrl (ADR-0007).

It drives the real Lua adapter on a test port and checks, over real HTTP:
  - it serves the page (small and large files, streamed),
  - POST /upload writes the part to uploads/upload_<field> (what services.uploads reads),
  - /ll and /cmd are GONE (404) -- the whole point: no root shell, no reboot over HTTP,
  - a foreign Host is refused (421, the DNS-rebinding guard web_ctrl had),
  - a path cannot climb out of the docroot,
  - HEAD returns headers without a body.

  python3 test_httpd.py         (needs lua5.1 + LuaSocket, both on the bench)
"""
import http.client, os, shutil, socket, subprocess, tempfile
import bench as B

REPO = B.REPO

DRIVER = r"""
package.path = (os.getenv("OJ_CORE") or ".") .. "/?.lua;" .. package.path
local httpd = require("adapters.httpd")
local socket = require("socket")
local port, docroot, uploads = tonumber(arg[1]), arg[2], arg[3]
local h = httpd.new({ port = port, docroot = docroot, uploads_dir = uploads,
  name = function() return "jooki" end,
  log = function(k) io.stderr:write("LOG " .. tostring(k) .. "\n") end })
local ok, err = h:start()
if not ok then
  io.stderr:write("START_FAIL " .. tostring(err) .. "\n")
  if arg[4] ~= "retry" then os.exit(3) end
  h:retry_later(socket.gettime())      -- what main.lua does: keep going, try again by itself
end
io.stdout:write("READY\n"); io.stdout:flush()
while true do
  local r, w = h:read_socks(), h:write_socks()
  local rl, wl = socket.select(r, w, 0.2)
  local now = socket.gettime()
  h:service_read(rl or {}, now)
  h:service_write(wl or {}, now)
  h:tick(now)
end
"""

PORT = 8099
R = B.Results(limit=0, lead="")
check = R.check


def ready(p, t=10):
    """READY on the driver's stdout within t s; on failure its stderr, read once it is stopped
    (a live child never closes it)."""
    try:
        B.wait_line(p, "READY", t)
        return True, ""
    except B.WaitTimeout as e:
        p.terminate()
        return False, "%s\n%s" % (e, p.stderr.read()[-800:])


def status(port):
    try:
        c = http.client.HTTPConnection("127.0.0.1", port, timeout=2)
        c.request("GET", "/"); r = c.getresponse(); r.read(); c.close()
        return r.status
    except OSError:
        return None


def get(path, host=None, method="GET", body=None, headers=None):
    c = http.client.HTTPConnection("127.0.0.1", PORT, timeout=10)
    h = dict(headers or {})
    if host:
        h["Host"] = host
    c.request(method, path, body=body, headers=h)
    r = c.getresponse()
    data = r.read()
    c.close()
    return r.status, data


def headers_of(path):
    c = http.client.HTTPConnection("127.0.0.1", PORT, timeout=10)
    c.request("GET", path)
    r = c.getresponse()
    r.read()
    c.close()
    return r.status, {k.lower(): v for k, v in r.getheaders()}


def port_taken_at_start():
    """The port is still held when the server starts (the core before it still closing): the page
    must come back by itself once the port is free, not stay down until the next start."""
    port = PORT + 1
    work = tempfile.mkdtemp(prefix="ojhttpd-retry-")
    docroot = os.path.join(work, "public")
    os.makedirs(docroot)
    open(os.path.join(docroot, "index.html"), "wb").write(b"back")
    drv = os.path.join(work, "driver.lua")
    open(drv, "w", newline="\n").write(DRIVER)
    holder = socket.socket()
    holder.bind(("0.0.0.0", port)); holder.listen(1)
    env = dict(os.environ, OJ_CORE=os.path.join(REPO, "core"))
    p = subprocess.Popen(["lua5.1", drv, str(port), docroot, work, "retry"],
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
    try:
        ok, err = ready(p)
        check("port taken at start: the core keeps running", ok and p.poll() is None, (p.poll(), err))
        holder.close()
        got = {}
        def back():
            got["st"] = status(port); return got["st"] == 200
        B.poll(back, 12, every=0.5)
        check("port freed: the page comes back by itself (within the 5 s retry)", got.get("st") == 200, got.get("st"))
    finally:
        p.terminate()
        try:
            p.wait(timeout=3)
        except Exception:
            p.kill()
        holder.close()
        shutil.rmtree(work, ignore_errors=True)


def restart_right_after_serving():
    """The core restarts just after serving the page: the port has connections in TIME_WAIT.
    The new server must bind at once (reuseaddr really set, whatever the LuaSocket version)."""
    port = PORT + 2
    work = tempfile.mkdtemp(prefix="ojhttpd-tw-")
    docroot = os.path.join(work, "public")
    os.makedirs(docroot)
    open(os.path.join(docroot, "index.html"), "wb").write(b"page")
    drv = os.path.join(work, "driver.lua")
    open(drv, "w", newline="\n").write(DRIVER)
    env = dict(os.environ, OJ_CORE=os.path.join(REPO, "core"))
    def run():
        return subprocess.Popen(["lua5.1", drv, str(port), docroot, work],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
    p = run()
    try:
        ready(p)
        for _ in range(3):
            c = http.client.HTTPConnection("127.0.0.1", port, timeout=3)
            c.request("GET", "/"); c.getresponse().read(); c.close()
        B.quiet(0.3, "the connections just closed must be sitting in TIME_WAIT when the server stops")
        p.terminate(); p.wait(timeout=3)
        p = run()
        ok, err = ready(p)
        check("restart right after serving: the new server binds at once (no 'address in use')", ok, err)
    finally:
        p.terminate()
        try:
            p.wait(timeout=3)
        except Exception:
            p.kill()
        shutil.rmtree(work, ignore_errors=True)


def main():
    work = tempfile.mkdtemp(prefix="ojhttpd-")
    docroot = os.path.join(work, "public")
    uploads = os.path.join(work, "uploads")
    os.makedirs(docroot)
    os.makedirs(uploads)
    index = b"<!doctype html><title>Jooki</title><script src=/app.js></script>"
    open(os.path.join(docroot, "index.html"), "wb").write(index)
    big = ("//" + "x" * 200000 + "\n").encode()   # ~200 KB, forces streaming across writes
    open(os.path.join(docroot, "app.js"), "wb").write(big)
    open(os.path.join(docroot, "app.css"), "wb").write(b"body{color:#000}")
    open(os.path.join(docroot, "oj-auth.json"), "wb").write(b'{"mqttUser":"jooki","mqttPass":"x"}')
    os.makedirs(os.path.join(docroot, "tokimg"))
    webp = b"RIFF\x1a\x00\x00\x00WEBPVP8L\x0d\x00\x00\x00/\x00\x00\x00\x10\x07\x10\x11\x11\x88\x88\xfe\x07\x00"
    open(os.path.join(docroot, "tokimg", "cat.webp"), "wb").write(webp)
    open(os.path.join(docroot, "tokimg", "index.json"), "wb").write(b'{"v":1}')

    drv = os.path.join(work, "driver.lua")
    open(drv, "w", newline="\n").write(DRIVER)
    env = dict(os.environ, OJ_CORE=os.path.join(REPO, "core"))
    p = subprocess.Popen(["lua5.1", drv, str(PORT), docroot, uploads],
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
    try:
        ok, err = ready(p)
        check("httpd starts", ok, err)
        if not ok:
            raise SystemExit(1)

        st, body = get("/")
        check("GET / serves index.html", st == 200 and body == index, (st, len(body)))

        st, body = get("/app.js")
        check("GET /app.js serves the large file whole (streamed)", st == 200 and body == big, (st, len(body)))

        st, body = get("/app.css")
        check("GET /app.css served", st == 200 and body == b"body{color:#000}", st)

        st, body = get("/oj-auth.json")
        check("GET /oj-auth.json served (page auth)", st == 200 and b"mqttPass" in body, st)

        st, _ = get("/nope.txt")
        check("GET unknown file -> 404", st == 404, st)

        # the token pictures of the library: WebP, and the phone may keep them (they never change)
        st, hd = headers_of("/tokimg/cat.webp")
        check("GET a library picture: image/webp, kept by the phone", st == 200 and hd.get("content-type") == "image/webp"
              and "max-age=" in hd.get("cache-control", ""), (st, hd))
        st, hd = headers_of("/tokimg/index.json")
        check("the library's index is not cached (it changes with the page)", st == 200 and hd.get("cache-control") == "no-cache", hd)
        st, hd = headers_of("/app.js")
        check("the page itself is not cached", hd.get("cache-control") == "no-cache", hd)

        # the security point of the whole change:
        st, _ = get("/ll?action=ls%20-la%20/")
        check("GET /ll -> 404 (no root shell over HTTP)", st == 404, st)
        st, _ = get("/cmd/reboot")
        check("GET /cmd/reboot -> 404 (no reboot over HTTP)", st == 404, st)
        st, _ = get("/cmd/factory_reset")
        check("GET /cmd/factory_reset -> 404", st == 404, st)

        # path traversal must not escape the docroot
        st, _ = get("/../../../../etc/passwd")
        check("path traversal refused", st in (400, 404), st)

        # DNS-rebinding guard
        st, _ = get("/", host="evil.example.com")
        check("foreign Host -> 421", st == 421, st)
        st, _ = get("/", host="jooki.local")
        check(".local Host allowed", st == 200, st)

        # HEAD: headers, no body
        st, body = get("/app.js", method="HEAD")
        check("HEAD /app.js -> 200, empty body", st == 200 and body == b"", (st, len(body)))

        # POST /upload (multipart, one part named as a numeric id)
        uid = "1234567"
        payload = b"ID3\x04\x00fake audio bytes \x00\x01\x02 end"
        boundary = "----ojtest"
        multipart = (
            ("--%s\r\n" % boundary).encode()
            + ('Content-Disposition: form-data; name="%s"; filename="song.mp3"\r\n' % uid).encode()
            + b"Content-Type: audio/mpeg\r\n\r\n"
            + payload + b"\r\n"
            + ("--%s--\r\n" % boundary).encode()
        )
        st, _ = get("/upload", method="POST", body=multipart,
                    headers={"Content-Type": "multipart/form-data; boundary=" + boundary})
        saved = os.path.join(uploads, "upload_" + uid)
        ok = st == 200 and os.path.exists(saved) and open(saved, "rb").read() == payload
        check("POST /upload writes uploads/upload_<id> with the exact bytes", ok,
              (st, os.path.exists(saved), (open(saved, "rb").read() if os.path.exists(saved) else None)))

        # a POST to something else is not an upload
        st, _ = get("/whatever", method="POST", body=b"x")
        check("POST to a non-/upload path -> 404", st == 404, st)

    finally:
        p.terminate()
        try:
            p.wait(timeout=3)
        except Exception:
            p.kill()
        shutil.rmtree(work, ignore_errors=True)

    port_taken_at_start()
    restart_right_after_serving()
    R.finish(list_failed=True, ok_line="OK: adapters.httpd verified (page, upload, and /ll + /cmd are gone)")


if __name__ == "__main__":
    main()
