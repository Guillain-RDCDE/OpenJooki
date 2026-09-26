-- adapters.bus: a small MQTT 3.1.1 client on LuaSocket (QoS 0 only).
--   local bus = require("adapters.bus").new({ host, port, client_id, keepalive, topics })
--   bus:maintain(now)  -> "up" | "down" | nil   (connects, reconnects with backoff, pings)
--   bus:poll(timeout)  -> list of { topic, payload }
--   bus:publish(topic, payload) -> true | nil, reason
--   bus:socket()       -> the socket (for select) or nil
-- The client never blocks the loop: connect() has a short timeout, reads are
-- non-blocking, and a lost connection is reported and retried, not fatal.
local codec = require("adapters.mqtt_codec")
local log = require("kernel.log")
local bus = {}
bus.__index = bus

function bus.new(opts)
  local socket = require("socket")
  return setmetatable({
    socket_lib = socket,
    host = opts.host or "127.0.0.1", port = opts.port or 1883,
    client_id = opts.client_id or "openjooki-core",
    keepalive = opts.keepalive or 30,
    topics = opts.topics or {},
    username = opts.username, password = opts.password,
    min_backoff = opts.min_backoff or 1, max_backoff = opts.max_backoff or 30,
    sock = nil, buf = "", up = false,
    next_attempt = 0, backoff = opts.min_backoff or 1,
    last_sent = 0, last_recv = 0, packet_id = 0,
    stats = { sent = 0, received = 0, reconnects = 0 },
  }, bus)
end

function bus:socket() return self.up and self.sock or nil end
function bus:connected() return self.up end

local function send(self, data)
  if not self.sock then return nil, "not connected" end
  self.sock:settimeout(2)
  local ok, err = self.sock:send(data)
  self.sock:settimeout(0)
  if not ok then return nil, err end
  self.stats.sent = self.stats.sent + 1
  return true
end

local function drop(self, why)
  if self.sock then pcall(self.sock.close, self.sock) end
  self.sock, self.buf = nil, ""
  local was = self.up
  self.up = false
  if was then log.warn("bus.down", { reason = why }) end
  return was
end

local function try_connect(self, now)
  local sock = self.socket_lib.tcp()
  sock:settimeout(3)
  local ok, err = sock:connect(self.host, self.port)
  if not ok then sock:close() return nil, err end
  sock:setoption("tcp-nodelay", true)
  self.sock = sock
  local sent, serr = send(self, codec.connect(self.client_id, self.keepalive, self.username, self.password))
  if not sent then drop(self, serr) return nil, serr end
  sock:settimeout(3)
  local data, rerr, partial = sock:receive(4)
  sock:settimeout(0)
  data = data or partial
  local pkt = data and codec.parse(data)
  if not pkt or pkt.type ~= "connack" or pkt.code ~= 0 then
    drop(self, "connack")
    return nil, "connack " .. tostring(pkt and pkt.code or rerr)
  end
  if #self.topics > 0 then
    self.packet_id = self.packet_id % 65535 + 1
    local sok, serr2 = send(self, codec.subscribe(self.packet_id, self.topics))
    if not sok then drop(self, serr2) return nil, serr2 end
  end
  self.up, self.last_sent, self.last_recv = true, now, now
  return true
end

--- Keep the connection alive. Returns "up" / "down" on a transition.
function bus:maintain(now)
  if not self.up then
    if now < self.next_attempt then return nil end
    local ok, err = try_connect(self, now)
    if ok then
      self.backoff = self.min_backoff
      log.info("bus.up", { host = self.host, port = self.port })
      return "up"
    end
    self.stats.reconnects = self.stats.reconnects + 1
    log.warn("bus.connect_failed", { err = tostring(err), retry_s = self.backoff })
    self.next_attempt = now + self.backoff
    self.backoff = math.min(self.backoff * 2, self.max_backoff)
    return nil
  end
  if now - self.last_sent >= self.keepalive / 2 then
    if not send(self, codec.pingreq()) then
      if drop(self, "ping send failed") then self.next_attempt = now + self.min_backoff return "down" end
    else
      self.last_sent = now
    end
  end
  if now - self.last_recv > self.keepalive * 1.5 then
    if drop(self, "keepalive timeout") then self.next_attempt = now + self.min_backoff return "down" end
  end
  return nil
end

--- Read what is available (waiting at most `timeout` seconds) and return the messages.
function bus:poll(timeout, now)
  local out = {}
  if not self.up then return out end
  local sel = self.socket_lib.select({ self.sock }, nil, timeout or 0)
  if #sel == 0 then return out end
  local data, err, partial = self.sock:receive(4096)
  data = data or partial
  if err == "closed" then
    if drop(self, "closed by broker") then self.next_attempt = (now or 0) + self.min_backoff end
    return out, "down"
  end
  if data and #data > 0 then
    self.buf = self.buf .. data
    self.last_recv = now or self.last_recv
  end
  while #self.buf > 0 do
    local pkt, consumed = codec.parse(self.buf)
    if not pkt then
      if consumed == "bad" then self.buf = "" log.warn("bus.bad_packet") end
      break
    end
    self.buf = self.buf:sub(consumed + 1)
    if pkt.type == "publish" then
      self.stats.received = self.stats.received + 1
      out[#out + 1] = { topic = pkt.topic, payload = pkt.payload }
    end
  end
  return out
end

function bus:publish(topic, payload)
  if not self.up then return nil, "not connected" end
  local ok, err = send(self, codec.publish(topic, payload or ""))
  if not ok then
    if drop(self, "publish failed: " .. tostring(err)) then self.next_attempt = self.last_sent + self.min_backoff end
    return nil, err
  end
  self.last_sent = self.last_sent   -- publish does not count as a ping for the broker
  return true
end

function bus:close()
  if self.up then pcall(send, self, codec.disconnect()) end
  drop(self, "closed")
end

return bus
