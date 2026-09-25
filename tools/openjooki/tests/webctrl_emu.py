"""Minimal emulation of the Jooki's web_ctrl (Mongoose) for the bench:
static files from /tmp/web_ctrl_dirs/public, /ui/* -> index.html, /ping,
POST /upload (multipart, field name = upload id -> /tmp/web_ctrl_dirs/uploads/upload_<id>)."""
import http.server, os, re, sys, cgi, json
ROOT = "/tmp/web_ctrl_dirs/public"
class H(http.server.SimpleHTTPRequestHandler):
    def __init__(s, *a, **k): super().__init__(*a, directory=ROOT, **k)
    def log_message(s, *a): pass
    def do_GET(s):
        if s.path.startswith("/ping"):
            b=b'{"version":"bench"}'; s.send_response(200); s.send_header("Access-Control-Allow-Origin","*")
            s.send_header("Content-Type","application/json"); s.send_header("Content-Length",str(len(b))); s.end_headers(); s.wfile.write(b); return
        if any(s.path.startswith(p) for p in ("/config","/set_config","/ll","/rpc","/flags","/cmd","/wifi","/api/wifi","/setup")):
            s.send_error(500, "reserved web_ctrl route"); return   # like the real prefix router
        if s.path.startswith("/ui/"): s.path="/index.html"
        return super().do_GET()
    def do_POST(s):
        if not s.path.startswith("/upload"): s.send_error(404); return
        fs = cgi.FieldStorage(fp=s.rfile, headers=s.headers, environ={"REQUEST_METHOD":"POST","CONTENT_TYPE":s.headers["Content-Type"]})
        for k in fs.keys():
            if not re.fullmatch(r"\d+", k): s.send_error(500,"Invalid upload id"); return
            item = fs[k]; data = item.file.read()
            open("/tmp/web_ctrl_dirs/uploads/upload_%s"%k,"wb").write(data)
            b=("Ok, upload %s - %d bytes."%(k,len(data))).encode()
            s.send_response(200); s.send_header("Access-Control-Allow-Origin","*"); s.send_header("Content-Length",str(len(b))); s.end_headers(); s.wfile.write(b); return
        s.send_error(500,"no file")
http.server.ThreadingHTTPServer(("0.0.0.0", int(sys.argv[1]) if len(sys.argv)>1 else 8080), H).serve_forever()
