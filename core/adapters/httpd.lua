-- adapters.httpd: our own small web server, so web_ctrl (closed, with /ll and /cmd) can stop.
-- It serves the page's static files and the one POST it needs -- /upload -- and NOTHING else:
-- there is no /ll and no /cmd, so a root shell over HTTP is gone (ADR-0007). The realtime channel
-- stays on the MQTT WebSocket (port 8000, mosquitto); this server is only files + upload.
--
--   local h = require("adapters.httpd").new({ port=80, docroot=..., uploads_dir=..., name=fn, log=fn })
--   h:start()                    -> true | nil, err   (bind + listen; nil if LuaSocket is missing)
--   h:read_socks(), h:write_socks()   -> sockets for the loop's select
--   h:service_read(list, now), h:service_write(list, now)
--   h:tick(now)                  -> close idle/stale connections
--
-- It never blocks the loop: the listen socket and every connection are non-blocking, reads and
-- writes are bounded, uploads stream to disk (the RSS budget is 4 MB), and a slow client is
-- dropped on a timeout, never waited on.
local httpd = {}
httpd.__index = httpd

local MIME = {
  html = "text/html; charset=utf-8", htm = "text/html; charset=utf-8",
  js = "application/javascript; charset=utf-8", css = "text/css; charset=utf-8",
  json = "application/json; charset=utf-8", png = "image/png", jpg = "image/jpeg",
  jpeg = "image/jpeg", gif = "image/gif", svg = "image/svg+xml", ico = "image/x-icon",
  txt = "text/plain; charset=utf-8", webmanifest = "application/manifest+json",
  map = "application/json",
}

local READ_CHUNK = 16384
local MAX_HEAD = 16 * 1024               -- a request head over this is refused
local MAX_UPLOAD = 200 * 1024 * 1024     -- an upload body over this is refused
local CONN_TIMEOUT = 30                   -- a connection idle this long is dropped
local MAX_CONNS = 24

function httpd.new(opts)
  opts = opts or {}
  return setmetatable({
    port = opts.port or 80,
    docroot = (opts.docroot or "/tmp/web_ctrl_dirs/public"):gsub("/$", ""),
    uploads_dir = (opts.uploads_dir or "/jooki/external/jooki/uploads"):gsub("/$", ""),
    name_fn = opts.name,                  -- function() -> the Jooki's own name (rebinding guard)
    log = opts.log or function() end,
    on_upload = opts.on_upload,
    server = nil, conns = {}, socket_lib = nil,
  }, httpd)
end

function httpd:start()
  local ok, socket = pcall(require, "socket")
  if not ok or not socket then return nil, "no socket library" end
  self.socket_lib = socket
  local srv, err = socket.tcp()
  if not srv then return nil, err end
  srv:setoption("reuseaddr", true)
  local bound, berr = srv:bind("0.0.0.0", self.port)
  if not bound then srv:close(); return nil, "bind " .. self.port .. ": " .. tostring(berr) end
  local lok, lerr = srv:listen(16)
  if not lok then srv:close(); return nil, "listen: " .. tostring(lerr) end
  srv:settimeout(0)
  self.server = srv
  self.log("httpd.listening", { port = self.port, docroot = self.docroot })
  return true
end

function httpd:read_socks()
  local r = {}
  if self.server then r[#r + 1] = self.server end
  for _, c in pairs(self.conns) do
    if c.phase ~= "resp" then r[#r + 1] = c.sock end
  end
  return r
end

function httpd:write_socks()
  local w = {}
  for _, c in pairs(self.conns) do
    if c.phase == "resp" then w[#w + 1] = c.sock end
  end
  return w
end

-- ---- helpers ----------------------------------------------------------------
local function ext_of(path)
  return (path:match("%.([%w]+)$") or ""):lower()
end

local function url_decode(s)
  s = s:gsub("+", " ")
  return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

-- A path is safe when, once decoded and split, it never climbs out of the docroot.
local function safe_path(docroot, urlpath)
  urlpath = urlpath:gsub("%?.*$", "")
  urlpath = url_decode(urlpath)
  if urlpath == "" or urlpath == "/" then urlpath = "/index.html" end
  local parts = {}
  for seg in urlpath:gmatch("[^/]+") do
    if seg == ".." then return nil end
    if seg ~= "." then parts[#parts + 1] = seg end
  end
  if #parts == 0 then parts = { "index.html" } end
  return docroot .. "/" .. table.concat(parts, "/")
end

local function file_size(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local n = f:seek("end")
  f:close()
  return n
end

-- The rebinding guard: web_ctrl answered a foreign Host with 500. We accept only a Host that is
-- our own name, a *.local name, an IP literal, localhost, or empty -- never someone's domain.
function httpd:host_ok(host)
  if not host or host == "" then return true end
  host = host:gsub(":%d+$", ""):lower()
  if host == "localhost" or host == "127.0.0.1" then return true end
  if host:match("^%d+%.%d+%.%d+%.%d+$") then return true end
  if host:match("%.local$") then return true end
  local name = self.name_fn and self.name_fn()
  if name and host == tostring(name):lower() then return true end
  return false
end

-- Build the response head (a string). Body is either `body` (string) or streamed from `file`.
local function head(status, ctype, len, extra)
  local lines = {
    "HTTP/1.1 " .. status,
    "Content-Type: " .. ctype,
    "Content-Length: " .. tostring(len),
    "Connection: close",
    "Cache-Control: no-cache",
  }
  for _, l in ipairs(extra or {}) do lines[#lines + 1] = l end
  return table.concat(lines, "\r\n") .. "\r\n\r\n"
end

-- responses (no `self` needed: they only fill the connection's output fields)
local function respond_text(c, status, body, ctype)
  body = body or ""
  c.out = head(status, ctype or "text/plain; charset=utf-8", #body) .. (c.method == "HEAD" and "" or body)
  c.out_off = 1
  c.out_file = nil
  c.phase = "resp"
end

local function respond_file(c, path)
  local sz = file_size(path)
  if not sz then return respond_text(c, "404 Not Found", "not found", "text/plain") end
  local ct = MIME[ext_of(path)] or "application/octet-stream"
  c.out = head("200 OK", ct, sz)
  c.out_off = 1
  if c.method == "HEAD" then c.out_file = nil else c.out_file = io.open(path, "rb") end
  c.phase = "resp"
end

-- ---- request routing --------------------------------------------------------
function httpd:route(c)
  local host = c.headers["host"]
  if not self:host_ok(host) then
    return respond_text(c, "421 Misdirected Request", "bad host", "text/plain")
  end
  if c.method == "GET" or c.method == "HEAD" then
    local path = safe_path(self.docroot, c.path)
    if not path then return respond_text(c, "400 Bad Request", "bad path", "text/plain") end
    return respond_file(c, path)
  end
  if c.method == "POST" and c.path:gsub("%?.*$", "") == "/upload" then
    return self:begin_upload(c)
  end
  -- everything else, /ll and /cmd included, does not exist here
  return respond_text(c, "404 Not Found", "not found", "text/plain")
end

-- ---- upload (streaming multipart to disk) -----------------------------------
function httpd:begin_upload(c)
  local ct = c.headers["content-type"] or ""
  local boundary = ct:match("boundary=\"?([^\";]+)\"?")
  local clen = tonumber(c.headers["content-length"] or "")
  if not boundary or not clen then
    return respond_text(c, "400 Bad Request", "expected multipart/form-data", "text/plain")
  end
  if clen > MAX_UPLOAD then
    return respond_text(c, "413 Payload Too Large", "too large", "text/plain")
  end
  c.up = {
    boundary = "--" .. boundary,     -- the delimiter between parts
    left = clen,                     -- body bytes still to read from the socket
    sub = "preamble",                -- preamble -> parthead -> body
    file = nil, saved = 0, names = {},
  }
  c.phase = "upload"
  -- c.inbuf already holds any body bytes that arrived with the head
  return self:feed_upload(c)
end

-- Process whatever is in c.inbuf against the multipart state; returns when it needs more bytes.
function httpd:feed_upload(c)
  local up = c.up
  while true do
    if up.sub == "preamble" then
      -- skip to the first boundary
      local s = c.inbuf:find(up.boundary, 1, true)
      if not s then
        -- keep only a tail that could be the start of the boundary
        if #c.inbuf > #up.boundary then c.inbuf = c.inbuf:sub(-#up.boundary) end
        return
      end
      c.inbuf = c.inbuf:sub(s + #up.boundary)
      up.sub = "partsep"
    elseif up.sub == "partsep" then
      -- right after a boundary: either "--" (end) or "\r\n" (a part follows)
      if #c.inbuf < 2 then return end
      local two = c.inbuf:sub(1, 2)
      if two == "--" then return self:finish_upload(c) end
      if two == "\r\n" then c.inbuf = c.inbuf:sub(3); up.sub = "parthead"
      else return self:upload_fail(c, "malformed multipart") end
    elseif up.sub == "parthead" then
      local e = c.inbuf:find("\r\n\r\n", 1, true)
      if not e then
        if #c.inbuf > MAX_HEAD then return self:upload_fail(c, "part head too large") end
        return
      end
      local ph = c.inbuf:sub(1, e - 1)
      c.inbuf = c.inbuf:sub(e + 4)
      local name = ph:match('name="([^"]*)"') or ph:match("name=([^;%s]+)")
      -- the page uses the numeric upload id as the field name -> upload_<id>
      if not name or not name:match("^[%w%._-]+$") then return self:upload_fail(c, "bad field name") end
      local target = self.uploads_dir .. "/upload_" .. name
      local f, err = io.open(target, "wb")
      if not f then return self:upload_fail(c, "cannot open " .. target .. ": " .. tostring(err)) end
      up.file, up.target, up.saved = f, target, 0
      up.names[#up.names + 1] = name
      up.sub = "body"
    elseif up.sub == "body" then
      -- write everything up to the delimiter "\r\n--boundary"; keep a safe tail back in case it spans reads
      local delim = "\r\n" .. up.boundary
      local s = c.inbuf:find(delim, 1, true)
      if s then
        up.file:write(c.inbuf:sub(1, s - 1)); up.saved = up.saved + (s - 1)
        up.file:close(); up.file = nil
        c.inbuf = c.inbuf:sub(s + #delim)
        up.sub = "partsep"
      else
        local keep = #delim
        if #c.inbuf > keep then
          local emit = c.inbuf:sub(1, #c.inbuf - keep)
          up.file:write(emit); up.saved = up.saved + #emit
          c.inbuf = c.inbuf:sub(#c.inbuf - keep + 1)
        end
        return
      end
    end
  end
end

function httpd:upload_fail(c, why)
  if c.up and c.up.file then pcall(function() c.up.file:close() end) end
  if c.up and c.up.target then os.remove(c.up.target) end
  self.log("httpd.upload_failed", { err = why })
  return respond_text(c, "400 Bad Request", "upload failed", "text/plain")
end

function httpd:finish_upload(c)
  if c.up and c.up.file then pcall(function() c.up.file:close() end) end
  local n = c.up and #c.up.names or 0
  if self.on_upload then pcall(self.on_upload, n) end
  self.log("httpd.uploaded", { parts = n })
  -- web_ctrl answered 200 with an empty body; the page reads only the status
  return respond_text(c, "200 OK", "OK", "text/plain")
end

-- ---- connection lifecycle ---------------------------------------------------
function httpd:accept(now)
  while true do
    local sock = self.server:accept()
    if not sock then return end
    if self:count() >= MAX_CONNS then pcall(function() sock:close() end)
    else
      sock:settimeout(0)
      sock:setoption("tcp-nodelay", true)
      self.conns[sock] = { sock = sock, inbuf = "", phase = "head", headers = {}, last = now }
    end
  end
end

function httpd:count()
  local n = 0
  for _ in pairs(self.conns) do n = n + 1 end
  return n
end

function httpd:close_conn(c)
  if c.up and c.up.file then pcall(function() c.up.file:close() end) end
  if c.out_file then pcall(function() c.out_file:close() end) end
  pcall(function() c.sock:close() end)
  self.conns[c.sock] = nil
end

function httpd:parse_head(c)
  local e = c.inbuf:find("\r\n\r\n", 1, true)
  if not e then
    if #c.inbuf > MAX_HEAD then respond_text(c, "431 Request Header Fields Too Large", "too large") end
    return
  end
  local raw = c.inbuf:sub(1, e - 1)
  c.inbuf = c.inbuf:sub(e + 4)
  local line = raw:match("^[^\r\n]*")
  local method, path = line:match("^(%u+)%s+(%S+)%s+HTTP")
  if not method then return respond_text(c, "400 Bad Request", "bad request") end
  c.method, c.path = method, path
  for k, v in raw:gmatch("\r\n([%w%-]+):%s*([^\r\n]*)") do c.headers[k:lower()] = v end
  return self:route(c)
end

function httpd:on_readable(c, now)
  c.last = now
  local data, err, partial = c.sock:receive(READ_CHUNK)
  data = data or partial
  if data and #data > 0 then c.inbuf = c.inbuf .. data end
  if c.phase == "head" then
    self:parse_head(c)
  elseif c.phase == "upload" then
    if c.up then c.up.left = c.up.left - (data and #data or 0) end
    self:feed_upload(c)
    if c.phase == "upload" and c.up and c.up.left <= 0 and err == "closed" then
      self:upload_fail(c)  -- body ended before the closing boundary
    end
  end
  if err == "closed" and c.phase ~= "resp" then self:close_conn(c) end
end

function httpd:on_writable(c, now)
  c.last = now
  -- send the head buffer first, then stream the file
  if c.out and c.out_off <= #c.out then
    local i, serr, last = c.sock:send(c.out, c.out_off)
    if i then c.out_off = i + 1
    elseif last then c.out_off = last + 1
    elseif serr == "closed" then return self:close_conn(c) end
    if c.out_off <= #c.out then return end   -- more head to send next time
  end
  if c.out_file then
    local chunk = c.out_file:read(READ_CHUNK)
    if not chunk then c.out_file:close(); c.out_file = nil; return self:close_conn(c) end
    local i, serr, last = c.sock:send(chunk)
    local sent = i or last or 0
    if serr == "closed" then return self:close_conn(c) end
    if sent < #chunk then
      -- keep the unsent remainder as a pending head buffer; the file continues after it
      c.out = chunk:sub(sent + 1); c.out_off = 1
    end
    return
  end
  self:close_conn(c)   -- head fully sent, no file: done
end

function httpd:service_read(list, now)
  for _, s in ipairs(list) do
    if s == self.server then
      self:accept(now)
    else
      local c = self.conns[s]
      if c then self:on_readable(c, now) end
    end
  end
end

function httpd:service_write(list, now)
  for _, s in ipairs(list) do
    local c = self.conns[s]
    if c then self:on_writable(c, now) end
  end
end

function httpd:tick(now)
  for _, c in pairs(self.conns) do
    if now - (c.last or now) > CONN_TIMEOUT then self:close_conn(c) end
  end
end

function httpd:stop()
  for _, c in pairs(self.conns) do self:close_conn(c) end
  if self.server then pcall(function() self.server:close() end); self.server = nil end
end

return httpd
