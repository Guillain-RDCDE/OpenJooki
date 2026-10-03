-- services.device.buttons: the buttons (1.x keys module). Presses on release, the long presses
-- detected by a tick that runs only while a button is held, and the four-button combo.
-- Writes state.activity.last and state.activity.buttons = { [name] = down_at } (state.activity is
-- services.device.power's). The volume chain stays the facade's, services.device: asked for at call
-- time, never at load time, since the facade requires this module. Installed by services.device,
-- which re-exports its handlers.
local util = require("services.util")
local buttons = {}

local copy, emit = util.copy, util.emit
local function volume() return require("services.device") end

-- ------------------------------------------------------------------ buttons (1.x keys module)
local LONG_CIRCLE_S, LONG_AIRPLANE_S, LONG_RESET_S = 2, 5, 10
local COMBO = { "next", "prev", "vol_inc", "vol_dec" }

local function activity_of(doc)
  local a = copy(doc.activity or {})
  a.buttons = a.buttons or {}
  return a
end

local function all_down(held)
  for _, b in ipairs(COMBO) do if not held[b] then return false end end
  return true
end

-- The long-press tick (device.tick, every 0.5 s) runs only while a button is held: the first button
-- down starts it, the last one up (or the tick that acts on it) stops it. Nothing to tick otherwise.
local TICK_S = 0.5
local function tick_change(cmds, held_before, held)
  local is_held = next(held) ~= nil
  if is_held and not held_before then cmds[#cmds + 1] = { kind = "timer.every", name = "device.tick", seconds = TICK_S }
  elseif held_before and not is_held then cmds[#cmds + 1] = { kind = "timer.cancel", name = "device.tick" } end
end

function buttons.on_button(doc, ev)
  local act = activity_of(doc)
  act.last = ev.now
  local cmds = {}
  local name = ev.button
  local held_before = next(act.buttons) ~= nil
  if ev.down then
    act.buttons[name] = ev.now
    if all_down(act.buttons) then
      cmds[#cmds + 1] = { kind = "shell", action = "speak_info" }
      cmds[#cmds + 1] = emit("playback.pause_request", { source = "speak_info" })
      act.buttons = {}
    end
    tick_change(cmds, held_before, act.buttons)
    -- airplane buttons are decided on release or by the long-press tick
    return { state = { activity = act }, commands = cmds }
  end
  -- release: circle short press does nothing (the long press is on the tick);
  -- hp_plugged is reported through the knob state
  local down_at = act.buttons[name]
  act.buttons[name] = nil
  if name == "airplane_release" then act.buttons.airplane_mode_on, act.buttons.airplane_mode_off = nil, nil end
  tick_change(cmds, held_before, act.buttons)
  if not down_at then return { state = { activity = act }, commands = cmds } end
  if name == "next" then cmds[#cmds + 1] = emit("playback.next", {})
  elseif name == "prev" then cmds[#cmds + 1] = emit("playback.prev", {})
  elseif name == "vol_inc" or name == "vol_dec" then
    local a = volume().audiocfg_of(doc)
    local s = volume().set_volume(doc, a.volume + (name == "vol_inc" and 10 or -10))
    for _, c in ipairs(s.commands) do cmds[#cmds + 1] = c end
    return { state = { activity = act, audiocfg = s.state.audiocfg }, commands = cmds }
  end
  return { state = { activity = act }, commands = cmds }
end

--- Long presses are detected on the tick (like 1.x): circle 2 s -> power off, airplane 5 s.
function buttons.on_tick(doc, ev)
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
  -- prev + next held together for 10 s: clear the parent code (docs/adr/0007 — whoever
  -- holds the Jooki is allowed). A confirmation sound is played by services.security.
  if act.buttons.prev and act.buttons.next and now - math.max(act.buttons.prev, act.buttons.next) >= LONG_RESET_S then
    a2.buttons.prev = nil; a2.buttons.next = nil; changed = true
    cmds[#cmds + 1] = emit("security.parent_clear", { physical = true })
  end
  if not changed then return nil end
  tick_change(cmds, true, a2.buttons)   -- the press acted on was the last one held: the tick stops
  return { state = { activity = a2 }, commands = cmds }
end

-- ------------------------------------------------------------------ timers / install
-- the buttons' timer (started by the first button held, see on_button), on its own name (kernel.dispatch on_timer)
local TIMERS = {
  ["device.tick"] = buttons.on_tick,
}
buttons.TIMERS = TIMERS

--- The buttons' timer, by name (the specs drive this one; the kernel routes the name itself).
function buttons.on_timer(doc, ev)
  local fn = TIMERS[ev.name]
  if not fn then return nil end
  return fn(doc, ev)
end

function buttons.install(_, dispatch)
  for name, fn in pairs(TIMERS) do dispatch.on_timer(name, "device.buttons", fn) end
  dispatch.on("gpio.button", "device.buttons", buttons.on_button)
end

return buttons
