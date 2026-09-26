-- services.device: the Jooki as a physical object.
-- Volume and its limits, headphones, toy-safe, buttons (with long presses and
-- the four-button combo), battery / charging / heat, inactivity power-off,
-- lights, and the power-off sequence. Owns:
--   state.audiocfg = { volume, headphones_en, shuffle_mode, repeat_mode }   (audiocfg.json, 1.x shape)
--   state.power    = { connected, charging, level = { mv, p, t }, warned_at }
--   state.limits   = { maxvol, fade, dim }   (set by bedtime; device applies them)
--   state.lights   = { ring, prev, next, circle }   (last colours sent; the simulator shows them)
--   state.device.toy_safe, state.device.ip, state.device.hostname, ...
--   state.activity = { last, buttons = { [name] = down_at } }
local device = {}

local LED = "/j/led/output/"
local COLOURS = { WHITE = { 200, 200, 200 }, BLACK = { 0, 0, 0 }, RED = { 200, 0, 0 }, GREEN = { 0, 200, 0 },
                  BLUE = { 0, 0, 200 }, YELLOW = { 200, 200, 0 }, ORANGE = { 200, 40, 0 }, LO_ORANGE = { 50, 10, 0 },
                  LIGHTBLUE = { 0, 10, 200 } }
device.COLOURS = COLOURS

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end
local function emit(t, extra)
  local e = { type = t }
  for k, v in pairs(extra or {}) do e[k] = v end
  return { kind = "emit", event = e }
end
local function cfg(doc, key, default)
  local c = doc.config or {}
  if c[key] ~= nil then return c[key] end
  return default
end

-- ------------------------------------------------------------------ volume
local function clamp(v) v = math.floor(tonumber(v) or 0) if v < 0 then return 0 elseif v > 100 then return 100 end return v end

--- What reaches the speaker: requested volume through the night limit and the fade.
function device.effective_volume(doc, requested)
  local v = clamp(requested)
  local lim = doc.limits or {}
  if lim.maxvol and lim.maxvol < 100 and v > lim.maxvol then v = lim.maxvol end
  if lim.fade and lim.fade < 1 then v = math.floor(v * lim.fade + 0.5) end
  return v
end

local function audiocfg_of(doc)
  local a = copy(doc.audiocfg or {})
  a.volume = a.volume or 40
  a.headphones_en = a.headphones_en == true
  a.shuffle_mode = a.shuffle_mode == true
  a.repeat_mode = a.repeat_mode or 1
  return a
end

local function audiocfg_path(doc) return cfg(doc, "data_dir", "/jooki/external/jooki") .. "/audiocfg.json" end

local function set_volume(doc, requested, persist)
  local a = audiocfg_of(doc)
  a.volume = clamp(requested)
  local cmds = { { kind = "host.volume", percent = device.effective_volume(doc, a.volume) } }
  if persist ~= false then cmds[#cmds + 1] = { kind = "files.write", path = audiocfg_path(doc), doc = a, version = 1 } end
  return { state = { audiocfg = a }, commands = cmds }
end
device.set_volume = set_volume

--- limits changed (bedtime): re-apply the current volume through the new chain.
function device.on_apply_volume(doc)
  local a = audiocfg_of(doc)
  return { commands = { { kind = "host.volume", percent = device.effective_volume(doc, a.volume) } } }
end

function device.on_gpio_volume(doc, ev)
  if ev.percent == nil then return nil end
  return set_volume(doc, ev.percent)
end

--- The ESP32's knob report (polled slowly): volume position and headphones.
function device.on_knobs(doc, ev)
  local a = audiocfg_of(doc)
  local r = { state = {}, commands = {} }
  if ev.volume ~= nil and clamp(ev.volume) ~= a.volume then
    local s = set_volume(doc, ev.volume)
    r.state.audiocfg = s.state.audiocfg
    for _, c in ipairs(s.commands) do r.commands[#r.commands + 1] = c end
  end
  if ev.headphones ~= nil and ev.headphones ~= a.headphones_en then
    local a2 = r.state.audiocfg or a
    a2.headphones_en = ev.headphones
    r.state.audiocfg = a2
    local dev = ev.headphones and "headphones" or "speaker"
    r.commands[#r.commands + 1] = { kind = "bus.publish", topic = "/j/audio/out/set_output_device", payload = dev }
    r.commands[#r.commands + 1] = { kind = "files.write_text", path = "/sys/kernel/htdrv/amp_en", text = ev.headphones and "0" or "1" }
  end
  if not next(r.state) and #r.commands == 0 then return nil end
  return r
end

-- ------------------------------------------------------------------ buttons (1.x keys module)
local LONG_CIRCLE_S, LONG_AIRPLANE_S = 2, 5
local COMBO = { "next", "prev", "vol_inc", "vol_dec" }

local function activity_of(doc)
  local a = copy(doc.activity or {})
  a.buttons = a.buttons or {}
  return a
end

local function all_down(buttons)
  for _, b in ipairs(COMBO) do if not buttons[b] then return false end end
  return true
end

function device.on_button(doc, ev)
  local act = activity_of(doc)
  act.last = ev.now
  local cmds = {}
  local name = ev.button
  if ev.down then
    act.buttons[name] = ev.now
    if all_down(act.buttons) then
      cmds[#cmds + 1] = { kind = "shell", action = "speak_info" }
      cmds[#cmds + 1] = emit("playback.pause_request", { source = "speak_info" })
      act.buttons = {}
    end
    -- airplane buttons are decided on release or by the long-press tick
    return { state = { activity = act }, commands = cmds }
  end
  -- release: circle short press does nothing (the long press is on the tick);
  -- hp_plugged is reported through the knob state
  local down_at = act.buttons[name]
  act.buttons[name] = nil
  if name == "airplane_release" then act.buttons.airplane_mode_on, act.buttons.airplane_mode_off = nil, nil end
  if not down_at then return { state = { activity = act }, commands = cmds } end
  if name == "next" then cmds[#cmds + 1] = emit("playback.next", {})
  elseif name == "prev" then cmds[#cmds + 1] = emit("playback.prev", {})
  elseif name == "vol_inc" or name == "vol_dec" then
    local a = audiocfg_of(doc)
    local s = set_volume(doc, a.volume + (name == "vol_inc" and 10 or -10))
    return { state = { activity = act, audiocfg = s.state.audiocfg }, commands = s.commands }
  end
  return { state = { activity = act }, commands = cmds }
end

--- Long presses are detected on the tick (like 1.x): circle 2 s -> power off, airplane 5 s.
function device.on_tick(doc, ev)
  local act = doc.activity
  if not act or not act.buttons then return nil end
  local now = ev.now
  local cmds = {}
  local changed = false
  local a2 = activity_of(doc)
  if act.buttons.circle and now - act.buttons.circle >= LONG_CIRCLE_S then
    a2.buttons.circle = nil; changed = true
    cmds[#cmds + 1] = emit("power.off_request", { reason = "button" })
  end
  for _, n in ipairs({ "airplane_mode_on", "airplane_mode_off" }) do
    if act.buttons[n] and now - act.buttons[n] >= LONG_AIRPLANE_S then
      a2.buttons[n] = nil; changed = true
      cmds[#cmds + 1] = emit("radio.set", { wifi = n == "airplane_mode_off", bt = n == "airplane_mode_off" })
    end
  end
  if not changed then return nil end
  return { state = { activity = a2 }, commands = cmds }
end

-- ------------------------------------------------------------------ power
local function power_of(doc)
  local p = copy(doc.power or {})
  p.level = p.level or { mv = 0, p = 0, t = 0 }
  return p
end

function device.on_battery(doc, ev)
  local p = power_of(doc)
  p.level = { mv = ev.mv or 0, p = ev.tenths or 0, t = ev.mc or 0 }
  local cmds = {}
  if (ev.mc or 0) > cfg(doc, "overheat_mc", 80000) then
    cmds[#cmds + 1] = { kind = "log", level = "error", key = "device.overheat", fields = { mc = ev.mc } }
    cmds[#cmds + 1] = emit("device.toy_safe_request", { enable = true })
    cmds[#cmds + 1] = { kind = "shell", action = "power_overheat" }
    local s = set_volume(doc, 80)
    for _, c in ipairs(s.commands) do cmds[#cmds + 1] = c end
    return { state = { power = p, audiocfg = s.state.audiocfg }, commands = cmds }
  end
  if not p.charging then
    local percent = (ev.tenths or 0) / 10
    if percent < cfg(doc, "battery_off_percent", 10) then
      cmds[#cmds + 1] = emit("system.event", { name = "Evt.Power.Low.Shutdown", after = { type = "power.off_request", reason = "battery" } })
    elseif percent < cfg(doc, "battery_warn_percent", 20) and (not p.warned_at or ev.now - p.warned_at >= 300) then
      p.warned_at = ev.now
      cmds[#cmds + 1] = emit("system.event", { name = "Evt.Power.Low.Warning" })
    end
  end
  return { state = { power = p }, commands = cmds }
end

function device.on_plugged(doc, ev)
  local p = power_of(doc)
  if p.connected == ev.on then return nil end
  local first = p.connected == nil
  p.connected = ev.on
  local cmds = {}
  if not first then
    cmds[#cmds + 1] = { kind = "files.write_text", path = "/sys/kernel/htdrv/usb_mux", text = (ev.on and not audiocfg_of(doc).headphones_en) and "0" or "1" }
    cmds[#cmds + 1] = emit("system.event", { name = ev.on and "Evt.Power.Cable.Insert" or "Evt.Power.Cable.Remove" })
  end
  return { state = { power = p }, commands = cmds }
end

function device.on_charging(doc, ev)
  local p = power_of(doc)
  if p.charging == ev.on then return nil end
  local first = p.charging == nil
  p.charging = ev.on
  if ev.on then p.warned_at = nil end
  local cmds = {}
  if not first and ev.on then cmds[#cmds + 1] = emit("system.event", { name = "Evt.Power.Charging" }) end
  return { state = { power = p }, commands = cmds }
end

--- Inactivity (every 30 s): 14 min -> warning lights, 15 min -> power off, unless kept awake.
function device.on_inactivity(doc, ev)
  if doc.flags and doc.flags.STAY_ON then return nil end
  local act = doc.activity or {}
  local pb = doc.playback or {}
  local playing = pb.state == "playing" or pb.state == "starting"
  local bt = doc.bluetooth and doc.bluetooth.connected_mac
  local plugged = doc.power and doc.power.connected
  if playing or bt or plugged then
    if act.last ~= ev.now then
      local a2 = activity_of(doc); a2.last = ev.now
      return { state = { activity = a2 } }
    end
    return nil
  end
  local idle = ev.now - (act.last or 0)
  if idle >= cfg(doc, "inactivity_off_s", 900) then
    return { commands = { { kind = "log", level = "info", key = "device.inactivity_off", fields = { idle_s = math.floor(idle) } },
                          emit("power.off_request", { reason = "inactivity" }) } }
  end
  if idle >= cfg(doc, "inactivity_warn_s", 840) and not act.warned then
    local a2 = activity_of(doc); a2.warned = true
    return { state = { activity = a2 }, commands = { emit("lights.event", { name = "Evt.Power.Inactivity.Warning" }) } }
  end
  return nil
end

--- Anything the child or a page does keeps the Jooki awake.
function device.on_activity(doc, ev)
  local a2 = activity_of(doc)
  if a2.last == ev.now and not a2.warned then return nil end
  a2.last, a2.warned = ev.now, nil
  return { state = { activity = a2 } }
end

-- ------------------------------------------------------------------ power off
function device.on_off_request(_, ev)
  return { commands = { emit("system.event", { name = "Evt.Jooki.Poweroff", after = { type = "shutdown.request", reason = ev.reason } }) } }
end

function device.on_shutdown_request(doc, ev)
  local a = audiocfg_of(doc)
  local cmds = {
    { kind = "files.write", path = audiocfg_path(doc), doc = a, version = 1 },
    { kind = "bus.publish", topic = LED .. "set_raw", payload = "ALL,0,0,0" },
    { kind = "bus.publish", topic = LED .. "set_raw", payload = "CIRCLE,200,0,0" },
    { kind = "bus.publish", topic = "/j/all/quit", payload = '"from-player"' },
    { kind = "shell", action = "sync" },
  }
  if ev.reason ~= "signal" then cmds[#cmds + 1] = { kind = "shell", action = "poweroff" } end
  cmds[#cmds + 1] = { kind = "shutdown", reason = ev.reason or "requested" }
  return { commands = cmds }
end

-- ------------------------------------------------------------------ toy safe, radio, wifi
function device.on_toy_safe(doc, ev)
  local d = copy(doc.device or {})
  d.toy_safe = ev.enable == true
  local flags = copy(doc.flags or {})
  flags.TOY_SAFE_OFF = (not d.toy_safe) or nil
  return { state = { device = d, flags = flags }, commands = {
    { kind = "files.flag", name = "TOY_SAFE_OFF", set = not d.toy_safe },
    { kind = "shell", action = "toysafe_update" },
    { kind = "bus.publish", topic = "/j/esp32/output/audio/set_toysafe", payload = d.toy_safe and "1" or "0" },
    emit("lights.event", { name = d.toy_safe and "Evt.ToySafe.On" or "Evt.ToySafe.Off" }) } }
end

function device.on_radio(doc, ev)
  local flags = copy(doc.flags or {})
  flags.WIFI_OFF = (ev.wifi == false) or nil
  flags.BT_OFF = (ev.bt == false) or nil
  local name = (ev.wifi and ev.bt) and "Evt.Airplane.Disable" or ((ev.wifi == false and ev.bt == false) and "Evt.Airplane.Enable" or "Evt.Airplane.Change")
  return { state = { flags = flags }, commands = {
    { kind = "files.flag", name = "WIFI_OFF", set = ev.wifi == false }, { kind = "files.flag", name = "BT_OFF", set = ev.bt == false },
    { kind = "shell", action = "radio", args = { wifi = ev.wifi ~= false, bt = ev.bt ~= false } },
    emit("lights.event", { name = name }) } }
end

-- ------------------------------------------------------------------ lights (1.x language, 1.3 dimming)
local function dimmed(doc, c)
  local lim = doc.limits or {}
  if not lim.dim then return c end
  local out = {}
  for i = 1, 3 do out[i] = c[i] > 0 and math.max(1, math.floor(c[i] * 0.05 + 0.5)) or 0 end
  return out
end
local function set(doc, group, colour) return { kind = "bus.publish", topic = LED .. "set_raw", payload = group .. "," .. table.concat(dimmed(doc, colour), ",") } end
local function pulse(doc, group, colour, n) return { kind = "bus.publish", topic = LED .. "pulse_raw", payload = group .. "," .. table.concat(dimmed(doc, colour), ",") .. "," .. (n or 1) .. ",500,0.5" } end

local function wifi_lights(doc)
  local w = doc.net or {}
  local assoc, ip = w.connected, (w.ip and w.ip ~= "")
  return { set(doc, "PREV", assoc and COLOURS.WHITE or COLOURS.ORANGE), set(doc, "NEXT", ip and COLOURS.WHITE or COLOURS.ORANGE) }
end

--- Idle/playing ring + Wi-Fi dots, recomputed on playback and network changes.
function device.on_lights_refresh(doc)
  local pb = doc.playback or {}
  local cmds = {}
  if pb.state == "starting" then
    cmds[#cmds + 1] = set(doc, "PREV", COLOURS.LIGHTBLUE); cmds[#cmds + 1] = set(doc, "NEXT", COLOURS.LIGHTBLUE)
    return { commands = cmds }
  end
  local ring = COLOURS.WHITE
  if pb.state == "playing" and doc.nfc and doc.nfc.tagId then ring = COLOURS.BLACK end   -- 1.x: the ring goes off while a token plays
  cmds[#cmds + 1] = set(doc, "RING", ring)
  for _, c in ipairs(wifi_lights(doc)) do cmds[#cmds + 1] = c end
  return { commands = cmds }
end

local EVENT_LIGHTS = {
  ["Evt.Character.Detect"] = function(doc) return { set(doc, "PREV", COLOURS.LIGHTBLUE), set(doc, "NEXT", COLOURS.LIGHTBLUE) } end,
  ["Evt.Character.Write"] = function(doc) return { pulse(doc, "PREV", COLOURS.GREEN, 8), pulse(doc, "NEXT", COLOURS.GREEN, 8) } end,
  ["Evt.Mobile.connect"] = function(doc) return { pulse(doc, "PREV", COLOURS.LIGHTBLUE, 1), pulse(doc, "NEXT", COLOURS.LIGHTBLUE, 1) } end,
}
local ERROR_EVENTS = { ["Evt.Character.Detect.Empty"] = true, ["Evt.Disk.FullError"] = true, ["Evt.Spotify.PlayError"] = true,
                       ["Evt.Spotify.NoLoginError"] = true, ["Evt.Deezer.PlayError"] = true, ["Evt.Deezer.NoLoginError"] = true }
local WARN_EVENTS = { ["Evt.ToySafe.On"] = true, ["Evt.ToySafe.Off"] = true, ["Evt.Factory.Enable"] = true, ["Evt.Factory.Disable"] = true,
                      ["Evt.Power.Low.Warning"] = true, ["Evt.Power.Inactivity.Warning"] = true, ["Evt.Airplane.Enable"] = true }

function device.on_lights_event(doc, ev)
  local f = EVENT_LIGHTS[ev.name]
  if f then return { commands = f(doc) } end
  if ERROR_EVENTS[ev.name] then return { commands = { pulse(doc, "PREV", COLOURS.RED, 2), pulse(doc, "NEXT", COLOURS.RED, 2) } } end
  if WARN_EVENTS[ev.name] then return { commands = { pulse(doc, "PREV", COLOURS.YELLOW, 1), pulse(doc, "NEXT", COLOURS.YELLOW, 1) } } end
  return nil
end

-- ------------------------------------------------------------------ disk usage (after uploads and at boot)
function device.on_disk_request(doc)
  return { commands = { { kind = "shell", action = "df", args = { dir = cfg(doc, "data_dir", "/jooki/external/jooki") }, reply = "device.df" } } }
end

--- df -k output -> diskUsage { used, available (minus a 10 MB reserve), total, usedPercent } in KiB, like 1.x
function device.on_df(doc, ev)
  if ev.rc ~= 0 or not ev.out then return nil end
  local used, avail = tostring(ev.out):match("%s+(%d+)%s+(%d+)%s+%d+%%")
  used, avail = tonumber(used), tonumber(avail)
  if not used or not avail then return nil end
  local d = copy(doc.device or {})
  d.diskUsage = { used = used, available = math.max(avail - 10 * 1024, 0), total = used + avail, usedPercent = math.ceil(100 * used / math.max(used + avail, 1)) }
  return { state = { device = d } }
end

-- ------------------------------------------------------------------ boot / api
function device.on_boot(doc, ev)
  local a = audiocfg_of({ audiocfg = ev.audiocfg })
  local flags = ev.flags or {}
  local d = copy(doc.device or {})
  d.toy_safe = not flags.TOY_SAFE_OFF
  local cmds = {
    { kind = "host.volume", percent = device.effective_volume(doc, a.volume) },
    { kind = "bus.publish", topic = "/j/audio/out/set_output_device", payload = "speaker" },
    { kind = "bus.publish", topic = "/j/esp32/output/device/send_all_notifications", payload = "" },
    { kind = "bus.publish", topic = "/j/esp32/output/nfc/mode/set", payload = "1" },
    { kind = "bus.publish", topic = "/j/esp32/output/knobs/state", payload = "" },
    { kind = "timer.every", name = "device.inactivity", seconds = 30 },
    { kind = "timer.every", name = "device.tick", seconds = 0.5 },
    { kind = "timer.every", name = "device.knobs", seconds = 10 },
    emit("system.event", { name = "Evt.Jooki.Ready" }),
  }
  return { state = { audiocfg = a, flags = flags, device = d, power = { level = { mv = 0, p = 0, t = 0 } }, activity = { last = ev.now or 0, buttons = {} },
                     limits = { maxvol = 100, fade = 1, dim = false } }, commands = cmds }
end

function device.on_timer(doc, ev)
  if ev.name == "device.inactivity" then return device.on_inactivity(doc, ev) end
  if ev.name == "device.tick" then return device.on_tick(doc, ev) end
  if ev.name == "device.knobs" then return { commands = { { kind = "bus.publish", topic = "/j/esp32/output/knobs/state", payload = "" } } } end
  return nil
end

local S = {}
S.volume = { type = "object", required = { "percent" }, properties = { percent = { type = "integer", minimum = 0, maximum = 100 } }, additionalProperties = false }
S.config = { type = "object", properties = { shuffle_mode = { type = "boolean" }, repeat_mode = { type = "integer", minimum = 0, maximum = 2 } }, additionalProperties = false }
S.enable = { type = "object", required = { "enable" }, properties = { enable = { type = "boolean" } }, additionalProperties = false }
S.wifi = { type = "object", required = { "ssid" }, properties = { ssid = { type = "string", minLength = 1, maxLength = 32 }, password = { type = "string", maxLength = 63 } }, additionalProperties = false }
device.schemas = S

function device.install(api, dispatch)
  dispatch.on("boot", "device", device.on_boot)
  dispatch.on("timer", "device", device.on_timer)
  dispatch.on("gpio.volume", "device", device.on_gpio_volume)
  dispatch.on("gpio.button", "device", device.on_button)
  dispatch.on("knobs", "device", device.on_knobs)
  dispatch.on("power.battery", "device", device.on_battery)
  dispatch.on("power.plugged", "device", device.on_plugged)
  dispatch.on("power.charging", "device", device.on_charging)
  dispatch.on("power.off_request", "device", device.on_off_request)
  dispatch.on("shutdown.request", "device", device.on_shutdown_request)
  dispatch.on("host.terminating", "device", function(doc) return device.on_shutdown_request(doc, { reason = "signal" }) end)
  dispatch.on("device.toy_safe_request", "device", device.on_toy_safe)
  dispatch.on("radio.set", "device", device.on_radio)
  dispatch.on("volume.apply", "device", device.on_apply_volume)
  dispatch.on("lights.event", "device", device.on_lights_event)
  dispatch.on("playback.changed", "device", device.on_lights_refresh)
  dispatch.on("net.status", "device", device.on_lights_refresh)
  dispatch.on("limits.changed", "device", function(doc)
    local r = device.on_apply_volume(doc)
    for _, c in ipairs(device.on_lights_refresh(doc).commands) do r.commands[#r.commands + 1] = c end
    return r
  end)
  dispatch.on("upload.done", "device", device.on_disk_request)
  dispatch.on("boot", "device.disk", device.on_disk_request)
  dispatch.on("device.df", "device", device.on_df)
  for _, t in ipairs({ "nfc.tag", "api.cmd", "v1.cmd", "playback.request" }) do dispatch.on(t, "device", device.on_activity) end
  dispatch.on("system.tag", "device", function(doc, ev)
    if ev.name == "sys.toy_safe_on" then return device.on_toy_safe(doc, { enable = true }) end
    if ev.name == "sys.toy_safe_off" then return device.on_toy_safe(doc, { enable = false }) end
    if ev.name == "sys.airplane_mode_on" then return device.on_radio(doc, { wifi = false, bt = false }) end
    if ev.name == "sys.airplane_mode_off" then return device.on_radio(doc, { wifi = true, bt = true }) end
    if ev.name == "sys.wifi_on" then return device.on_radio(doc, { wifi = true }) end
    if ev.name == "sys.wifi_off" then return device.on_radio(doc, { wifi = false }) end
    if ev.name == "sys.bt_on" then return device.on_radio(doc, { bt = true }) end
    if ev.name == "sys.bt_off" then return device.on_radio(doc, { bt = false }) end
    return { commands = { { kind = "log", level = "warn", key = "device.system_tag_ignored", fields = { name = ev.name } } } }
  end)
  api.command("device.set_volume", S.volume, function(doc, p) return set_volume(doc, p.percent) end)
  api.command("device.set_config", S.config, function(doc, p)
    local a = audiocfg_of(doc)
    if p.shuffle_mode ~= nil then a.shuffle_mode = p.shuffle_mode end
    if p.repeat_mode ~= nil then a.repeat_mode = p.repeat_mode end
    return { state = { audiocfg = a }, commands = { { kind = "files.write", path = audiocfg_path(doc), doc = a, version = 1 },
                                                   emit("audiocfg.changed", { shuffle_mode = p.shuffle_mode, repeat_mode = p.repeat_mode }) } }
  end)
  dispatch.on("device.set_config_request", "device", function(doc, ev)
    local a = audiocfg_of(doc)
    if ev.shuffle_mode ~= nil then a.shuffle_mode = ev.shuffle_mode == true end
    if ev.repeat_mode ~= nil then a.repeat_mode = tonumber(ev.repeat_mode) or a.repeat_mode end
    return { state = { audiocfg = a }, commands = { { kind = "files.write", path = audiocfg_path(doc), doc = a, version = 1 } } }
  end)
  api.command("device.toy_safe", S.enable, function(doc, p) return device.on_toy_safe(doc, { enable = p.enable }) end)
  api.command("device.power_off", nil, function(_, _, ev) return device.on_off_request(nil, { reason = "page", now = ev.now }) end)
  api.command("device.set_wifi", S.wifi, function(_, p) return { commands = { { kind = "shell", action = "wifi_add", args = { ssid = p.ssid, password = p.password, lang = "EN" } } } } end)
  api.command("device.speak_info", nil, function() return { commands = { { kind = "shell", action = "speak_info" }, emit("playback.pause_request", { source = "speak_info" }) } } end)
end

return device
