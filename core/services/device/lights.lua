-- services.device.lights: the Jooki's lights (1.x language, 1.3 dimming).
-- The ring and the two side dots: idle / playing ring, Wi-Fi dots, the start-up "waiting for
-- Wi-Fi" chase, the event pulses (lights.event) and the Christmas tree. Pure: it reacts to events
-- owns state.device.party and private driver verification, startup-cue state.
-- Colours sent are not kept (the simulator reads them off the bus). Installed by services.device
-- (the facade), which re-exports its handlers.
local util = require("services.util")
local bedtime = require("services.bedtime")
local lights = {}

local LED = "/j/led/output/"
local COLOURS = { WHITE = { 200, 200, 200 }, BLACK = { 0, 0, 0 }, RED = { 200, 0, 0 }, GREEN = { 0, 200, 0 },
                  BLUE = { 0, 0, 200 }, YELLOW = { 200, 200, 0 }, ORANGE = { 200, 40, 0 }, LO_ORANGE = { 50, 10, 0 },
                  LIGHTBLUE = { 0, 10, 200 } }

local copy = util.copy
local function requested_off(doc)
  return (doc.audiocfg or {}).lights_off == true or (doc.limits or {}).lights_off == true
end
lights.requested_off = requested_off
function lights.off(doc)
  local boot = doc.lights_boot_int or {}
  if (doc.poweroff_int or {}).step then return true end
  if boot.phase == "connecting" or boot.phase == "waiting" then return false end
  if boot.phase == "blinking" then return true end -- only the startup frames may paint
  return requested_off(doc)
end
local function cfg(doc, key, default)
  local c = doc.config or {}
  if c[key] ~= nil then return c[key] end
  return default
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

-- While the Jooki waits for its Wi-Fi at start-up, the two side dots are orange. Both at once and
-- steady, that reads as "it crashed" (the chip only tries to join the network about a minute after
-- power-on, docs/20). So instead of a steady pair we run a slow left<->right glow -- bright orange
-- ping-ponging over dim orange, both dots always lit so it never looks dead -- which plainly says
-- "something is happening, you can wait". It stops on its own the moment the Wi-Fi associates, a
-- token is played, or airplane mode is on (where steady orange is the intended "off", docs/24).
local ANIM_S = 0.45   -- default frame interval; the live value comes from config (0 = off, e.g. on the bench)
local function anim_s(doc) local v = cfg(doc, "wifi_anim_s", ANIM_S); return (v and v > 0) and v or ANIM_S end
local function radios_off(doc)
  if doc.flags and doc.flags.WIFI_OFF then return true end
  if doc.device and doc.device.airplane then return true end
  return false
end
local function playing(doc)
  local s = (doc.playback or {}).state
  return s == "playing" or s == "starting" or s == "paused"
end
-- the side dots should chase (rather than sit steady orange) while: not yet associated, radios on,
-- nothing playing. The same test tells on_lights_refresh to leave the dots to the animation.
local function wifi_waiting(doc)
  return not (doc.net and doc.net.connected) and not radios_off(doc) and not playing(doc)
end

--- One frame of the start-up "waiting for Wi-Fi" chase, or its end. Driven by the device.wifi_anim
--- timer started at boot; it cancels that timer as soon as the wait is over.
function lights.on_wifi_anim(doc, ev)
  if lights.off(doc) then return nil end
  if (doc.device or {}).party then return nil end
  if not wifi_waiting(doc) then
    local r = lights.on_lights_refresh(doc)   -- let the dots settle to their real state
    r.commands[#r.commands + 1] = { kind = "timer.cancel", name = "device.wifi_anim" }
    return r
  end
  local phase = math.floor((ev.now or 0) / anim_s(doc)) % 2
  return { commands = {
    set(doc, "PREV", phase == 0 and COLOURS.ORANGE or COLOURS.LO_ORANGE),
    set(doc, "NEXT", phase == 0 and COLOURS.LO_ORANGE or COLOURS.ORANGE),
  } }
end

--- Idle/playing ring + Wi-Fi dots, recomputed on playback and network changes.
function lights.on_lights_refresh(doc)
  if lights.off(doc) then return { commands = {} } end
  local pb = doc.playback or {}
  local cmds = {}
  if (doc.device or {}).party then return { commands = cmds } end   -- the Christmas tree owns the lights for 5 s
  if pb.state == "starting" then
    cmds[#cmds + 1] = set(doc, "PREV", COLOURS.LIGHTBLUE); cmds[#cmds + 1] = set(doc, "NEXT", COLOURS.LIGHTBLUE)
    return { commands = cmds }
  end
  local ring = COLOURS.WHITE
  if pb.state == "playing" and doc.nfc and doc.nfc.tagId then ring = COLOURS.BLACK end   -- 1.x: the ring goes off while a token plays
  cmds[#cmds + 1] = set(doc, "RING", ring)
  -- while the start-up chase owns the side dots, leave them to it (it paints PREV/NEXT itself)
  if not wifi_waiting(doc) then
    for _, c in ipairs(wifi_lights(doc)) do cmds[#cmds + 1] = c end
  end
  return { commands = cmds }
end

-- The network check reports every 30 s (services.network). Painting the lights again each time cut
-- short whatever pulse was running (led_ctrl drops a pulse on any new set, Muuselabs' lib_led.c), so
-- the dots are painted again only when what they show changes: the last one shown is kept as
-- state.device.lit_net.
local function net_key(doc)
  local w = doc.net or {}
  return tostring(not not w.connected) .. "|" .. tostring(w.ip ~= nil and w.ip ~= "") .. "|" .. tostring(wifi_waiting(doc)) .. "|" .. tostring(radios_off(doc))
end
local function connected(doc)
  local n = doc.net or {}
  return n.connected and type(n.ip) == "string" and n.ip ~= "" and n.ip ~= "0.0.0.0"
end
function lights.on_net_status(doc, ev)
  -- Dispatch handlers share the pre-event document; use this status report now.
  local after = copy(doc)
  if ev then
    after.net = copy(doc.net or {}); after.net.connected = ev.connected; after.net.ip = ev.ip
  end
  local key = net_key(after)
  local r = { state = {}, commands = {} }
  if (doc.device or {}).lit_net ~= key then
    r = lights.on_lights_refresh(after); r.state = r.state or {}
    local d = copy(doc.device or {}); d.lit_net = key; r.state.device = d
  end
  local boot = copy(doc.lights_boot_int or {})
  if boot.phase == "connecting" and connected(after) then
    boot.phase = "waiting"; r.state.lights_boot_int = boot
    r.commands[#r.commands + 1] = { kind = "timer.once", name = "device.lights_boot", seconds = 10 }
  elseif boot.phase == "waiting" and not connected(after) then
    boot.phase = "connecting"; r.state.lights_boot_int = boot
    r.commands[#r.commands + 1] = { kind = "timer.once", name = "device.lights_boot", seconds = lights.NO_WIFI_S }
  end
  if not next(r.state) and #r.commands == 0 then return nil end
  return r
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

function lights.on_lights_event(doc, ev)
  if lights.off(doc) then return nil end
  local f = EVENT_LIGHTS[ev.name]
  if f then return { commands = f(doc) } end
  if ERROR_EVENTS[ev.name] then return { commands = { pulse(doc, "PREV", COLOURS.RED, 2), pulse(doc, "NEXT", COLOURS.RED, 2) } } end
  if WARN_EVENTS[ev.name] then return { commands = { pulse(doc, "PREV", COLOURS.YELLOW, 1), pulse(doc, "NEXT", COLOURS.YELLOW, 1) } } end
  return nil
end

-- ------------------------------------------------------------------ the Christmas tree (just for fun)
-- A button in Settings: for 5 s the ring and the two side dots run through the colour wheel, each
-- at a different place on it, then everything goes back to its real state. The heart stays the
-- light controller's (docs/24 §1). Night mode's dimming applies, so it never lights up a bedroom.
local PARTY_S, PARTY_FRAME_S, PARTY_STEP = 5, 0.12, 47   -- 47° a frame: the colours jump, they do not slide

--- A fully saturated colour at `deg` on the colour wheel, 0-200 like the rest of the lights.
local function wheel(deg)
  local h = (deg % 360) / 60
  local i = math.floor(h)
  local up, down = math.floor(200 * (h - i) + 0.5), math.floor(200 * (1 - (h - i)) + 0.5)
  return ({ { 200, up, 0 }, { down, 200, 0 }, { 0, 200, up }, { 0, down, 200 }, { up, 0, 200 }, { 200, 0, down } })[i + 1]
end
lights.wheel = wheel

function lights.on_party(doc)
  if lights.off(doc) then return {} end
  if (doc.device or {}).party then return {} end
  local d = copy(doc.device or {}); d.party = true
  return { state = { device = d }, commands = {
    { kind = "timer.every", name = "device.party", seconds = PARTY_FRAME_S },
    { kind = "timer.once", name = "device.party_end", seconds = PARTY_S } } }
end

function lights.on_party_frame(doc, ev)
  if lights.off(doc) then return nil end
  if not (doc.device or {}).party then return { commands = { { kind = "timer.cancel", name = "device.party" } } } end
  local deg = math.floor((ev.now or 0) / PARTY_FRAME_S) * PARTY_STEP
  return { commands = { set(doc, "RING", wheel(deg)), set(doc, "PREV", wheel(deg + 120)), set(doc, "NEXT", wheel(deg + 240)) } }
end

function lights.on_party_end(doc)
  local d = copy(doc.device or {}); d.party = nil
  local after = {}
  for k, v in pairs(doc) do after[k] = v end
  after.device = d
  local r = lights.on_lights_refresh(after)
  table.insert(r.commands, 1, { kind = "timer.cancel", name = "device.party" })
  r.state = { device = d }
  return r
end

-- ------------------------------------------------------------------ boot / timers / install
--- Boot starts the side-dot "waiting for Wi-Fi" chase; it stops itself once the network is up (or a
--- token plays). Off the real Jooki wifi_anim_s is 0 (no frames, no idle bus traffic on the bench).
-- The global LED driver gates the ring, side dots AND the Holtek-owned heart.
-- ht_ctrl writes register 34 and reports the read-back on raw_read_response.
-- A missing / wrong answer gets at most three attempts, including the first.
local function driver_write(value)
  return { kind = "bus.publish", topic = "/j/ht/output/raw_write", payload = "34 " .. value }
end
local function verify_timer() return { kind = "timer.once", name = "device.lights_verify", seconds = 0.75 } end

function lights.on_apply(doc)
  local off = lights.off(doc)
  local boot = doc.lights_boot_int or {}
  local shutdown = doc.poweroff_int or {}
  local flashing = shutdown.step ~= nil or boot.phase == "blinking"
  local step = shutdown.step or boot.step or 0
  local colour = shutdown.step and COLOURS.RED or COLOURS.WHITE
  local enabled = flashing and step % 2 == 1 or not off
  local d = copy(doc.device or {}); d.party = nil
  local cmds = {
    { kind = "timer.cancel", name = "device.party" }, { kind = "timer.cancel", name = "device.party_end" },
    { kind = "timer.cancel", name = "device.wifi_anim" },
    -- A set cancels the controller's ongoing pulses too. The global gate remains authoritative.
    { kind = "bus.publish", topic = LED .. "set_raw", payload = flashing and enabled and ("ALL," .. table.concat(dimmed(doc, colour), ",")) or "ALL,0,0,0" },
    driver_write(enabled and 8 or 0), verify_timer(),
  }
  -- bus.up also changes state.device in the facade. Clear party in the next turn so
  -- a stale copy here cannot replace its esp32_up / capability reset.
  if (doc.device or {}).party then cmds[#cmds + 1] = util.emit("lights.cancel_party", {}) end
  if not off then
    local after = copy(doc); after.device = d
    for _, c in ipairs(lights.on_lights_refresh(after).commands) do cmds[#cmds + 1] = c end
    if cfg(doc, "wifi_anim_s", ANIM_S) > 0 and wifi_waiting(doc) then
      cmds[#cmds + 1] = { kind = "timer.every", name = "device.wifi_anim", seconds = anim_s(doc) }
    end
  end
  return { state = { lights_int = { desired = enabled and 8 or 0, pending = true, attempts = 1 } }, commands = cmds }
end

function lights.on_register(doc, ev)
  local s = doc.lights_int or {}
  if ev.address ~= 34 or not s.pending or ev.value ~= s.desired then return nil end
  local done = copy(s); done.pending = false; done.verified = true
  return { state = { lights_int = done }, commands = { { kind = "timer.cancel", name = "device.lights_verify" } } }
end

function lights.on_verify(doc)
  local s = doc.lights_int or {}
  if not s.pending then return nil end
  local next_state = copy(s)
  if s.attempts >= 3 then
    next_state.pending = false; next_state.verified = false
    return { state = { lights_int = next_state }, commands = {
      { kind = "log", level = "warn", key = "device.lights_unconfirmed", fields = { desired = s.desired, attempts = s.attempts } } } }
  end
  next_state.attempts = s.attempts + 1
  return { state = { lights_int = next_state }, commands = { driver_write(s.desired), verify_timer() } }
end

function lights.on_power(doc, ev)
  local key = ev.type == "power.charging" and "charging" or "connected"
  if lights.off(doc) and (doc.power or {})[key] ~= ev.on then return lights.on_apply(doc) end
  return nil
end

-- A configuration change cancels any boot cue.
-- Reconnects / charging reapply the current phase without restarting the countdown.
function lights.on_preference(doc)
  if (doc.poweroff_int or {}).step then return nil end
  local after = copy(doc); after.lights_boot_int = {}
  local r = lights.on_apply(after)
  r.state.lights_boot_int = {}
  r.commands[#r.commands + 1] = { kind = "timer.cancel", name = "device.lights_boot" }
  return r
end

function lights.on_limits(doc)
  if (doc.lights_boot_int or {}).phase and not requested_off(doc) then return lights.on_preference(doc) end
  if (doc.lights_boot_int or {}).phase == "blinking" then return nil end
  local desired = lights.off(doc) and 0 or 8
  if (doc.lights_int or {}).desired ~= desired then return lights.on_apply(doc) end
  return lights.on_lights_refresh(doc)
end

local BOOT_WAIT_S, BLINK_S = 10, 0.15
-- Holidays, airplane mode, a router that is off: the dark the parent asked for does not wait for ever.
lights.NO_WIFI_S = 60
function lights.on_boot(doc, ev)
  local after = copy(doc); after.audiocfg = (ev or {}).audiocfg or doc.audiocfg or {}
  after.limits = bedtime.boot_limits(ev or {})
  after.lights_boot_int = requested_off(after) and { phase = connected(after) and "waiting" or "connecting" } or {}
  local r = lights.on_apply(after)
  r.state.lights_boot_int = after.lights_boot_int
  if after.lights_boot_int.phase == "waiting" then
    r.commands[#r.commands + 1] = { kind = "timer.once", name = "device.lights_boot", seconds = BOOT_WAIT_S }
  elseif after.lights_boot_int.phase == "connecting" then
    r.commands[#r.commands + 1] = { kind = "timer.once", name = "device.lights_boot", seconds = lights.NO_WIFI_S }
  end
  return r
end

function lights.on_boot_frame(doc)
  local b = copy(doc.lights_boot_int or {})
  if (doc.poweroff_int or {}).step or not b.phase then return nil end
  if b.phase ~= "blinking" then b = { phase = "blinking", step = 1 }
  elseif b.step < 6 then b.step = b.step + 1
  else b = {} end
  local after = copy(doc); after.lights_boot_int = b
  local r = lights.on_apply(after); r.state.lights_boot_int = b
  if b.phase then r.commands[#r.commands + 1] = { kind = "timer.once", name = "device.lights_boot", seconds = BLINK_S } end
  return r
end

-- the lights' timers, each handler on its own name (kernel.dispatch on_timer)
local TIMERS = {
  ["device.wifi_anim"] = lights.on_wifi_anim,
  ["device.party"] = lights.on_party_frame,
  ["device.party_end"] = lights.on_party_end,
  ["device.lights_verify"] = lights.on_verify,
  ["device.lights_boot"] = lights.on_boot_frame,
}
lights.TIMERS = TIMERS

--- Any of the lights' timers, by name (the specs drive this one; the kernel routes each name itself).
function lights.on_timer(doc, ev)
  local fn = TIMERS[ev.name]
  if not fn then return nil end
  return fn(doc, ev)
end

function lights.install(api, dispatch)
  dispatch.on("boot", "device.lights", lights.on_boot)
  dispatch.on("bus.up", "device.lights", lights.on_apply)
  dispatch.on("lights.apply", "device.lights", lights.on_preference)
  dispatch.on("lights.cancel_party", "device.lights", lights.on_party_end)
  dispatch.on("lights.register", "device.lights", lights.on_register)
  dispatch.on("power.plugged", "device.lights", lights.on_power)
  dispatch.on("power.charging", "device.lights", lights.on_power)
  for name, fn in pairs(TIMERS) do dispatch.on_timer(name, "device.lights", fn) end
  dispatch.on("lights.event", "device.lights", lights.on_lights_event)
  dispatch.on("playback.changed", "device.lights", lights.on_lights_refresh)
  dispatch.on("net.status", "device.lights", lights.on_net_status)
  dispatch.on("limits.changed", "device.lights", lights.on_limits)   -- after the facade's volume re-apply
  api.command("device.party", nil, function(doc) return lights.on_party(doc) end)
end

return lights
