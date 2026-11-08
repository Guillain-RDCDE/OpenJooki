-- services.device.buttons: the buttons (1.x keys module). Presses on release, the long presses
-- detected by a tick that runs only while a button is held, the five-click light gesture and the four-button combo.
-- Writes state.activity.last, activity.buttons = { [name] = down_at } and activity.heart_clicks (state.activity is
-- services.device.power's). The volume chain stays the facade's, services.device: asked for at call
-- time, never at load time, since the facade requires this module. Installed by services.device,
-- which re-exports its handlers.
local util = require("services.util")
local buttons = {}

local copy, emit = util.copy, util.emit
local function volume() return require("services.device") end

-- ------------------------------------------------------------------ buttons (1.x keys module)
local LONG_CIRCLE_S, LONG_AIRPLANE_S, LONG_RESET_S = 2, 5, 10
-- the heart held to switch off: 2 s as the original, 5 s when its short press does something (#20:
-- a small child pressing "next song" a bit too long switched the Jooki off). The Holtek cuts the
-- power by itself only at about 10 s (holtek-code Main.c: 255 steps of 40 ms), so 5 s stays clean.
local LONG_CIRCLE_BUSY_S = 5
local function long_circle_s(doc)
  local hp = (doc.audiocfg or {}).heart_press
  return (hp == "next" or hp == "pause") and LONG_CIRCLE_BUSY_S or LONG_CIRCLE_S
end
local RESET_MAX_VOLUME = 5   -- the volume wheel all the way down (it reads 0-100) for the parent-code gesture
local COMBO = { "next", "prev", "vol_inc", "vol_dec" }
-- The track knob, as the parents chose in Settings (audiocfg.knob_mode):
--   "song" (default, the original Jooki): all the way = next / prev; halfway does nothing (Muuselabs'
--          do_fwd / do_rev were never written)
--   "both": halfway (fwd / rew, knobs_ctrl.c's zones between the centre and next / prev) winds the track
--   "wind": the knob only winds, halfway or all the way (the heart can change the song)
-- Winding: after SEEK_HOLD_S held, SEEK_STEP_S at every tick. A turn all the way crosses the halfway
-- zone in a blink, so it never winds there. In "wind", a short turn all the way winds once.
local SEEK_HOLD_S, SEEK_STEP_S = 1, 10
local WINDERS = { song = {}, both = { fwd = 1, rew = -1 }, wind = { fwd = 1, rew = -1, next = 1, prev = -1 } }
local function knob_mode(doc)
  local m = (doc.audiocfg or {}).knob_mode
  return WINDERS[m] and m or "song"
end
-- A short press on the heart (held 2 s it switches the Jooki off) does what the parents chose in
-- Settings (audiocfg.heart_press): nothing, the next track, or pause / play.
local HEART = { next = function() return emit("playback.next", {}) end,
                pause = function(now) return emit("playback.toggle_request", { source = "button", now = now }) end }

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

-- Buffer short heart clicks until the multi-click window closes. This keeps
-- the five-click light gesture from also skipping five songs or toggling pause.
local HEART_GAP_S, HEART_SHORT_S = 0.6, 0.6
local function flush_heart(doc, act, cmds, now)
  local h = act.heart_clicks
  act.heart_clicks = nil
  cmds[#cmds + 1] = { kind = "timer.cancel", name = "device.heart_clicks" }
  local fn = HEART[(doc.audiocfg or {}).heart_press]
  if h and fn then for _ = 1, h.count do cmds[#cmds + 1] = fn(now) end end
end
function buttons.on_heart_clicks(doc, ev)
  local act = activity_of(doc)
  if not act.heart_clicks or act.buttons.circle then return nil end
  local remaining = act.heart_clicks.last + HEART_GAP_S - ev.now
  if remaining > 0.001 then
    return { commands = { { kind = "timer.once", name = "device.heart_clicks", seconds = remaining } } }
  end
  local cmds = {}; flush_heart(doc, act, cmds, ev.now)
  return { state = { activity = act }, commands = cmds }
end

function buttons.on_button(doc, ev)
  -- headphones plugged in or out: not a button (services.device reads the knobs again); held, it
  -- would keep the long-press tick running for as long as the headphones stay in
  if ev.button == "hp_plugged" then return nil end
  local act = activity_of(doc)
  act.last = ev.now
  local cmds = {}
  local name = ev.button
  local held_before = next(act.buttons) ~= nil
  if ev.down then
    if act.buttons[name] then return nil end -- duplicate down must not restart a hold
    if act.heart_clicks then
      if name == "circle" then cmds[#cmds + 1] = { kind = "timer.cancel", name = "device.heart_clicks" }
      else flush_heart(doc, act, cmds, ev.now) end
    end
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
  if (name == "next" or name == "prev") and knob_mode(doc) == "wind" then
    -- held, it was wound by the tick; a short turn winds once
    if ev.now - down_at < SEEK_HOLD_S then
      cmds[#cmds + 1] = emit("playback.skip_request", { seconds = WINDERS.wind[name] * SEEK_STEP_S })
    end
  elseif name == "next" then cmds[#cmds + 1] = emit("playback.next", {})
  elseif name == "prev" then cmds[#cmds + 1] = emit("playback.prev", {})
  elseif name == "circle" then
    -- a long press was taken by the tick (power off) and is no longer held here: this one is short
    local duration = ev.now - down_at
    if duration >= HEART_SHORT_S then
      if act.heart_clicks then flush_heart(doc, act, cmds, ev.now) end
      local fn = HEART[(doc.audiocfg or {}).heart_press]
      if fn then cmds[#cmds + 1] = fn(ev.now) end
    -- Several valid edges may arrive in one MQTT read with the same timestamp.
    -- Reject duplicate/orphan edges, rather than rejecting a zero-length measured hold.
    elseif duration >= 0 then
      local h = act.heart_clicks
      if h and ev.now - h.last > HEART_GAP_S then flush_heart(doc, act, cmds, ev.now); h = nil end
      h = { count = (h and h.count or 0) + 1, last = ev.now }
      if h.count == 5 then
        act.heart_clicks = nil
        cmds[#cmds + 1] = { kind = "timer.cancel", name = "device.heart_clicks" }
        cmds[#cmds + 1] = emit("lights.toggle", { physical = true })
      else
        act.heart_clicks = h
        cmds[#cmds + 1] = { kind = "timer.once", name = "device.heart_clicks", seconds = HEART_GAP_S }
      end
    end
  elseif name == "vol_inc" or name == "vol_dec" then
    local a = volume().audiocfg_of(doc)
    local s = volume().set_volume(doc, a.volume + (name == "vol_inc" and 10 or -10))
    for _, c in ipairs(s.commands) do cmds[#cmds + 1] = c end
    return { state = { activity = act, audiocfg = s.state.audiocfg }, commands = cmds }
  end
  return { state = { activity = act }, commands = cmds }
end

--- Long presses are detected on the tick (like 1.x): circle 2 s (5 s when the heart has a job) -> power off, airplane 5 s.
function buttons.on_tick(doc, ev)
  local act = doc.activity
  if not act or not act.buttons then return nil end
  local now = ev.now
  local cmds = {}
  local changed = false
  local a2 = activity_of(doc)
  if act.buttons.circle and now - act.buttons.circle >= long_circle_s(doc) then
    a2.buttons.circle = nil; changed = true
    if a2.heart_clicks then
      a2.heart_clicks = nil
      cmds[#cmds + 1] = { kind = "timer.cancel", name = "device.heart_clicks" }
    end
    cmds[#cmds + 1] = emit("power.off_request", { reason = "button" })
  end
  for n, sign in pairs(WINDERS[knob_mode(doc)]) do
    if act.buttons[n] and now - act.buttons[n] >= SEEK_HOLD_S then
      cmds[#cmds + 1] = emit("playback.skip_request", { seconds = sign * SEEK_STEP_S })
    end
  end
  for _, n in ipairs({ "airplane_mode_on", "airplane_mode_off" }) do
    if act.buttons[n] and now - act.buttons[n] >= LONG_AIRPLANE_S then
      a2.buttons[n] = nil; changed = true
      cmds[#cmds + 1] = emit("radio.set", { wifi = n == "airplane_mode_off", bt = n == "airplane_mode_off" })
    end
  end
  -- the parent code cleared by whoever holds the Jooki (docs/adr/0007); services.security plays a
  -- confirmation sound. On a Jooki 2, prev and next are the two ends of ONE knob (Muuselabs' source:
  -- esp32_ctrl.c KNOBS_EVENT_PREV/NEXT, one key in ml-j2000.dts), so they cannot be held together:
  -- the gesture is the volume wheel all the way down, then the knob held on prev for 10 s. The
  -- release that follows does nothing (prev is no longer held). prev + next stays for other hardware.
  local quiet = (tonumber((doc.audiocfg or {}).volume) or 100) <= RESET_MAX_VOLUME
  local reset = act.buttons.prev and act.buttons.next and now - math.max(act.buttons.prev, act.buttons.next) >= LONG_RESET_S
  reset = reset or (act.buttons.prev and quiet and now - act.buttons.prev >= LONG_RESET_S)
  if reset then
    a2.buttons.prev = nil; a2.buttons.next = nil; changed = true
    cmds[#cmds + 1] = emit("security.parent_clear", { physical = true })
  end
  if not changed then return #cmds > 0 and { commands = cmds } or nil end   -- winding: the knob stays held
  tick_change(cmds, true, a2.buttons)   -- the press acted on was the last one held: the tick stops
  return { state = { activity = a2 }, commands = cmds }
end

-- ------------------------------------------------------------------ timers / install
-- the buttons' timer (started by the first button held, see on_button), on its own name (kernel.dispatch on_timer)
local TIMERS = {
  ["device.tick"] = buttons.on_tick,
  ["device.heart_clicks"] = buttons.on_heart_clicks,
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
