local httpd = require("adapters.httpd")

-- The pure parts of the web server, without a socket: the path check, the rebinding guard, the
-- request head and the multipart parser (a connection is a plain table the server reads and fills).
local dir = os.getenv("TMPDIR") or "/tmp"
local function read(p)
  local f = io.open(p, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end
local function write(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
local function conn(raw) return { inbuf = raw, phase = "head", headers = {}, last = 0 } end
local function status(c) return c.out and c.out:match("^HTTP/1.1 (%d+)") end

describe("adapters.httpd — safe_path", function()
  local sp = httpd._safe_path

  it("maps a URL path under the docroot; the root is index.html; the query string is dropped", function()
    assert_eq(sp("/w", "/"), "/w/index.html"); assert_eq(sp("/w", ""), "/w/index.html")
    assert_eq(sp("/w", "/app.js?v=3"), "/w/app.js")
    assert_eq(sp("/w", "/tokimg/fox.webp"), "/w/tokimg/fox.webp")
    assert_eq(sp("/w", "//a///b"), "/w/a/b")
  end)

  it("refuses any climb out of the docroot, encoded or not, and drops dot segments", function()
    assert_nil(sp("/w", "/../etc/passwd")); assert_nil(sp("/w", "/a/../../x")); assert_nil(sp("/w", "/a/.."))
    assert_nil(sp("/w", "/%2e%2e/etc/passwd")); assert_nil(sp("/w", "/a/%2E%2E/x"))
    assert_nil(sp("/w", "/a%2f..%2fb"))                      -- decoded before it is split: still a climb
    assert_eq(sp("/w", "/./a/./b"), "/w/a/b"); assert_eq(sp("/w", "/."), "/w/index.html")
    assert_eq(sp("/w", "/..."), "/w/...")                    -- three dots are a name, not a climb
  end)

  it("decodes percent escapes and + the way the page sends them", function()
    assert_eq(sp("/w", "/art%20work/a+b.png"), "/w/art work/a b.png")
    assert_eq(httpd._url_decode("%41%2f+"), "A/ ")
    assert_eq(httpd._ext_of("/x/App.JS"), "js"); assert_eq(httpd._ext_of("/x/noext"), ""); assert_eq(httpd._ext_of("/x/a.tar.gz"), "gz")
  end)
end)

describe("adapters.httpd — the rebinding guard (host_ok)", function()
  local h = httpd.new({ name = function() return "Jooki-Salon.local" end })

  it("accepts our own name (any case, with a port), any .local name, an IP literal, localhost, no Host", function()
    assert_true(h:host_ok(nil)); assert_true(h:host_ok(""))
    for _, ok in ipairs({ "jooki-salon.local", "JOOKI-SALON.LOCAL:80", "jooki.local", "printer.local",
                          "192.168.1.19", "192.168.1.19:8080", "localhost", "localhost:8080", "127.0.0.1" }) do
      assert_true(h:host_ok(ok), ok)
    end
  end)

  it("refuses anyone's domain (DNS rebinding), including one that only starts like ours", function()
    for _, bad in ipairs({ "evil.example.com", "jooki.local.evil.com", "muuselabs.com", "192.168.1.19.evil.com", "jooki-salon" }) do
      assert_false(h:host_ok(bad), bad)
    end
    assert_false(httpd.new({}):host_ok("jooki"))                                                -- no name known: nothing bare passes
    assert_true(httpd.new({ name = function() return "jooki" end }):host_ok("JOOKI:80"))        -- the live name, as the state gives it
  end)
end)

describe("adapters.httpd — request head and routing, without a socket", function()
  local h = httpd.new({ docroot = dir, uploads_dir = dir })
  local page = dir .. "/oj_httpd_spec_index.html"
  before_each(function() write(page, "<html>hi</html>") end)

  it("serves a file under the docroot with its type and length; HEAD sends no body", function()
    local c = conn("GET /oj_httpd_spec_index.html?v=2 HTTP/1.1\r\nHost: jooki.local\r\nAccept: */*\r\n\r\n")
    h:parse_head(c)
    assert_eq(c.method, "GET"); assert_eq(c.headers.host, "jooki.local"); assert_eq(c.headers.accept, "*/*")
    assert_eq(c.phase, "resp"); assert_eq(status(c), "200")
    assert_match(c.out, "Content%-Type: text/html; charset=utf%-8"); assert_match(c.out, "Content%-Length: 15")
    assert_true(c.out_file ~= nil); c.out_file:close()
    c = conn("HEAD /oj_httpd_spec_index.html HTTP/1.1\r\n\r\n")
    h:parse_head(c)
    assert_eq(status(c), "200"); assert_nil(c.out_file)
  end)

  it("answers 404 for a missing file and for anything web_ctrl had that we do not (/ll, /cmd)", function()
    local c = conn("GET /oj_httpd_spec_nope.html HTTP/1.1\r\n\r\n"); h:parse_head(c); assert_eq(status(c), "404")
    c = conn("POST /cmd HTTP/1.1\r\nContent-Length: 2\r\n\r\nls"); h:parse_head(c); assert_eq(status(c), "404")
    c = conn("GET /ll?cmd=ls HTTP/1.1\r\n\r\n"); h:parse_head(c); assert_eq(status(c), "404")   -- web_ctrl's root shell: here, a missing file
  end)

  it("answers 400 to a climb and to a line that is not a request, 421 to a foreign Host", function()
    local c = conn("GET /%2e%2e/etc/passwd HTTP/1.1\r\n\r\n"); h:parse_head(c); assert_eq(status(c), "400")
    c = conn("garbage\r\n\r\n"); h:parse_head(c); assert_eq(status(c), "400")
    c = conn("GET /oj_httpd_spec_index.html HTTP/1.1\r\nHost: evil.example.com\r\n\r\n"); h:parse_head(c); assert_eq(status(c), "421")
  end)

  it("waits for the end of the head, and refuses one over 16 KiB", function()
    local c = conn("GET /oj_httpd_spec_index.html HTTP/1.1\r\nHost: jooki")
    h:parse_head(c)
    assert_eq(c.phase, "head"); assert_nil(c.out)
    c.inbuf = c.inbuf .. ".local\r\n\r\n"; h:parse_head(c); assert_eq(status(c), "200"); if c.out_file then c.out_file:close() end
    c = conn("GET / HTTP/1.1\r\nX: " .. string.rep("a", 17 * 1024)); h:parse_head(c); assert_eq(status(c), "431")
  end)

  it("the page's token pictures may be cached for a month, nothing else", function()
    local ok, lfs = pcall(require, "lfs")
    if ok and lfs then
      lfs.mkdir(dir .. "/tokimg"); write(dir .. "/tokimg/oj_httpd_spec.webp", "RIFF")
      local c = conn("GET /tokimg/oj_httpd_spec.webp HTTP/1.1\r\n\r\n"); h:parse_head(c)
      assert_match(c.out, "Cache%-Control: public, max%-age=2592000"); c.out_file:close()
      os.remove(dir .. "/tokimg/oj_httpd_spec.webp")
    end
    local c = conn("GET /oj_httpd_spec_index.html HTTP/1.1\r\n\r\n"); h:parse_head(c)
    assert_match(c.out, "Cache%-Control: no%-cache"); c.out_file:close()
  end)
end)

describe("adapters.httpd — multipart upload, fed by hand", function()
  local B = "----oj"
  local function body_of(parts)
    local s = ""
    for _, p in ipairs(parts) do
      s = s .. "--" .. B .. "\r\nContent-Disposition: form-data; name=\"" .. p[1] .. "\"; filename=\"f.mp3\"\r\nContent-Type: application/octet-stream\r\n\r\n" .. p[2] .. "\r\n"
    end
    return s .. "--" .. B .. "--\r\n"
  end
  local function head_for(body, boundary)
    return "POST /upload HTTP/1.1\r\nHost: jooki.local\r\nContent-Type: multipart/form-data; boundary=" .. (boundary or B) .. "\r\nContent-Length: " .. #body .. "\r\n\r\n"
  end
  local uploaded, logged
  local h = httpd.new({ docroot = dir, uploads_dir = dir, on_upload = function(n) uploaded = n end, log = function(k) logged = k end })
  before_each(function() uploaded, logged = nil, nil; os.remove(dir .. "/upload_1234"); os.remove(dir .. "/upload_77") end)

  it("one part, all at once: the body lands in uploads/upload_<field name>, 200 OK like web_ctrl", function()
    local body = body_of({ { "1234", "hello\r\nworld" } })
    local c = conn(head_for(body) .. body)
    h:parse_head(c)
    assert_eq(c.phase, "resp"); assert_eq(status(c), "200")
    assert_eq(read(dir .. "/upload_1234"), "hello\r\nworld")
    assert_eq(uploaded, 1); assert_eq(logged, "httpd.uploaded")
  end)

  it("bytes arriving one at a time, two parts, a delimiter look-alike inside the body: the same files", function()
    local first = string.rep("x", 100) .. "\r\n--not-the-end\r\n--" .. B:sub(1, 3) .. string.rep("y", 50)
    local body = body_of({ { "1234", first }, { "77", "second" } })
    local c = conn(head_for(body))
    h:parse_head(c)                   -- the head alone: the upload begins and waits for bytes
    assert_eq(c.phase, "upload"); assert_eq(c.up.left, #body)
    for i = 1, #body do
      c.inbuf = c.inbuf .. body:sub(i, i)
      h:feed_upload(c)
      if c.phase == "resp" then assert_eq(i, #body - 2, "done at the closing boundary, before the final CRLF"); break end
    end
    assert_eq(status(c), "200")
    assert_eq(read(dir .. "/upload_1234"), first)
    assert_eq(read(dir .. "/upload_77"), "second")
    assert_eq(uploaded, 2)
  end)

  it("refuses what is not a multipart post, an oversized one, and a field name that is not a plain name", function()
    local c = conn("POST /upload HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}")
    h:parse_head(c); assert_eq(status(c), "400"); assert_match(c.out, "expected multipart")
    c = conn("POST /upload HTTP/1.1\r\nContent-Type: multipart/form-data; boundary=x\r\nContent-Length: " .. (201 * 1024 * 1024) .. "\r\n\r\n")
    h:parse_head(c); assert_eq(status(c), "413")
    local body = body_of({ { "../etc/x", "boom" } })
    c = conn(head_for(body) .. body); h:parse_head(c)
    assert_eq(status(c), "400"); assert_eq(logged, "httpd.upload_failed"); assert_nil(uploaded)
    assert_nil(read(dir .. "/upload_../etc/x"))
  end)

  it("a malformed delimiter fails the upload and removes the half-written file", function()
    local body = "--" .. B .. "\r\nContent-Disposition: form-data; name=\"1234\"\r\n\r\npartial\r\n--" .. B .. "xx"
    local c = conn(head_for(body) .. body); h:parse_head(c)
    assert_eq(status(c), "400"); assert_nil(read(dir .. "/upload_1234")); assert_nil(uploaded)
  end)
end)
