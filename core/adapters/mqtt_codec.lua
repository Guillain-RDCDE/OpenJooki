-- adapters.mqtt_codec: MQTT 3.1.1 packets, pure functions (no socket).
-- Only what the core needs: CONNECT, CONNACK, PUBLISH (QoS 0), SUBSCRIBE,
-- SUBACK, PINGREQ, PINGRESP, DISCONNECT.
local codec = {}

local function u16(n) return string.char(math.floor(n / 256), n % 256) end
local function str(s) return u16(#s) .. s end

local function remaining_length(n)
  local out = ""
  repeat
    local b = n % 128
    n = math.floor(n / 128)
    if n > 0 then b = b + 128 end
    out = out .. string.char(b)
  until n == 0
  return out
end

function codec.connect(client_id, keepalive, username, password)
  local flags = 2   -- clean session
  if username then flags = flags + 128 end
  if password then flags = flags + 64 end
  local body = str("MQTT") .. string.char(4, flags) .. u16(keepalive) .. str(client_id)
  if username then body = body .. str(username) end
  if password then body = body .. str(password) end
  return string.char(0x10) .. remaining_length(#body) .. body
end

function codec.publish(topic, payload)
  local body = str(topic) .. payload
  return string.char(0x30) .. remaining_length(#body) .. body
end

function codec.subscribe(packet_id, topics)
  local body = u16(packet_id)
  for _, t in ipairs(topics) do body = body .. str(t) .. string.char(0) end
  return string.char(0x82) .. remaining_length(#body) .. body
end

function codec.pingreq() return string.char(0xC0, 0) end
function codec.disconnect() return string.char(0xE0, 0) end

--- Parse one packet from the start of `buf`. Returns packet, bytes_consumed;
--- or nil, "incomplete" when more bytes are needed; or nil, "bad" on garbage.
function codec.parse(buf)
  if #buf < 2 then return nil, "incomplete" end
  local first = buf:byte(1)
  local ptype = math.floor(first / 16)
  local len, mult, i = 0, 1, 2
  while true do
    if i > #buf then return nil, "incomplete" end
    local b = buf:byte(i)
    len = len + (b % 128) * mult
    mult = mult * 128
    i = i + 1
    if b < 128 then break end
    if i > 5 then return nil, "bad" end
  end
  if #buf < i - 1 + len then return nil, "incomplete" end
  local body = buf:sub(i, i - 1 + len)
  local consumed = i - 1 + len
  if ptype == 3 then
    local qos = math.floor(first / 2) % 4
    if #body < 2 then return nil, "bad" end
    local tlen = body:byte(1) * 256 + body:byte(2)
    local topic = body:sub(3, 2 + tlen)
    local pos = 3 + tlen
    if qos > 0 then pos = pos + 2 end
    return { type = "publish", topic = topic, payload = body:sub(pos), qos = qos }, consumed
  elseif ptype == 2 then
    return { type = "connack", session_present = body:byte(1) % 2 == 1, code = body:byte(2) }, consumed
  elseif ptype == 9 then
    local codes = {}
    for k = 3, #body do codes[#codes + 1] = body:byte(k) end
    return { type = "suback", packet_id = body:byte(1) * 256 + body:byte(2), codes = codes }, consumed
  elseif ptype == 13 then
    return { type = "pingresp" }, consumed
  else
    return { type = "other", ptype = ptype }, consumed
  end
end

return codec
