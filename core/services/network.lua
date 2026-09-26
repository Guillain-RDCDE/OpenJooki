-- services.network: what the page needs to know about the Wi-Fi, and the
-- Jooki's name on the network (docs/20). The Wi-Fi manager (safe switch,
-- preferred networks) is 2.1.
-- Owns state.net = { ssid, bssid, channel, signal, connected, ip, ap, drops, beacons, name, since }
--      state.bluetooth = { connected_mac, devices }
-- Reads /tmp/oj-wifi.log (Wi-Fi events copied there by syslog-ng, see
-- tools/openjooki/system/syslog-ng.conf) every 20 s; cleans the logs the
-- original system piled up, once at boot.
local network = {}

local WIFI_LOG = "/tmp/oj-wifi.log"

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end

--- Count drops / beacon losses and find the last access point in the Wi-Fi log text.
function network.read_wifi_log(txt)
  local drops, beacons, ap = 0, 0, nil
  for line in (txt or ""):gmatch("[^\n]+") do
    if line:find("wifi:state: run -> init", 1, true) then drops = drops + 1
    elseif line:find("bcn_timout", 1, true) then beacons = beacons + 1 end
    local a = line:match("wifi:connected with (.-), aid")
    if a then ap = a end
  end
  return drops, beacons, ap
end

function network.on_boot(doc, ev)
  local host = ((doc.device or {}).hostname or ""):lower():gsub("%.local$", "")
  local net = { drops = 0, beacons = 0, since = ev.now or 0, name = host ~= "" and (host .. ".local") or nil }
  return { state = { net = net },
           commands = { { kind = "shell", action = "log_cleanup" },
                        { kind = "timer.every", name = "network.wifi_log", seconds = 20 },
                        { kind = "timer.every", name = "network.status", seconds = 30 },   -- 1.x asked every 10 s
                        { kind = "files.read_text", path = WIFI_LOG, reply = "network.wifi_log" } } }
end

function network.on_status(doc, ev)
  local net = copy(doc.net or {})
  net.ssid, net.bssid, net.channel, net.signal, net.connected, net.ip = ev.ssid, ev.bssid, ev.channel, ev.signal, ev.connected, ev.ip
  if ev.connected and type(ev.ssid) == "string" then net.ap = ev.ssid end
  return { state = { net = net } }
end

function network.on_timer(_, ev)
  if ev.name == "network.status" then
    return { commands = { { kind = "bus.publish", topic = "/j/esp32/output/net/sta/status", payload = "" } } }
  end
  if ev.name ~= "network.wifi_log" then return nil end
  return { commands = { { kind = "files.read_text", path = WIFI_LOG, reply = "network.wifi_log" } } }
end

function network.on_wifi_log(doc, ev)
  local drops, beacons, ap = network.read_wifi_log(ev.text)
  local net = copy(doc.net or {})
  if doc.net and doc.net.connected and type(doc.net.ssid) == "string" then ap = doc.net.ssid end
  if net.drops == drops and net.beacons == beacons and net.ap == ap then return nil end
  net.drops, net.beacons, net.ap = drops, beacons, ap
  return { state = { net = net } }
end

function network.on_bt_connected(doc, ev)
  return { state = { bluetooth = { connected_mac = ev.mac, devices = (doc.bluetooth or {}).devices } } }
end

function network.on_bt_state(doc, ev)
  if ev.code ~= 9 then return nil end
  return { state = { bluetooth = { connected_mac = nil, devices = (doc.bluetooth or {}).devices } } }
end

function network.install(_, dispatch)
  dispatch.on("boot", "network", network.on_boot)
  dispatch.on("net.status", "network", network.on_status)
  dispatch.on("timer", "network", network.on_timer)
  dispatch.on("network.wifi_log", "network", network.on_wifi_log)
  dispatch.on("bt.connected", "network", network.on_bt_connected)
  dispatch.on("bt.state", "network", network.on_bt_state)
end

return network
