-- services.device.radio: toy-safe, the radios (Wi-Fi, Bluetooth), airplane mode and its boot
-- restore, and the system tags that drive them. Owns:
--   state.device.toy_safe, state.device.airplane   (false = none; a table = one is running)
--   state.flags = { TOY_SAFE_OFF, WIFI_OFF, BT_OFF, OJ_AIRPLANE, STAY_ON, ... }   (the files on /data/mode, read at boot)
-- Installed by services.device (the facade), which re-exports its handlers.
local util = require("services.util")
local radio = {}

local copy, emit, err = util.copy, util.emit, util.err

-- ------------------------------------------------------------------ toy safe, radio, wifi
function radio.on_toy_safe(doc, ev)
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

--- radio.set { wifi?, bt?, bounded? }: the knob (held 5 s) and the system tokens switch the radios
--- for good — the ESP32 remembers airplane mode across restarts, and the way back is a knob
--- gesture few owners know. A change that is not `bounded` therefore also ends any airplane
--- mode the page had started (its timer and its boot flag go).
function radio.on_radio(doc, ev)
  local flags = copy(doc.flags or {})
  flags.WIFI_OFF = (ev.wifi == false) or nil
  flags.BT_OFF = (ev.bt == false) or nil
  local name = (ev.wifi and ev.bt) and "Evt.Airplane.Disable" or ((ev.wifi == false and ev.bt == false) and "Evt.Airplane.Enable" or "Evt.Airplane.Change")
  local cmds = {
    { kind = "files.flag", name = "WIFI_OFF", set = ev.wifi == false }, { kind = "files.flag", name = "BT_OFF", set = ev.bt == false },
    { kind = "shell", action = "radio", args = { wifi = ev.wifi ~= false, bt = ev.bt ~= false } },
    emit("lights.event", { name = name }) }
  local r = { state = { flags = flags }, commands = cmds }
  if not ev.bounded then
    flags.OJ_AIRPLANE = nil
    local d = copy(doc.device or {})
    if d.airplane ~= false then
      d.airplane = false
      r.state.device = d
      cmds[#cmds + 1] = { kind = "files.flag", name = "OJ_AIRPLANE", set = false }
      cmds[#cmds + 1] = { kind = "timer.cancel", name = "device.airplane" }
    end
  end
  return r
end

-- ------------------------------------------------------------------ airplane mode from the page (always bounded)
-- Parents ask for the airplane button the Muuselabs app had (no radio near the bed, or on a
-- plane). From the page it is only ever bounded: for a number of minutes (a timer switches the
-- radios back on) and, whatever happens, until the next start: the flag OJ_AIRPLANE on /data/mode
-- marks it, and at boot the core sees the flag, switches the radios back on and drops it. So a
-- Jooki can never be left with its two side dots orange for good by a tap on the page.
local AIRPLANE_MAX_MIN = 24 * 60
local AIRPLANE_BOOT_RESTORE_S = 3      -- after boot: let the ready chime and the ESP32 orders go first

--- device.airplane { minutes? (1-1440, or none = until the next start) | cancel = true }
function radio.on_airplane(doc, p, ev)
  if p.cancel then return radio.on_radio(doc, { wifi = true, bt = true }) end
  local minutes
  if p.minutes ~= nil then
    minutes = tonumber(p.minutes)
    if not minutes or minutes < 1 or minutes > AIRPLANE_MAX_MIN then
      return nil, err("invalid_argument", "minutes", "invalid duration (1 to " .. AIRPLANE_MAX_MIN .. " minutes)")
    end
    minutes = math.floor(minutes)
  end
  local r = radio.on_radio(doc, { wifi = false, bt = false, bounded = true })
  local d = copy(doc.device or {})
  d.airplane = { ends = minutes and ((ev.wall or 0) + minutes * 60) or nil, boot = true }
  r.state.device = d
  r.state.flags.OJ_AIRPLANE = true
  local cmds = r.commands
  cmds[#cmds + 1] = { kind = "files.flag", name = "OJ_AIRPLANE", set = true }
  if minutes then cmds[#cmds + 1] = { kind = "timer.once", name = "device.airplane", seconds = minutes * 60 }
  else cmds[#cmds + 1] = { kind = "timer.cancel", name = "device.airplane" } end
  cmds[#cmds + 1] = { kind = "log", level = "info", key = "device.airplane", fields = { minutes = minutes or "boot" } }
  return r
end

--- The timer (or the boot flag) is over: the radios come back, the flag goes.
function radio.on_airplane_end(doc, why)
  local r = radio.on_radio(doc, { wifi = true, bt = true })
  r.commands[#r.commands + 1] = { kind = "log", level = "info", key = "device.airplane_end", fields = { why = why } }
  return r
end

--- The system tokens (services.tokens: sys.*) that switch toy-safe and the radios.
function radio.on_system_tag(doc, ev)
  if ev.name == "sys.toy_safe_on" then return radio.on_toy_safe(doc, { enable = true }) end
  if ev.name == "sys.toy_safe_off" then return radio.on_toy_safe(doc, { enable = false }) end
  if ev.name == "sys.airplane_mode_on" then return radio.on_radio(doc, { wifi = false, bt = false }) end
  if ev.name == "sys.airplane_mode_off" then return radio.on_radio(doc, { wifi = true, bt = true }) end
  if ev.name == "sys.wifi_on" then return radio.on_radio(doc, { wifi = true }) end
  if ev.name == "sys.wifi_off" then return radio.on_radio(doc, { wifi = false }) end
  if ev.name == "sys.bt_on" then return radio.on_radio(doc, { bt = true }) end
  if ev.name == "sys.bt_off" then return radio.on_radio(doc, { bt = false }) end
  return { commands = { { kind = "log", level = "warn", key = "device.system_tag_ignored", fields = { name = ev.name } } } }
end

-- ------------------------------------------------------------------ boot / timers / install
--- Boot: the flags read from /data/mode become the state; an airplane mode started from the page
--- ends at the next start, whatever the ESP32 remembers.
function radio.on_boot(doc, ev)
  local flags = ev.flags or {}
  local d = copy(doc.device or {})
  d.toy_safe = not flags.TOY_SAFE_OFF
  -- false = the page may offer the (bounded) airplane mode; a table = one is running (until the restore below)
  d.airplane = flags.OJ_AIRPLANE and { boot = true } or false
  local cmds = {}
  if flags.OJ_AIRPLANE then cmds[#cmds + 1] = { kind = "timer.once", name = "device.airplane_restore", seconds = AIRPLANE_BOOT_RESTORE_S } end
  return { state = { flags = flags, device = d }, commands = cmds }
end

-- the radio timers, each handler on its own name (kernel.dispatch on_timer)
local TIMERS = {
  ["device.airplane"] = function(doc) return radio.on_airplane_end(doc, "timer") end,
  ["device.airplane_restore"] = function(doc) return radio.on_airplane_end(doc, "boot") end,
}
radio.TIMERS = TIMERS

--- Any of the radio timers, by name (the specs drive this one; the kernel routes each name itself).
function radio.on_timer(doc, ev)
  local fn = TIMERS[ev.name]
  if not fn then return nil end
  return fn(doc, ev)
end

local S = {}
S.enable = { type = "object", required = { "enable" }, properties = { enable = { type = "boolean" } }, additionalProperties = false }
S.airplane = { type = "object", properties = { minutes = { type = "integer", minimum = 1, maximum = AIRPLANE_MAX_MIN }, cancel = { type = "boolean" } }, additionalProperties = false }
radio.schemas = S

function radio.install(api, dispatch)
  dispatch.on("boot", "device.radio", radio.on_boot)
  for name, fn in pairs(TIMERS) do dispatch.on_timer(name, "device.radio", fn) end
  dispatch.on("device.toy_safe_request", "device.radio", radio.on_toy_safe)
  dispatch.on("radio.set", "device.radio", radio.on_radio)
  dispatch.on("system.tag", "device.radio", radio.on_system_tag)
  api.command("device.toy_safe", S.enable, function(doc, p) return radio.on_toy_safe(doc, { enable = p.enable }) end)
  api.command("device.airplane", S.airplane, function(doc, p, ev) return radio.on_airplane(doc, p, ev) end)
end

return radio
