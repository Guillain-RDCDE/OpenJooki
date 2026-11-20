local httpd = require("adapters.httpd")
local shell = require("adapters.shell")
local upnp = require("services.upnp")
local playback = require("services.playback")

-- An https song from an app (#50): curl fetches it to the card, the web server hands it to the player
-- over http while it grows. Here without curl or a socket: the files curl writes are written by hand,
-- and a connection is a table with a fake socket that keeps what it is sent.
local dir = (os.getenv("TMPDIR") or "/tmp") .. "/oj-relay-spec"
os.execute("rm -rf '" .. dir .. "' && mkdir -p '" .. dir .. "'")
local function write(p, s) local f = assert(io.open(p, "wb")); f:write(s); f:close() end
local function append(p, s) local f = assert(io.open(p, "ab")); f:write(s); f:close() end

local function sock(peer)
  local s = { sent = {} }
  function s.getpeername() return peer or "127.0.0.1", 40000 end
  function s.send(_, data, i) local piece = data:sub(i or 1); s.sent[#s.sent + 1] = piece; return (i or 1) + #piece - 1 end
  function s.close() s.closed = true end
  return s
end
local function conn(srv, path, headers, peer)
  local c = { sock = sock(peer), inbuf = "", phase = "head", headers = headers or {}, last = 100, method = "GET", path = path }
  srv.conns[c.sock] = c
  return c
end
local function body_of(c)
  local all = table.concat(c.sock.sent)
  return all:match("\r\n\r\n(.*)$") or "", all:match("^(.-)\r\n\r\n") or all
end
local function pump(srv, c, now)
  for _ = 1, 50 do
    if not srv.conns[c.sock] then return end
    if c.phase == "resp" then srv:on_writable(c, now) else srv:tick(now) end
  end
end

describe("relay (#50) — curl's answer", function()
  it("reads the last complete answer, after the redirects", function()
    local code, len, ct = httpd._relay_answer("HTTP/1.1 302 Found\r\nLocation: https://b/x\r\n\r\nHTTP/2 200\r\ncontent-type: audio/flac\r\ncontent-length: 1234\r\n\r\n")
    assert_eq(code, 200); assert_eq(len, 1234); assert_eq(ct, "audio/flac")
    assert_eq(httpd._relay_answer("HTTP/1.1 302 Found\r\nLocation: https://b/x\r\n\r\n"), 302)
    assert_nil(httpd._relay_answer("HTTP/1.1 200 OK\r\nContent-Le"))   -- not complete yet
  end)
end)

describe("relay (#50) — the web server", function()
  local srv = httpd.new({ relay_dir = dir, docroot = dir })
  local base = dir .. "/r-7"

  it("waits for the song's server, then hands over what the card has, and the rest as it comes", function()
    os.execute("rm -f '" .. dir .. "'/r-*")
    write(base, "")
    local c = conn(srv, "/relay/7")
    srv:route(c)
    assert_eq(c.phase, "relay_wait")                       -- no answer yet
    write(base .. ".h", "HTTP/1.1 200 OK\r\nContent-Type: audio/mpeg\r\nContent-Length: 10\r\n\r\n")
    write(base, "abcd")
    pump(srv, c, 101)
    local body, head = body_of(c)
    assert_match(head, "^HTTP/1.1 200 OK"); assert_match(head, "Content%-Length: 10"); assert_match(head, "audio/mpeg")
    assert_eq(body, "abcd"); assert_eq(c.phase, "relay_starved")
    append(base, "efghij")
    pump(srv, c, 102)
    assert_eq(body_of(c), "abcdefghij")
    assert_nil(srv.conns[c.sock])                         -- all ten bytes: done
  end)

  it("a seek is a range: from there, once the card has it", function()
    local c = conn(srv, "/relay/7", { range = "bytes=6-" })
    srv:route(c); pump(srv, c, 103)
    local body, head = body_of(c)
    assert_match(head, "206 Partial Content"); assert_match(head, "Content%-Range: bytes 6%-9/10"); assert_match(head, "Content%-Length: 4")
    assert_eq(body, "ghij")
  end)

  it("unknown size: streams until curl has finished", function()
    os.execute("rm -f '" .. dir .. "'/r-*")
    write(base .. ".h", "HTTP/1.1 200 OK\r\nContent-Type: audio/flac\r\n\r\n")
    write(base, "12345")
    local c = conn(srv, "/relay/7")
    srv:route(c); pump(srv, c, 104)
    assert_eq(body_of(c), "12345"); assert_eq(c.phase, "relay_starved")
    append(base, "678"); write(base .. ".end", "0\n")
    pump(srv, c, 105)
    local body, head = body_of(c)
    assert_eq(body, "12345678"); assert_nil(head:find("Content%-Length")); assert_nil(srv.conns[c.sock])
  end)

  it("a server that says no, or never answers: 502", function()
    os.execute("rm -f '" .. dir .. "'/r-*")
    write(base, ""); write(base .. ".h", "HTTP/1.1 403 Forbidden\r\n\r\n"); write(base .. ".end", "22\n")
    local c = conn(srv, "/relay/7"); srv:route(c); pump(srv, c, 106)
    assert_match(select(2, body_of(c)), "502 Bad Gateway")
    os.execute("rm -f '" .. dir .. "'/r-*"); write(base, "")
    c = conn(srv, "/relay/7"); srv:route(c)
    srv:tick(120); assert_eq(c.phase, "relay_wait")
    pump(srv, c, 131)
    assert_match(select(2, body_of(c)), "502 Bad Gateway")
  end)

  it("only the player on this Jooki: a phone on the Wi-Fi gets nothing", function()
    local c = conn(srv, "/relay/7", nil, "192.168.1.20"); srv:route(c)
    assert_match(c.out, "^HTTP/1.1 404")
  end)
end)

describe("relay (#50) — the shell action", function()
  local argv = shell.ACTIONS.relay_start.argv
  it("takes an https address and nothing a shell could read as more", function()
    local ok = { dir = "/jooki/external/oj-relay", id = 3, url = "https://cdn.example/a.flac?t=1&s=x%20y", max_bytes = 1000 }
    local a = argv(ok)
    assert_eq(a[1], "sh"); assert_eq(a[#a - 1], ok.url); assert_eq(a[#a], "1000")
    for _, bad in ipairs({ "http://cdn.example/a.flac", "https://a/b c", "https://a/b'c", "https://a/$(x)`y`", "file:///etc/shadow", "https://a/\nb" }) do
      local u = {}; for k, v in pairs(ok) do u[k] = v end
      u.url = bad
      assert_nil(argv(u))
    end
    local u = {}; for k, v in pairs(ok) do u[k] = v end
    u.id = 1.5; assert_nil(argv(u)); u.id = 3; u.dir = "../x"; assert_nil(argv(u))
  end)
end)

describe("relay (#50) — an app sends an https song", function()
  local function doc_with(relay)
    return {
      config = { data_dir = "/d", system_dir = "/sys", http_port = 80, relay_dir = relay, relay_max_mb = 600 },
      device = { hostname = "jooki" }, net = { ip = "192.168.1.11" },
      library = { playlists = {}, tracks = {}, tokens = {} },
      audiocfg = { volume = 40, upnp = true },
      playback = { state = "idle" }, playback_int = {},
    }
  end
  local SONG = "https://cdn.example/a.flac?token=x"

  it("is refused without a relay folder, taken with one", function()
    assert_eq(upnp.request(doc_with(""), "avt", "SetAVTransportURI", { InstanceID = "0", CurrentURI = SONG, CurrentURIMetaData = "" }).fault.code, 714)
    assert_nil(upnp.request(doc_with("/jooki/external/oj-relay"), "avt", "SetAVTransportURI", { InstanceID = "0", CurrentURI = SONG, CurrentURIMetaData = "" }).fault)
    assert_eq(upnp.request(doc_with("/r"), "avt", "SetAVTransportURI", { InstanceID = "0", CurrentURI = "https://a/b'c", CurrentURIMetaData = "" }).fault.code, 714)
  end)

  it("curl fetches it, the player reads it from our web server; the same song again reuses it", function()
    local d = doc_with("/jooki/external/oj-relay")
    local r = playback.play_uri(d, SONG, { title = "S" })
    local sh, play
    for _, c in ipairs(r.commands) do
      if c.kind == "shell" then sh = c end
      if c.kind == "bus.publish" and c.topic == "/j/audio/out/play" then play = c.payload end
    end
    assert_eq(sh.action, "relay_start"); assert_eq(sh.args.url, SONG); assert_eq(sh.args.id, 1)
    assert_eq(sh.args.max_bytes, 600 * 1048576); assert_true(shell.ACTIONS.relay_start.argv(sh.args) ~= nil)
    assert_eq(play, "7\thttp://127.0.0.1:80/relay/1")
    for k, v in pairs(r.state) do d[k] = v end
    assert_eq(d.playback.now.uri, SONG)                   -- what the app sees is its own address
    r = playback.play_uri(d, SONG, { title = "S" })
    for _, c in ipairs(r.commands) do assert_true(c.kind ~= "shell") end
    for k, v in pairs(r.state) do d[k] = v end
    r = playback.play_uri(d, SONG .. "2", {})
    local n = 0
    for _, c in ipairs(r.commands) do if c.kind == "shell" then n = n + 1; assert_eq(c.args.id, 2) end end
    assert_eq(n, 1)
  end)

  it("an http song goes straight to the player, as before", function()
    local r = playback.play_uri(doc_with("/r"), "http://192.168.1.20/a.mp3", {})
    for _, c in ipairs(r.commands) do assert_true(c.kind ~= "shell") end
  end)
end)
