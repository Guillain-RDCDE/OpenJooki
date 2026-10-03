-- services.device.power: battery, cable, charging, heat, inactivity, and the power-off sequence.
-- Owns:
--   state.power    = { connected, charging, level = { mv, p, t }, warned_at }
--   state.activity = { last, warned, buttons = { [name] = down_at } }   (buttons is services.device.buttons')
-- The volume chain (audiocfg) stays the facade's, services.device: it is asked for at call time, never
-- at load time, since the facade requires this module. Installed by services.device, which re-exports
-- its handlers.
local util = require("services.util")
local power = {}

local LED = "/j/led/output/"

local copy, emit = util.copy, util.emit
local function cfg(doc, key, default)
  local c = doc.config or {}
  if c[key] ~= nil then return c[key] end
  return default
end
local function volume() return require("services.device") end

local function activity_of(doc)
  local a = copy(doc.activity or {})
  a.buttons = a.buttons or {}
  return a
end

-- ------------------------------------------------------------------ power
local function power_of(doc)
  local p = copy(doc.power or {})
  p.level = p.level or { mv = 0, p = 0, t = 0 }
  return p
end

function power.on_battery(doc, ev)
  local p = power_of(doc)
  p.level = { mv = ev.mv or 0, p = ev.tenths or 0, t = ev.mc or 0 }
  local cmds = {}
  if (ev.mc or 0) > cfg(doc, "overheat_mc", 80000) then
    cmds[#cmds + 1] = { kind = "log", level = "error", key = "device.overheat", fields = { mc = ev.mc } }
    cmds[#cmds + 1] = emit("device.toy_safe_request", { enable = true })
    cmds[#cmds + 1] = { kind = "shell", action = "power_overheat" }
    local s = volume().set_volume(doc, 80)
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

function power.on_plugged(doc, ev)
  local p = power_of(doc)
  if p.connected == ev.on then return nil end
  local first = p.connected == nil
  p.connected = ev.on
  local cmds = {}
  if not first then
    cmds[#cmds + 1] = { kind = "files.write_text", path = "/sys/kernel/htdrv/usb_mux", text = (ev.on and not volume().audiocfg_of(doc).headphones_en) and "0" or "1" }
    cmds[#cmds + 1] = emit("system.event", { name = ev.on and "Evt.Power.Cable.Insert" or "Evt.Power.Cable.Remove" })
  end
  return { state = { power = p }, commands = cmds }
end

function power.on_charging(doc, ev)
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
function power.on_inactivity(doc, ev)
  if doc.flags and doc.flags.STAY_ON then return nil end
  local act = doc.activity or {}
  -- a connected Bluetooth speaker no longer keeps it awake (1.x did): the chip reconnects it
  -- by itself, so a Jooki idle next to its speaker would never switch off (docs/26)
  local plugged = doc.power and doc.power.connected
  if util.is_playing(doc) or plugged then
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
function power.on_activity(doc, ev)
  local a2 = activity_of(doc)
  if a2.last == ev.now and not a2.warned then return nil end
  a2.last, a2.warned = ev.now, nil
  return { state = { activity = a2 } }
end

-- ------------------------------------------------------------------ power off
function power.on_off_request(_, ev)
  return { commands = { emit("system.event", { name = "Evt.Jooki.Poweroff", after = { type = "shutdown.request", reason = ev.reason } }) } }
end

function power.on_shutdown_request(doc, ev)
  local a = volume().audiocfg_of(doc)
  local cmds = {
    { kind = "files.write", path = volume().audiocfg_path(doc), doc = a, version = 1 },
    { kind = "bus.publish", topic = LED .. "set_raw", payload = "ALL,0,0,0" },
    { kind = "bus.publish", topic = LED .. "set_raw", payload = "CIRCLE,200,0,0" },
    { kind = "bus.publish", topic = "/j/all/quit", payload = '"from-player"' },
    { kind = "shell", action = "sync" },
  }
  if ev.reason ~= "signal" then cmds[#cmds + 1] = { kind = "shell", action = "poweroff" } end
  cmds[#cmds + 1] = { kind = "shutdown", reason = ev.reason or "requested" }
  return { commands = cmds }
end

-- ------------------------------------------------------------------ boot / timers / install
--- Boot: the inactivity timer, and the charger read from its file (the power controller only reports
--- a cable change: without this a Jooki plugged in at boot would believe it runs on battery).
function power.on_boot(_, ev)
  -- plugged at start (1.x did the same): known from the first second, so no cable sound either
  local connected
  if ev.plugged == "1" then connected = true elseif ev.plugged == "0" then connected = false end
  return { state = { power = { level = { mv = 0, p = 0, t = 0 }, connected = connected }, activity = { last = ev.now or 0, buttons = {} } },
           commands = { { kind = "timer.every", name = "device.inactivity", seconds = 30 } } }
end

-- the power timers, each handler on its own name (kernel.dispatch on_timer)
local TIMERS = {
  ["device.inactivity"] = power.on_inactivity,
}
power.TIMERS = TIMERS

--- Any of the power timers, by name (the specs drive this one; the kernel routes each name itself).
function power.on_timer(doc, ev)
  local fn = TIMERS[ev.name]
  if not fn then return nil end
  return fn(doc, ev)
end

function power.install(api, dispatch)
  dispatch.on("boot", "device.power", power.on_boot)
  for name, fn in pairs(TIMERS) do dispatch.on_timer(name, "device.power", fn) end
  dispatch.on("power.battery", "device.power", power.on_battery)
  dispatch.on("power.plugged", "device.power", power.on_plugged)
  dispatch.on("power.charging", "device.power", power.on_charging)
  dispatch.on("power.off_request", "device.power", power.on_off_request)
  dispatch.on("shutdown.request", "device.power", power.on_shutdown_request)
  dispatch.on("host.terminating", "device.power", function(doc) return power.on_shutdown_request(doc, { reason = "signal" }) end)
  for _, t in ipairs({ "nfc.tag", "api.cmd", "v1.cmd", "playback.request" }) do dispatch.on(t, "device.power", power.on_activity) end
  api.command("device.power_off", nil,function(_, _, ev) return power.on_off_request(nil, { reason = "page", now = ev.now }) end)
end

return power
