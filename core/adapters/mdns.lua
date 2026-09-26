-- adapters.mdns: answers "<name>.local" with the Jooki's address (docs/20).
-- A non-blocking UDP socket on 5353 shared with spotify_ctrl's own responder
-- (SO_REUSEADDR); if the port cannot be shared, the Jooki works without the
-- name. A queries get the address, AAAA queries get the "IPv4 only" NSEC
-- answer so browsers do not wait for IPv6. Pure packet functions are exposed
-- for the specs; `serve(ip, names)` is what the loop calls every turn.
local log = require("kernel.log")
local mdns = {}
mdns.__index = mdns

local GROUP, PORT = "224.0.0.251", 5353

local function u16(p, i) return p:byte(i) * 256 + p:byte(i + 1) end

--- Decode a QNAME at offset i; returns name (lower case), next offset; nil on compression or garbage.
function mdns.qname(p, i)
  local parts = {}
  for _ = 1, 20 do
    local n = p:byte(i)
    if not n or n >= 192 then return nil end
    if n == 0 then return table.concat(parts, "."):lower(), i + 1 end
    parts[#parts + 1] = p:sub(i + 1, i + n)
    i = i + n + 1
  end
  return nil
end

local function enc(name)
  local out = {}
  for part in name:gmatch("[^%.]+") do out[#out + 1] = string.char(#part) .. part end
  return table.concat(out) .. string.char(0)
end

--- The questions of a query packet we should answer: list of { name, qtype, raw }.
function mdns.questions(p, names)
  if #p < 17 or p:byte(3) >= 128 then return {} end    -- not a query
  local out = {}
  local i = 13
  for _ = 1, u16(p, 5) do
    local name, j = mdns.qname(p, i)
    if not name or not p:byte(j + 3) then break end
    local qtype = u16(p, j)
    local raw = p:sub(i, j + 3)
    i = j + 4
    if names[name] and (qtype == 1 or qtype == 255 or qtype == 28) then out[#out + 1] = { name = name, qtype = qtype, raw = raw } end
  end
  return out
end

--- Build the answer packet (unicast answers echo the id and the question).
function mdns.answer(q, ip, unicast, id)
  local a, b, c, d = ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  if not a then return nil end
  local ttl = unicast and 10 or 120
  local cls = unicast and 1 or 32769
  local head = (unicast and id or string.char(0, 0)) .. string.char(132, 0, 0, unicast and 1 or 0, 0, 1, 0, 0, 0, 0)
  local rr
  local name = enc(q.name)
  if q.qtype == 28 then
    local nx = name .. string.char(0, 1, 64)   -- NSEC: next = itself, bitmap "A only"
    rr = name .. string.char(0, 47, math.floor(cls / 256), cls % 256, 0, 0, math.floor(ttl / 256), ttl % 256, 0, #nx) .. nx
  else
    rr = name .. string.char(0, 1, math.floor(cls / 256), cls % 256, 0, 0, math.floor(ttl / 256), ttl % 256, 0, 4, tonumber(a), tonumber(b), tonumber(c), tonumber(d))
  end
  return head .. (unicast and q.raw or "") .. rr
end

function mdns.new(opts)
  local self = setmetatable({ sock = nil, joined = nil, names = {}, stats = { answered = 0 } }, mdns)
  local ok, socket = pcall(require, "socket")
  if not ok or not socket then return self end
  local s = socket.udp()
  s:setoption("reuseaddr", true)
  pcall(s.setoption, s, "reuseport", true)
  if not s:setsockname("0.0.0.0", (opts and opts.port) or PORT) then
    log.warn("mdns.port_unavailable", { port = PORT })
    s:close()
    return self
  end
  s:settimeout(0)
  pcall(s.setoption, s, "ip-multicast-ttl", 255)
  self.sock = s
  return self
end

function mdns:available() return self.sock ~= nil end

function mdns:set_names(list)
  self.names = {}
  for _, n in ipairs(list or {}) do self.names[n:lower()] = true end
end

local function join(self, ip)
  if self.joined == ip then return end
  if self.joined then pcall(self.sock.setoption, self.sock, "ip-drop-membership", { multiaddr = GROUP, interface = self.joined }) end
  local ok = self.sock:setoption("ip-add-membership", { multiaddr = GROUP, interface = ip })
  self.joined = ok and ip or nil
  if ok then log.info("mdns.answering", { ip = ip }) end
end

--- Called every loop turn: answers pending queries for `names` with `ip`. Never blocks.
function mdns:serve(ip)
  if not self.sock or not ip or ip == "" then return 0 end
  join(self, ip)
  local n = 0
  for _ = 1, 8 do
    local p, rip, rport = self.sock:receivefrom()
    if not p then break end
    for _, q in ipairs(mdns.questions(p, self.names)) do
      local uni = rport ~= PORT
      local pkt = mdns.answer(q, ip, uni, p:sub(1, 2))
      if pkt then
        if uni then self.sock:sendto(pkt, rip, rport) else self.sock:sendto(pkt, GROUP, PORT) end
        n = n + 1
        self.stats.answered = self.stats.answered + 1
      end
    end
  end
  return n
end

function mdns:close()
  if self.sock then self.sock:close() self.sock = nil end
end

return mdns
