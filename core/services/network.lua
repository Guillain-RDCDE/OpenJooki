-- services.network: what the page needs to know about the Wi-Fi, and the
-- Jooki's name on the network (docs/20). The Wi-Fi manager (safe switch,
-- preferred networks) is 2.1.
-- Owns state.net = { ssid, bssid, channel, signal, connected, ip, ap, drops, beacons, name, since }
-- (state.bluetooth belongs to services.bluetooth)
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
  -- restarts in a row the Wi-Fi watchdog already made (read by main from /data)
  local count = tonumber(tostring(ev.wifi_watchdog or ""):match("%d+")) or 0
  return { state = { net = net, net_watch = { count = count } },
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

-- ------------------------------------------------------------------ Wi-Fi watchdog
-- The Wi-Fi chip can stay stuck ("connecting" for good, 28/09/2026) and nothing on the original
-- system starts it again: the Jooki stays unreachable until someone restarts it. A restart is what
-- brings it back, so the core does it itself, only when it is safe:
--   * offline for wifi_watchdog_s (10 min) in a row, radios supposed on (no airplane mode);
--   * nothing playing, on the charger (on battery the Jooki switches itself off after 15 min anyway,
--     and its next start is a fresh one);
--   * at most wifi_watchdog_max (2) restarts in a row without Wi-Fi: then it stops trying (moved
--     house, box gone: the Bluetooth page is the way). The count lives on /data and goes back to 0
--     as soon as the Wi-Fi is back. The restart is silent (no "ready" chime at night).
-- online = the chip says so AND Linux has a default route: on 29/09 the chip reported its address
-- while Linux had never set the interface up (unreachable 40 min, and the watchdog believed the chip)
local function online(net) return net and net.connected and type(net.ip) == "string" and net.ip ~= "" and net.route ~= false end
local ROUTES = "/proc/net/route"
function network.on_route(doc, ev)
  local has = (ev.text or ""):find("\n%S+\t00000000\t") ~= nil
  if doc.net and doc.net.route == has then return nil end
  local net = copy(doc.net or {}); net.route = has
  return { state = { net = net } }
end
local function radios_off(doc)
  local f, d = doc.flags or {}, doc.device or {}
  return f.WIFI_OFF or f.OJ_AIRPLANE or type(d.airplane) == "table"
end

function network.watchdog(doc, now)
  local config = require("kernel.config")
  local limit, max = config.get("wifi_watchdog_s"), config.get("wifi_watchdog_max")
  local w = copy(doc.net_watch or { count = 0 })
  if online(doc.net) then
    local cmds = {}
    -- once per start, a minute after the Wi-Fi is up: forget the factory network (never at start:
    -- writing the chip's list while it connects disturbs it)
    if not w.factory_done then
      w.online_at = w.online_at or now
      if now - w.online_at >= 60 then
        w.factory_done = true
        cmds[#cmds + 1] = { kind = "shell", action = "wifi_forget_factory" }
      end
    end
    if not w.since and (w.count or 0) == 0 then return { state = { net_watch = w }, commands = cmds } end
    if (w.count or 0) > 0 then
      cmds[#cmds + 1] = { kind = "files.write_text", path = config.get("wifi_watchdog_file"), text = "0\n" }
      cmds[#cmds + 1] = { kind = "log", level = "info", key = "network.watchdog_ok", fields = { after_restarts = w.count } }
    end
    w.since, w.count = nil, 0
    return { state = { net_watch = w }, commands = cmds }
  end
  -- the minute before forgetting the factory network counts from a stable Wi-Fi
  local dropped = w.online_at ~= nil
  w.online_at = nil
  local keep = dropped and { state = { net_watch = w } } or nil
  if radios_off(doc) or limit <= 0 then
    if w.since then w.since = nil return { state = { net_watch = w } } end
    return keep
  end
  if not w.since then w.since = now return { state = { net_watch = w } } end
  if now - w.since < limit then return keep end
  local pb = doc.playback or {}
  local busy = pb.state == "playing" or pb.state == "starting" or (pb.sys and pb.sys.name)
  local plugged = doc.power and doc.power.connected
  if busy or not plugged or (w.count or 0) >= max then return keep end
  w.count = (w.count or 0) + 1
  w.since = nil
  return { state = { net_watch = w }, commands = {
    { kind = "log", level = "warn", key = "network.watchdog_restart", fields = { offline_s = math.floor(now - (doc.net_watch.since or now)), restart = w.count } },
    { kind = "files.write_text", path = config.get("wifi_watchdog_file"), text = w.count .. "\n" },
    { kind = "files.write_text", path = config.get("quiet_boot_file"), text = "wifi watchdog\n" },
    { kind = "shell", action = "watchdog_reboot" } } }
end

function network.on_timer(doc, ev)
  if ev.name == "network.status" then
    local r = network.watchdog(doc, ev.now or 0) or { commands = {} }
    r.commands = r.commands or {}
    table.insert(r.commands, 1, { kind = "bus.publish", topic = "/j/esp32/output/net/sta/status", payload = "" })
    table.insert(r.commands, 2, { kind = "files.read_text", path = ROUTES, reply = "network.route" })
    return r
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

function network.install(_, dispatch)
  dispatch.on("boot", "network", network.on_boot)
  dispatch.on("net.status", "network", network.on_status)
  dispatch.on("timer", "network", network.on_timer)
  dispatch.on("network.wifi_log", "network", network.on_wifi_log)
  dispatch.on("network.route", "network", network.on_route)
end

return network
