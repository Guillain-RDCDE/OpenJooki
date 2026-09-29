-- services.bluetooth: play through a Bluetooth speaker or headphones (docs/26).
-- The ESP32 does it all (A2DP source, pairing, reconnection); the original app
-- never offered it. We only drive esp32_ctrl on the bus:
--   start_scan  -> device_discovered {name, mac, rssi, cod}, a burst per device
--   connect_device "MAC<TAB>0xCOD<TAB>name" (tabs, not JSON) -> state 4 then 5
--   set_autoconnect "true"|"false"   (the chip reconnects to the last speaker by itself)
--   forget_device "MAC"              (refused while autoconnect is on)
--   get_state   -> state N (+ device_connected when connected)
-- The chip says nothing when a speaker goes away or comes back, so we ask every 30 s;
-- nor does it always end a search, so a search lasts 20 s on our clock.
-- Owns state.bluetooth = { state, connected_mac, connected = {mac, name}, known = {...} (remembered
--                          by the chip), devices = {...} (last search), auto, scanning }
local bluetooth = {}

local OUT = "/j/esp32/output/bt/"
local MAX_DEVICES = 12
-- states of the chip: 0 idle, 1 scanning, 2 scan ended, 3 scan failed, 4 connecting,
-- 5 connected, 6 connect failed, 7 forgotten, 8 forget failed, 9 disconnected
local NOT_CONNECTED = { [0] = true, [6] = true, [7] = true, [9] = true }

local function pub(what, payload) return { kind = "bus.publish", topic = OUT .. what, payload = payload or "" } end

local function copy(b)
  local out = {}
  for k, v in pairs(b or {}) do out[k] = v end
  out.devices, out.known = {}, {}
  for i, d in ipairs((b or {}).devices or {}) do out.devices[i] = d end
  for i, d in ipairs((b or {}).known or {}) do out.known[i] = d end
  return out
end

--- Add or refresh one device in a list; false when nothing changed.
local function upsert(list, ev)
  local dev = { mac = ev.mac, name = ev.name, cod = ev.cod }
  for i, d in ipairs(list) do
    if d.mac == ev.mac then
      if d.name == ev.name and d.cod == ev.cod then return false end
      list[i] = dev; return true
    end
  end
  if #list >= MAX_DEVICES then return false end
  list[#list + 1] = dev; return true
end

--- Audio devices only (speakers, headphones, car kits): major class 0x04 of the class of device.
function bluetooth.is_audio(cod)
  return type(cod) == "number" and math.floor(cod / 256) % 32 == 4
end

function bluetooth.on_boot()
  return { state = { bluetooth = { state = 0, devices = {}, known = {} } },
           commands = { pub("get_state"), { kind = "timer.every", name = "bluetooth.poll", seconds = 30 } } }
end

function bluetooth.on_timer(doc, ev)
  if ev.name == "bluetooth.poll" then return { commands = { pub("get_state") } } end
  if ev.name ~= "bluetooth.scan_end" then return nil end
  local b = copy(doc.bluetooth)
  b.scanning = nil
  if b.state == 1 then b.state = 2 end
  return { state = { bluetooth = b } }
end

function bluetooth.on_state(doc, ev)
  local b = copy(doc.bluetooth)
  local code = ev.code
  -- the chip does not always say a search ended, and keeps answering "searching": our 20 s window decides
  if code == 1 and not b.scanning then code = 2 end
  if b.state == code and not (NOT_CONNECTED[code] and b.connected_mac) then return nil end
  b.state = code
  if NOT_CONNECTED[code] then b.connected_mac, b.connected = nil, nil end
  return { state = { bluetooth = b } }
end

function bluetooth.on_connected(doc, ev)
  local b = copy(doc.bluetooth)
  local cmds = {}
  -- once a speaker answers, let the chip reconnect to it by itself (after a restart, when it comes back)
  if b.auto ~= true then b.auto = true; cmds[1] = pub("set_autoconnect", "true") end
  local new = upsert(b.known, ev)   -- the chip remembers it from now on
  if b.connected_mac == ev.mac and b.state == 5 and #cmds == 0 and not new then return nil end
  b.state, b.connected_mac, b.connected = 5, ev.mac, { mac = ev.mac, name = ev.name }
  return { state = { bluetooth = b }, commands = cmds }
end

--- The speakers the chip remembers (one message each, answer to get_state). A paired speaker
--- does not show in a search unless it is in pairing mode, but reconnecting to it needs no pairing mode.
function bluetooth.on_saved(doc, ev)
  local b = copy(doc.bluetooth)
  if not upsert(b.known, ev) then return nil end
  return { state = { bluetooth = b } }
end

--- One discovered device: kept only when it is new or its name just arrived (the chip repeats each one many times).
function bluetooth.on_discovered(doc, ev)
  if not bluetooth.is_audio(ev.cod) then return nil end
  local b = copy(doc.bluetooth)
  for _, d in ipairs(b.devices) do
    if d.mac == ev.mac and (d.name ~= "" or ev.name == "") then return nil end   -- known, or no name yet
  end
  if not upsert(b.devices, ev) then return nil end
  return { state = { bluetooth = b } }
end

-- ------------------------------------------------------------------ page commands
local function bad(field, message) return nil, { code = "invalid_argument", field = field, message = message } end
local function valid_mac(m) return type(m) == "string" and m:upper():match("^%x%x:%x%x:%x%x:%x%x:%x%x:%x%x$") ~= nil end

function bluetooth.on_scan(doc)
  local b = copy(doc.bluetooth)
  b.devices, b.state, b.scanning = {}, 1, true
  return { state = { bluetooth = b }, commands = { pub("start_scan"), { kind = "timer.once", name = "bluetooth.scan_end", seconds = 20 } } }
end

function bluetooth.on_connect(doc, p)
  if not valid_mac(p.mac) then return bad("mac", "invalid mac") end
  local mac = p.mac:upper()
  local dev
  for _, d in ipairs((doc.bluetooth or {}).known or {}) do if d.mac == mac then dev = d end end
  for _, d in ipairs((doc.bluetooth or {}).devices or {}) do if d.mac == mac then dev = d end end
  if not dev then return nil, { code = "not_found", field = "mac", message = "unknown Bluetooth device" } end
  local b = copy(doc.bluetooth)
  b.state, b.auto = 4, false
  -- autoconnect off first, so the chip does not fight us for the previous speaker
  return { state = { bluetooth = b },
           commands = { pub("set_autoconnect", "false"),
                        pub("connect_device", string.format("%s\t0x%08X\t%s", mac, dev.cod or 0, (dev.name or ""):gsub("[\t\r\n]", " "))) } }
end

function bluetooth.on_forget(doc, p)
  if not valid_mac(p.mac) then return bad("mac", "invalid mac") end
  local b = copy(doc.bluetooth)
  b.auto, b.connected_mac, b.connected = false, nil, nil
  for i, d in ipairs(b.known) do if d.mac == p.mac:upper() then table.remove(b.known, i) break end end
  -- the chip refuses to forget while it may reconnect by itself
  return { state = { bluetooth = b }, commands = { pub("set_autoconnect", "false"), pub("forget_device", p.mac:upper()) } }
end

function bluetooth.install(_, dispatch)
  dispatch.on("boot", "bluetooth", bluetooth.on_boot)
  dispatch.on("timer", "bluetooth", bluetooth.on_timer)
  dispatch.on("bt.state", "bluetooth", bluetooth.on_state)
  dispatch.on("bt.connected", "bluetooth", bluetooth.on_connected)
  dispatch.on("bt.discovered", "bluetooth", bluetooth.on_discovered)
  dispatch.on("bt.saved", "bluetooth", bluetooth.on_saved)
end

return bluetooth
