-- services.bedtime: sleep timer, gentle fade, night window (docs/19), ported
-- from the 1.3 module as pure handlers.
-- Owns state.bedtime = { cfg, night, sleep }  (published; the page reads it)
--      state.bedtime_int = { fade, ends, restore, stop_at_end, ... } (internal)
-- Drives state.limits = { maxvol, fade, dim } that the device applies to the
-- speaker and the lights (event limits.changed).
local bedtime = {}

local DEF = { enabled = true, start = 1200, stop = 420, timer = 20, maxvol = 30, dim = true, tzbase = 60, tzdst = "EU" }
local FADE_S, TRACK_FADE_MS = 60, 20000
bedtime.DEFAULTS = DEF

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
local function path(doc) return ((doc.config and doc.config.data_dir) or "/jooki/external/jooki") .. "/bedtime.json" end

-- ------------------------------------------------------------------ clock (UTC -> local minutes, EU summer time)
local function dow(y, m, d)
  local k = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }
  if m < 3 then y = y - 1 end
  return (y + math.floor(y / 4) - math.floor(y / 100) + math.floor(y / 400) + k[m] + d) % 7
end
local function last_sunday(y, m) return 31 - dow(y, m, 31) end

--- Minutes since local midnight for a UTC wall time, or nil when the clock is not set.
function bedtime.local_minutes(cfg, wall)
  local u = os.date("!*t", wall)
  if u.year < 2024 then return nil end
  local off = tonumber(cfg.tzbase) or 0
  if cfg.tzdst == "EU" then
    local k = u.month * 10000 + u.day * 100 + u.hour
    if k >= 30000 + last_sunday(u.year, 3) * 100 + 1 and k < 100000 + last_sunday(u.year, 10) * 100 + 1 then off = off + 60 end
  end
  return (u.hour * 60 + u.min + off) % 1440
end

function bedtime.is_night(cfg, wall)
  if not cfg.enabled then return false end
  local m = bedtime.local_minutes(cfg, wall)
  if not m then return false end
  local a, b = cfg.start, cfg.stop
  if a == b then return false end
  if a < b then return m >= a and m < b end
  return m >= a or m < b
end

-- ------------------------------------------------------------------ state helpers
local function bt_of(doc)
  local b = copy(doc.bedtime or {})
  b.cfg = b.cfg or copy(DEF)
  if b.night == nil then b.night = false end
  if b.sleep == nil then b.sleep = false end
  return b
end
local function int_of(doc)
  local i = copy(doc.bedtime_int or {})
  i.fade = i.fade or 1
  return i
end

local function limits_for(b, i)
  return { maxvol = (b.night and b.cfg.maxvol < 100) and b.cfg.maxvol or 100, fade = i.fade, dim = b.night and b.cfg.dim == true }
end

local function limits_changed(doc, b, i)
  local new = limits_for(b, i)
  local old = doc.limits or {}
  return old.maxvol ~= new.maxvol or old.fade ~= new.fade or old.dim ~= new.dim, new
end

--- Build the result: state (bedtime, bedtime_int, limits when changed) + limits.changed.
local function result(doc, b, i, cmds)
  cmds = cmds or {}
  local r = { state = { bedtime = b, bedtime_int = i }, commands = cmds }
  local changed, lim = limits_changed(doc, b, i)
  if changed then
    r.state.limits = lim
    cmds[#cmds + 1] = emit("limits.changed", {})
  end
  return r
end

local function set_fade(i, f)
  if f >= 1 then f = 1 elseif f < 0 then f = 0 end
  if f ~= 1 and f ~= 0 and math.abs(f - i.fade) < 0.02 then return end
  i.fade = f
end

local function sleep_view(i, now)
  if not i.sleep then return false end
  local remaining
  if i.sleep.ends then remaining = math.max(0, math.floor(i.sleep.ends - now + 0.5)) end
  return { mode = i.sleep.mode, remaining = remaining, total = i.sleep.total, auto = i.sleep.auto or nil }
end

local function start_sleep(b, i, now, seconds, mode, auto)
  i.sleep = { mode = mode or "time", total = seconds, ends = seconds and (now + seconds) or nil, auto = auto or nil }
  i.stop_at_end = (mode == "track") or nil
  b.sleep = sleep_view(i, now)
  return { kind = "timer.every", name = "bedtime.tick", seconds = 0.5 }
end

local function clear_sleep(b, i)
  i.sleep, i.stop_at_end = nil, nil
  b.sleep = false
  return { kind = "timer.cancel", name = "bedtime.tick" }
end

-- ------------------------------------------------------------------ handlers
function bedtime.on_boot(doc, ev)
  local b = { cfg = copy(DEF), night = false, sleep = false }
  for k, v in pairs(ev.bedtime or {}) do if DEF[k] ~= nil and type(v) == type(DEF[k]) then b.cfg[k] = v end end
  local i = { fade = 1 }
  b.night = bedtime.is_night(b.cfg, ev.wall)
  local r = result(doc, b, i, { { kind = "timer.every", name = "bedtime.clock", seconds = 15 } })
  r.state.limits = limits_for(b, i)
  return r
end

function bedtime.on_timer(doc, ev)
  if ev.name == "bedtime.clock" then return bedtime.on_clock(doc, ev) end
  if ev.name == "bedtime.tick" then return bedtime.on_tick(doc, ev) end
  return nil
end

function bedtime.on_clock(doc, ev)
  local b, i = bt_of(doc), int_of(doc)
  local n = bedtime.is_night(b.cfg, ev.wall)
  if n == b.night then return nil end
  b.night = n
  return result(doc, b, i, { { kind = "log", level = "info", key = "bedtime.night", fields = { night = n } } })
end

--- Once a second while a timer runs: fade during the last minute (or last 20 s of the track), then pause.
function bedtime.on_tick(doc, ev)
  local b, i = bt_of(doc), int_of(doc)
  local cmds = {}
  local pb = doc.playback or {}
  if i.restore and pb.state ~= "playing" and pb.state ~= "starting" then
    i.restore = nil
    set_fade(i, 1)
  end
  if not i.sleep then
    cmds[#cmds + 1] = clear_sleep(b, i)
    return result(doc, b, i, cmds)
  end
  local f = 1
  if i.sleep.mode == "time" then
    local remaining = i.sleep.ends - ev.now
    if remaining <= 0 then
      -- done: pause the music (the fade stays until the pause is confirmed)
      i.restore = true
      cmds[#cmds + 1] = clear_sleep(b, i)
      cmds[#cmds + 1] = { kind = "log", level = "info", key = "bedtime.sleep_done" }
      cmds[#cmds + 1] = emit("playback.pause_request", { source = "sleep_timer", now = ev.now })
      return result(doc, b, i, cmds)
    end
    local fd = math.min(FADE_S, i.sleep.total / 3)
    if remaining < fd then f = remaining / fd end
  else
    local d = tonumber(pb.now and pb.now.duration_ms) or 0
    local p = tonumber(pb.position_ms) or 0
    if d > 0 and p > 0 and d - p < TRACK_FADE_MS then f = (d - p) / TRACK_FADE_MS end
  end
  if not i.restore then set_fade(i, f) end
  b.sleep = sleep_view(i, ev.now)
  return result(doc, b, i, cmds)
end

--- playback.changed { state }: automatic timer at night, restore after the pause, end-of-chapter stop.
function bedtime.on_playback(doc, ev)
  local b, i = bt_of(doc), int_of(doc)
  local cmds = {}
  local changed = false
  if ev.state == "playing" then
    if i.restore then i.restore = nil set_fade(i, 1) changed = true end
    if b.night and not i.sleep and b.cfg.timer > 0 then
      cmds[#cmds + 1] = start_sleep(b, i, ev.now, b.cfg.timer * 60, "time", true)
      cmds[#cmds + 1] = { kind = "log", level = "info", key = "bedtime.auto_timer", fields = { minutes = b.cfg.timer } }
      changed = true
    end
  elseif ev.state == "paused" or ev.state == "idle" then
    if i.restore then i.restore = nil set_fade(i, 1) changed = true end
  elseif ev.state == "ended" then
    if i.sleep and i.sleep.mode == "track" then
      cmds[#cmds + 1] = clear_sleep(b, i)
      set_fade(i, 1)
      cmds[#cmds + 1] = { kind = "log", level = "info", key = "bedtime.end_of_chapter" }
      changed = true
    end
  end
  if not changed and #cmds == 0 then return nil end
  return result(doc, b, i, cmds)
end

--- bedtime.sleep { seconds | minutes | mode = "track" | cancel = true }
function bedtime.on_sleep(doc, p, now)
  local b, i = bt_of(doc), int_of(doc)
  if p.cancel then
    local cmds = { clear_sleep(b, i) }
    i.restore = nil
    set_fade(i, 1)
    return result(doc, b, i, cmds)
  end
  if p.mode == "track" then
    return result(doc, b, i, { start_sleep(b, i, now, nil, "track"), { kind = "log", level = "info", key = "bedtime.sleep", fields = { mode = "track" } } })
  end
  local s = tonumber(p.seconds) or (tonumber(p.minutes) and tonumber(p.minutes) * 60)
  if not s or s < 1 or s > 4 * 3600 then return nil, { code = "invalid_argument", field = "seconds", message = "invalid duration" } end
  return result(doc, b, i, { start_sleep(b, i, now, math.floor(s), "time"), { kind = "log", level = "info", key = "bedtime.sleep", fields = { seconds = math.floor(s) } } })
end

local function hm(v)
  if type(v) == "number" and v >= 0 and v < 1440 then return math.floor(v) end
  if type(v) == "string" then
    local h, m = v:match("^(%d%d?):(%d%d)$")
    h, m = tonumber(h), tonumber(m)
    if h and m and h < 24 and m < 60 then return h * 60 + m end
  end
  return nil
end

--- bedtime.set { enabled?, start?, stop?, timer?, maxvol?, dim?, tzbase?, tzdst? }
function bedtime.on_set(doc, p, wall)
  if type(p) ~= "table" then return nil, { code = "invalid_argument", field = "", message = "invalid payload" } end
  local b, i = bt_of(doc), int_of(doc)
  local n = copy(b.cfg)
  for _, k in ipairs({ "enabled", "dim" }) do
    if p[k] ~= nil then
      if type(p[k]) ~= "boolean" then return nil, { code = "invalid_argument", field = k, message = "invalid " .. k } end
      n[k] = p[k]
    end
  end
  for _, k in ipairs({ "start", "stop" }) do
    if p[k] ~= nil then
      local v = hm(p[k])
      if not v then return nil, { code = "invalid_argument", field = k, message = "invalid " .. k } end
      n[k] = v
    end
  end
  local lim = { timer = { 0, 180 }, maxvol = { 5, 100 }, tzbase = { -840, 840 } }
  for k, r in pairs(lim) do
    if p[k] ~= nil then
      local v = tonumber(p[k])
      if not v or v < r[1] or v > r[2] then return nil, { code = "invalid_argument", field = k, message = "invalid " .. k } end
      n[k] = math.floor(v)
    end
  end
  if p.tzdst ~= nil then
    if p.tzdst ~= "EU" and p.tzdst ~= "none" then return nil, { code = "invalid_argument", field = "tzdst", message = "invalid tzdst" } end
    n.tzdst = p.tzdst
  end
  b.cfg = n
  b.night = bedtime.is_night(n, wall)
  return result(doc, b, i, { { kind = "files.write", path = path(doc), doc = n, version = 1 } })
end

local S = {}
S.sleep = { type = "object", additionalProperties = false, properties = { seconds = { type = "integer" }, minutes = { type = "integer" }, mode = { type = "string", enum = { "track" } }, cancel = { type = "boolean" } } }
S.set = { type = "object", additionalProperties = false, properties = { enabled = { type = "boolean" }, dim = { type = "boolean" }, start = { type = { "string", "integer" } }, stop = { type = { "string", "integer" } },
          timer = { type = "integer" }, maxvol = { type = "integer" }, tzbase = { type = "integer" }, tzdst = { type = "string" } } }
bedtime.schemas = S

function bedtime.install(api, dispatch)
  dispatch.on("boot", "bedtime", bedtime.on_boot)
  dispatch.on("timer", "bedtime", bedtime.on_timer)
  dispatch.on("playback.changed", "bedtime", bedtime.on_playback)
  api.command("bedtime.sleep", S.sleep, function(doc, p, ev) return bedtime.on_sleep(doc, p, ev.now) end)
  api.command("bedtime.set", S.set, function(doc, p, ev) return bedtime.on_set(doc, p, ev.wall) end)
end

return bedtime
