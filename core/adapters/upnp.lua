-- adapters.upnp: the network side of the UPnP player (services.upnp, #29).
--   SSDP  (UDP 1900, multicast 239.255.255.250): answers the apps' searches (M-SEARCH) and announces
--         the Jooki (NOTIFY ssdp:alive) at start, on every address change and every 30 s, like the
--         .local name (adapters.mdns): the Wi-Fi chip misses most multicast it is sent, so waiting for
--         questions is not enough. Turned off: says goodbye (ssdp:byebye) and goes quiet.
--   HTTP  (the page's server, adapters.httpd, under /upnp/): the descriptions, the SOAP control
--         requests, the event subscriptions (SUBSCRIBE / UNSUBSCRIBE).
--   GENA  events: the apps that subscribed get a NOTIFY when what they see changes (TransportState,
--         the song, the volume). Sent from the loop, never blocking: a connection that does not open
--         or answer within a few seconds is dropped, and a subscriber that fails three times is.
--
--   local r = require("adapters.upnp").new({ http_port = 80, emit = loop.emit, doc = state.doc })
--   r:http(method, path, headers, body, now)  -> status, content type, body, extra header lines (or nil: not ours)
--   r:serve(doc, now)                          once per loop turn
-- Pure packet and header functions are exposed for the specs.
local log = require("kernel.log")
local svc = require("services.upnp")
local upnp = {}
upnp.__index = upnp

local GROUP, PORT = "239.255.255.250", 1900
local MAX_AGE = 1800
local SERVER = "Linux/4 UPnP/1.0 OpenJooki/2"
local BURST, EVERY = { 0, 1, 3 }, 30
local SUB_MIN, SUB_MAX, SUB_DEFAULT = 60, 3600, 1800
local MAX_SUBS = 16
local SEND_TIMEOUT_S = 4
local MAX_FAILS = 3

-- ------------------------------------------------------------------ SSDP packets
--- A datagram -> method ("M-SEARCH", "NOTIFY", "HTTP"...) and its headers (lower-case names); nil on garbage.
function upnp.parse(p)
  p = tostring(p or "")
  local first = p:match("^([^\r\n]*)")
  local method = first and first:match("^(%S+)")
  if not method then return nil end
  local h = {}
  for k, v in p:gmatch("\r?\n([%w%-]+):[ \t]*([^\r\n]*)") do h[k:lower()] = v end
  return method, h
end

--- The (NT/ST, USN) pairs the Jooki answers for, given its UDN.
function upnp.targets(udn)
  local list = { { "upnp:rootdevice", udn .. "::upnp:rootdevice" }, { udn, udn }, { svc.DEVICE, udn .. "::" .. svc.DEVICE } }
  for _, s in ipairs(svc.SERVICES) do list[#list + 1] = { s.type, udn .. "::" .. s.type } end
  return list
end

--- The pairs a search target (ST) asks for: all of them, one, or none. A lower version of a type
--- is answered too (version 1 is all the Jooki has).
function upnp.matching(st, udn)
  st = tostring(st or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local all = upnp.targets(udn)
  if st == "ssdp:all" then return all end
  for _, t in ipairs(all) do
    if t[1] == st then return { t } end
    local base, ver = st:match("^(urn:.+:)(%d+)$")
    if base and t[1] == base .. "1" and tonumber(ver) and tonumber(ver) >= 1 then return { { st, udn .. "::" .. st } } end
  end
  return {}
end

--- The unicast answer to an M-SEARCH.
function upnp.search_response(st, usn, location)
  return table.concat({ "HTTP/1.1 200 OK", "CACHE-CONTROL: max-age=" .. MAX_AGE, "EXT:", "LOCATION: " .. location,
    "SERVER: " .. SERVER, "ST: " .. st, "USN: " .. usn, "", "" }, "\r\n")
end

--- A NOTIFY announcement (nts = "ssdp:alive" or "ssdp:byebye").
function upnp.notify(nt, usn, nts, location)
  local lines = { "NOTIFY * HTTP/1.1", "HOST: " .. GROUP .. ":" .. PORT, "NT: " .. nt, "NTS: " .. nts, "USN: " .. usn }
  if nts == "ssdp:alive" then
    lines[#lines + 1] = "CACHE-CONTROL: max-age=" .. MAX_AGE
    lines[#lines + 1] = "LOCATION: " .. location
    lines[#lines + 1] = "SERVER: " .. SERVER
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = ""
  return table.concat(lines, "\r\n")
end

--- Is an announcement due at `now`? (the schedule of adapters.mdns: 0, 1, 3 s, then every 30 s)
function upnp.due(sched, now, key)
  if sched.key ~= key then sched.key, sched.step, sched.at = key, 1, now end
  if now < sched.at then return false end
  sched.step = sched.step + 1
  sched.at = BURST[sched.step] and (sched.at - BURST[sched.step - 1] + BURST[sched.step]) or (now + EVERY)
  return true
end

--- "http://host:port/path" -> host, port, path; nil unless a plain http address (GENA callbacks).
function upnp.split_url(u)
  local host, port, path = tostring(u or ""):match("^http://([%w%.%-]+):?(%d*)(/?[^%s]*)$")
  if not host then return nil end
  return host, tonumber(port) or 80, path ~= "" and path or "/"
end

--- The first callback address of a CALLBACK header ("<http://a/b><http://c/d>").
function upnp.callback(h)
  for u in tostring(h or ""):gmatch("<([^>]+)>") do
    if upnp.split_url(u) then return u end
  end
  return nil
end

--- "Second-1800" -> 1800, kept between 60 s and 1 h ("infinite" = 1 h).
function upnp.timeout(h)
  local n = tonumber(tostring(h or ""):match("[Ss]econd%-(%d+)"))
  if not n then return SUB_DEFAULT end
  if n < SUB_MIN then return SUB_MIN end
  if n > SUB_MAX then return SUB_MAX end
  return n
end

-- ------------------------------------------------------------------ the adapter
function upnp.new(opts)
  opts = opts or {}
  local self = setmetatable({
    http_port = opts.http_port or 80, emit = opts.emit or function() end, port = opts.port or PORT,
    sock = nil, joined = nil, sched = {}, announced = nil, subs = {}, sent = {}, n_subs = 0, seq_id = 0,
    stats = { searches = 0, answered = 0, announced = 0, requests = 0, events = 0, event_fails = 0 },
    socket_lib = nil, clock = opts.clock,
  }, upnp)
  local ok, socket = pcall(require, "socket")
  if ok and socket then self.socket_lib = socket end
  return self
end

function upnp:open()
  if self.sock or not self.socket_lib then return self.sock ~= nil end
  local s = self.socket_lib.udp()
  s:setoption("reuseaddr", true)
  pcall(s.setoption, s, "reuseport", true)
  if not s:setsockname("0.0.0.0", self.port) then
    if not self.warned then log.warn("upnp.port_unavailable", { port = self.port }) self.warned = true end
    s:close()
    return false
  end
  s:settimeout(0)
  pcall(s.setoption, s, "ip-multicast-ttl", 4)
  self.sock = s
  return true
end

function upnp:close()
  if self.sock then pcall(function() self.sock:close() end) end
  self.sock, self.joined, self.sched = nil, nil, {}
end

local function location(self, ip) return "http://" .. ip .. ":" .. self.http_port .. "/upnp/desc.xml" end

local function join(self, ip)
  if self.joined == ip then return end
  if self.joined then pcall(self.sock.setoption, self.sock, "ip-drop-membership", { multiaddr = GROUP, interface = self.joined }) end
  local ok = self.sock:setoption("ip-add-membership", { multiaddr = GROUP, interface = ip })
  self.joined = ok and ip or nil
  pcall(self.sock.setoption, self.sock, "ip-multicast-if", ip)
end

local function announce(self, udn, nts, ip)
  for _, t in ipairs(upnp.targets(udn)) do
    if self.sock:sendto(upnp.notify(t[1], t[2], nts, location(self, ip)), GROUP, PORT) then self.stats.announced = self.stats.announced + 1 end
  end
end

--- Once per loop turn: SSDP (announce, answer), the events. Never blocks.
function upnp:serve(doc, now)
  local on = svc.enabled(doc)
  local ip = doc.net and doc.net.ip
  if not on then
    -- turned off (or never on): goodbye once, then the socket is closed and the apps forget it
    if self.sock and self.announced and ip and ip ~= "" then announce(self, self.announced, "ssdp:byebye", ip) end
    self.announced = nil
    if self.sock then self:close() end
    if self.n_subs > 0 or (self.outbox and #self.outbox > 0) then self:drop_subs() end
    return
  end
  -- SSDP needs the Jooki's address (LOCATION); the events do not
  if ip and ip ~= "" and self:open() then self:ssdp(doc, ip, now) end
  self:events(doc, now)
end

function upnp:ssdp(doc, ip, now)
  join(self, ip)
  local udn = svc.udn(doc)
  if upnp.due(self.sched, now, ip .. " " .. udn) then
    announce(self, udn, "ssdp:alive", ip)
    self.announced = udn
  end
  for _ = 1, 8 do
    local p, rip, rport = self.sock:receivefrom()
    if not p then break end
    local method, h = upnp.parse(p)
    if method == "M-SEARCH" and tostring(h["man"] or ""):find("ssdp:discover", 1, true) then
      self.stats.searches = self.stats.searches + 1
      for _, t in ipairs(upnp.matching(h["st"], udn)) do
        self.sock:sendto(upnp.search_response(t[1], t[2], location(self, ip)), rip, rport)
        self.stats.answered = self.stats.answered + 1
      end
    end
  end
end

-- ------------------------------------------------------------------ HTTP (called by adapters.httpd)
local XML = 'text/xml; charset="utf-8"'

--- A request under /upnp/: status line, content type, body, extra header lines. nil: not ours.
function upnp:http(doc, method, path, headers, body, now)
  path = tostring(path or ""):gsub("%?.*$", "")
  if path:sub(1, 6) ~= "/upnp/" then return nil end
  if not svc.enabled(doc) then return "404 Not Found", "text/plain", "not found" end
  self.stats.requests = self.stats.requests + 1
  local key
  if method == "GET" or method == "HEAD" then
    if path == "/upnp/desc.xml" then return "200 OK", XML, svc.description(doc) end
    key = path:match("^/upnp/(%a+)%.xml$")
    local x = key and svc.scpd(key)
    if x then return "200 OK", XML, x end
    return "404 Not Found", "text/plain", "not found"
  end
  if method == "POST" then
    key = path:match("^/upnp/ctl/(%a+)$")
    local s = key and svc.BY_KEY[key]
    if not s then return "404 Not Found", "text/plain", "not found" end
    local action, args = svc.parse_soap(body)
    -- SOAPACTION: "urn:...:AVTransport:1#Play" names it too; the body is what counts
    if not action then return "500 Internal Server Error", XML, svc.soap_fault(401, "Invalid Action"), { "EXT:" } end
    local r = svc.request(doc, key, action, args)
    if r.fault then
      log.info("upnp.refused", { action = action, code = r.fault.code })
      return "500 Internal Server Error", XML, svc.soap_fault(r.fault.code, r.fault.text), { "EXT:" }
    end
    if r.event then
      r.event.now = now
      self.emit(r.event)
    end
    return "200 OK", XML, svc.soap_response(s.type, action, r.out), { "EXT:", "SERVER: " .. SERVER }
  end
  key = path:match("^/upnp/evt/(%a+)$")
  if not key or not svc.BY_KEY[key] then return "404 Not Found", "text/plain", "not found" end
  if method == "SUBSCRIBE" then return self:subscribe(doc, key, headers or {}, now) end
  if method == "UNSUBSCRIBE" then
    local sid = (headers or {})["sid"]
    if not sid or not self.subs[sid] then return "412 Precondition Failed", "text/plain", "" end
    self.subs[sid], self.sent[sid] = nil, nil
    self.n_subs = self.n_subs - 1
    return "200 OK", "text/plain", ""
  end
  return "405 Method Not Allowed", "text/plain", ""
end

-- ------------------------------------------------------------------ GENA
local function new_sid(self, now)
  self.seq_id = self.seq_id + 1
  local r = math.floor((tonumber(now) or 0) * 1000) % 4294967296
  return string.format("uuid:4a6f6f6b-%04x-4000-8000-%08x%04x", self.seq_id % 65536, r, math.random(0, 65535))
end

function upnp:subscribe(_, key, h, now)
  now = tonumber(now) or 0
  local secs = upnp.timeout(h["timeout"])
  if h["sid"] then
    -- renewal: no CALLBACK, no NT
    local sub = self.subs[h["sid"]]
    if not sub or h["callback"] or h["nt"] then return "412 Precondition Failed", "text/plain", "" end
    sub.expires = now + secs
    return "200 OK", "text/plain", "", { "SID: " .. h["sid"], "TIMEOUT: Second-" .. secs, "SERVER: " .. SERVER }
  end
  local cb = upnp.callback(h["callback"])
  if h["nt"] ~= "upnp:event" or not cb then return "412 Precondition Failed", "text/plain", "" end
  -- the oldest goes when there are too many (an app that subscribes at every start, never unsubscribes)
  if self.n_subs >= MAX_SUBS then
    local oldest, at
    for sid, sub in pairs(self.subs) do if not at or sub.since < at then oldest, at = sid, sub.since end end
    self.subs[oldest], self.sent[oldest] = nil, nil
    self.n_subs = self.n_subs - 1
  end
  local sid = new_sid(self, now)
  self.subs[sid] = { key = key, url = cb, seq = 0, expires = now + secs, since = now, fails = 0, initial = true }
  self.n_subs = self.n_subs + 1
  log.info("upnp.subscribed", { service = key })
  return "200 OK", "text/plain", "", { "SID: " .. sid, "TIMEOUT: Second-" .. secs, "SERVER: " .. SERVER }
end

function upnp:drop_subs()
  self.subs, self.n_subs, self.sent = {}, 0, {}
  for _, o in ipairs(self.outbox or {}) do if o.sock then pcall(function() o.sock:close() end) end end
  self.outbox = {}
end

--- The NOTIFY request of an event.
function upnp.notify_request(url, sid, seq, body)
  local host, port, path = upnp.split_url(url)
  return table.concat({ "NOTIFY " .. path .. " HTTP/1.1", "HOST: " .. host .. ":" .. port, 'CONTENT-TYPE: text/xml; charset="utf-8"',
    "NT: upnp:event", "NTS: upnp:propchange", "SID: " .. sid, "SEQ: " .. seq, "CONTENT-LENGTH: " .. #body,
    "CONNECTION: close", "", "" }, "\r\n") .. body
end

local function queue(self, sid, sub, body, now)
  local host, port = upnp.split_url(sub.url)
  self.outbox = self.outbox or {}
  -- a subscriber still busy with an older event gets only the newest (the old one says less)
  for i = #self.outbox, 1, -1 do
    local o = self.outbox[i]
    if o.sid == sid and not o.sock then table.remove(self.outbox, i) end
  end
  self.outbox[#self.outbox + 1] = { sid = sid, host = host, port = port,
    data = upnp.notify_request(sub.url, sid, sub.seq, body), deadline = now + SEND_TIMEOUT_S }
  sub.seq = sub.seq == 4294967295 and 1 or sub.seq + 1
end

--- Every turn: events for what changed, then move the pending sends on.
function upnp:events(doc, now)
  -- expired subscriptions
  for sid, sub in pairs(self.subs) do
    if now >= sub.expires then self.subs[sid], self.sent[sid] = nil, nil; self.n_subs = self.n_subs - 1 end
  end
  if self.n_subs > 0 then
    local sig = {}
    for _, s in ipairs(svc.SERVICES) do sig[s.key] = svc.signature(doc, s.key) end
    for sid, sub in pairs(self.subs) do
      if sub.initial or self.sent[sid] ~= sig[sub.key] then
        -- the first event a little after the subscription's answer (the app is ready for it then)
        if not sub.initial or now - sub.since >= 0.2 then
          sub.initial = nil
          self.sent[sid] = sig[sub.key]
          queue(self, sid, sub, svc.event_body(doc, sub.key), now)
        end
      end
    end
  end
  self:pump(now)
end

local function failed(self, o)
  local sub = self.subs[o.sid]
  self.stats.event_fails = self.stats.event_fails + 1
  if sub then
    sub.fails = sub.fails + 1
    if sub.fails >= MAX_FAILS then
      self.subs[o.sid], self.sent[o.sid] = nil, nil
      self.n_subs = self.n_subs - 1
      log.info("upnp.subscriber_gone", { service = sub.key })
    end
  end
end

--- The sends in progress: connect, write, wait for the answer's first line, close. Non-blocking.
function upnp:pump(now)
  local socket = self.socket_lib
  if not socket or not self.outbox or #self.outbox == 0 then return end
  local keep = {}
  for _, o in ipairs(self.outbox) do
    local done = false
    if now > o.deadline then
      if o.sock then pcall(function() o.sock:close() end) end
      failed(self, o)
      done = true
    elseif not o.sock then
      local s = socket.tcp()
      s:settimeout(0)
      local ok, err = s:connect(o.host, o.port)
      if ok or err == "timeout" or err == "Operation already in progress" then o.sock, o.off = s, 1
      else pcall(function() s:close() end); failed(self, o); done = true end
    end
    if not done and o.sock and o.off <= #o.data then
      local _, w = socket.select(nil, { o.sock }, 0)
      if w and #w > 0 then
        local i, serr, last = o.sock:send(o.data, o.off)
        if i then o.off = i + 1 elseif last and last >= o.off then o.off = last + 1 end
        if serr == "closed" or (serr and serr ~= "timeout") then
          pcall(function() o.sock:close() end); failed(self, o); done = true
        end
      end
    elseif not done and o.sock then
      -- the status line is enough ("HTTP/1.1 200"): read what has come, a bit at a time
      local line, rerr, partial = o.sock:receive("*l")
      o.buf = (o.buf or "") .. (line or partial or "")
      if line or rerr == "closed" or #o.buf >= 12 then
        if o.buf:match("^HTTP/%d%.%d 2") then
          self.stats.events = self.stats.events + 1
          local sub = self.subs[o.sid]
          if sub then sub.fails = 0 end
        else
          failed(self, o)
        end
        pcall(function() o.sock:close() end)
        done = true
      end
    end
    if not done then keep[#keep + 1] = o end
  end
  self.outbox = keep
end

return upnp
