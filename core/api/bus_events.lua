-- api.bus_events: what the daemons say on the bus, turned into typed events.
-- One place for every topic and payload format (docs/22 §3.2), so services
-- never parse a payload themselves. Unknown topics give nil; a malformed
-- payload gives an event with `bad = true` (logged by the kernel, never
-- delivered to a handler as a normal event).
local json = require("vendor.json")
local bus_events = {}

local function jsonish(payload)
  local ok, v = pcall(json.decode, payload)
  if ok and type(v) == "table" then return v end
  return nil
end

local AUDIO = { starting = true, playing = true, paused = true, stopped = true, ended = true }
local BUTTONS = { next = true, prev = true, fwd = true, rev = true, vol_inc = true, vol_dec = true, circle = true,
                  airplane_mode_on = true, airplane_mode_off = true, airplane_release = true, hp_plugged = true }

function bus_events.translate(topic, payload)
  local rest = topic:match("^/j/audio/input/(%w+)$")
  if rest then
    local d = jsonish(payload) or {}
    if rest == "position" then return { type = "audio.position", id = tonumber(d.id), ms = tonumber(d.pos) or 0 } end
    if AUDIO[rest] then return { type = "audio." .. rest, id = tonumber(d.id) } end
    return nil
  end
  if topic == "/j/nfc/input/tag" then
    local uid, star = tostring(payload):match("^(%x+),(%x+)$")
    if not uid then return { type = "nfc.tag", bad = true, raw = payload } end
    return { type = "nfc.tag", uid = uid:upper(), star_code = tonumber(star, 16) }
  end
  if topic == "/j/nfc/input/tag_removed" then return { type = "nfc.removed" } end
  if topic == "/j/nfc/input/tag_written" then return { type = "nfc.written", uid = tostring(payload) } end
  local btn = topic:match("^/j/gpio/input/([%w_]+)$")
  if btn then
    if btn == "vol_set" then
      local d = jsonish(payload) or {}
      return { type = "gpio.volume", percent = tonumber(d.vol) }
    end
    if BUTTONS[btn] then return { type = "gpio.button", button = btn, down = (tostring(payload) == "1") } end
    return nil
  end
  local pw = topic:match("^/j/power/input/([%w_]+)$")
  if pw == "battery_level" then
    local d = jsonish(payload) or {}
    return { type = "power.battery", mv = tonumber(d.mv), tenths = tonumber(d.p), mc = tonumber(d.t) }
  elseif pw == "plugged_in" then return { type = "power.plugged", on = tostring(payload) == "1" }
  elseif pw == "charging" then return { type = "power.charging", on = tostring(payload) == "1" }
  end
  if topic == "/j/esp32/input/net/sta/config" then
    local d = jsonish(payload) or {}
    return { type = "net.status", ssid = d.ssid, bssid = d.bssid, channel = tonumber(d.ch), signal = tonumber(d.signal),
             connected = d.stat == "success", ip = d.ip }
  end
  if topic == "/j/esp32/input/knobs/state" then
    local d = jsonish(payload) or {}
    return { type = "knobs", volume = tonumber(d.volume), headphones = tonumber(d.hp_state) == 1, control = tonumber(d.control) }
  end
  if topic == "/j/esp32/input/bt/device_connected" then
    local d = jsonish(payload) or {}
    return { type = "bt.connected", mac = d.mac }
  end
  if topic == "/j/esp32/input/bt/state" then return { type = "bt.state", code = tonumber(payload) } end
  local sp = topic:match("^/j/spotify/input/([%w_]+)$")
  if sp then
    if sp == "position" or sp == "volume" then return { type = "spotify." .. sp, ms = tonumber(payload), value = tonumber(payload) } end
    if sp == "active" then return { type = "spotify.active", active = (payload == "true" or payload == "1") } end
    if sp == "new_preset" then return { type = "spotify.new_preset", raw = payload } end
    local d = jsonish(payload) or {}
    if sp == "now_playing" then return { type = "spotify.now_playing", data = d } end
    if sp == "login" then return { type = "spotify.login", username = d.username } end
    if sp == "set_cfg" then return { type = "spotify.set_cfg", shuffle_mode = d.shuffle_mode, repeat_mode = d.repeat_mode } end
    return { type = "spotify." .. sp }
  end
  local dz = topic:match("^/j/deezer/input/([%w_]+)$")
  if dz then
    if dz == "position" then return { type = "deezer.position", ms = tonumber(payload) } end
    if dz == "paused" then return { type = "deezer.paused", flag = tostring(payload) } end
    if dz == "now_pl" then return { type = "deezer.now_pl", uri = tostring(payload) } end
    if dz == "playlists" then return { type = "deezer.playlists", raw = payload } end
    local d = jsonish(payload) or {}
    if dz == "login" then return { type = "deezer.login", name = d.name, id = d.id } end
    if dz == "options" then return { type = "deezer.options", license = d.license } end
    if dz == "now_playing" then return { type = "deezer.now_playing", data = d } end
    return { type = "deezer." .. dz }
  end
  local dhcp = topic:match("^/j/net/dhcp/(%w+)$")
  if dhcp then return { type = "net.dhcp", event = dhcp } end
  if topic == "/j/event" then return { type = "system.event", name = tostring(payload) } end
  if topic == "/j/mender/shutdown_app" then return { type = "mender.shutdown" } end
  if topic == "/j/mender" then return { type = "mender", raw = tostring(payload) } end
  local v1 = topic:match("^/j/web/input/(.+)$")
  if v1 then return { type = "v1.cmd", name = v1, raw = payload } end
  return nil
end

--- Compose several translators: the first non-nil event wins.
function bus_events.chain(...)
  local fns = { ... }
  return function(topic, payload)
    for _, f in ipairs(fns) do
      local e = f(topic, payload)
      if e then return e end
    end
    return nil
  end
end

return bus_events
