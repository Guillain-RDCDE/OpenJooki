local bedtime = require("services.bedtime")

-- os.time interprets the table as local time; correct by the local offset so the result is the UTC instant
local function at(y, mo, d, h, mi)
  local t = os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = 0, isdst = false })
  local u = os.date("!*t", t)
  local delta = (u.hour * 3600 + u.min * 60) - (h * 3600 + mi * 60)
  if delta > 43200 then delta = delta - 86400 elseif delta < -43200 then delta = delta + 86400 end
  return t - delta
end

local function doc_with(o)
  o = o or {}
  return { config = { data_dir = "/d" }, bedtime = o.bedtime, bedtime_int = o.int, limits = o.limits, playback = o.playback or { state = "idle" } }
end
local function kinds(r)
  local out = {}
  for _, c in ipairs((r and r.commands) or {}) do
    if c.kind == "emit" then out[#out + 1] = "emit " .. c.event.type
    elseif c.kind == "timer.every" or c.kind == "timer.cancel" then out[#out + 1] = c.kind .. " " .. c.name
    elseif c.kind == "files.write" then out[#out + 1] = "write " .. c.path
    elseif c.kind == "log" then out[#out + 1] = "log " .. c.key end
  end
  return out
end
local function apply(doc, r) for k, v in pairs((r and r.state) or {}) do doc[k] = v end return doc end

describe("services.bedtime — clock", function()
  local cfg = { enabled = true, start = 1200, stop = 420, tzbase = 60, tzdst = "EU" }
  it("Paris: +1 in winter, +2 in summer, EU change days", function()
    assert_eq(bedtime.local_minutes(cfg, at(2026, 1, 15, 19, 30)), 20 * 60 + 30)
    assert_eq(bedtime.local_minutes(cfg, at(2026, 7, 15, 18, 30)), 20 * 60 + 30)
    assert_eq(bedtime.local_minutes(cfg, at(2026, 3, 29, 0, 59)), 119)
    assert_eq(bedtime.local_minutes(cfg, at(2026, 3, 29, 1, 0)), 180)
    assert_eq(bedtime.local_minutes(cfg, at(2026, 10, 25, 0, 59)), 179)
    assert_eq(bedtime.local_minutes(cfg, at(2026, 10, 25, 1, 0)), 120)
    assert_nil(bedtime.local_minutes(cfg, at(1970, 1, 2, 0, 5)))
  end)
  it("night window across midnight and same-day, disabled", function()
    local function night(h, m) return bedtime.is_night(cfg, at(2026, 1, 15, (h - 1) % 24, m)) end
    assert_false(night(19, 59)); assert_true(night(20, 0)); assert_true(night(3, 0)); assert_true(night(6, 59)); assert_false(night(7, 0))
    local c2 = { enabled = true, start = 780, stop = 930, tzbase = 0, tzdst = "none" }
    assert_true(bedtime.is_night(c2, at(2026, 1, 15, 14, 0))); assert_false(bedtime.is_night(c2, at(2026, 1, 15, 15, 30)))
    assert_false(bedtime.is_night({ enabled = false, start = 0, stop = 1439 }, at(2026, 1, 15, 14, 0)))
  end)
end)

describe("services.bedtime — settings and night limits", function()
  it("boot: defaults, file values of the right type, timers, limits", function()
    local r = bedtime.on_boot(doc_with(), { bedtime = { maxvol = 40, start = "bad" }, wall = at(2026, 1, 15, 22, 0) })
    assert_eq(r.state.bedtime.cfg.maxvol, 40); assert_eq(r.state.bedtime.cfg.start, 1200)
    assert_true(r.state.bedtime.night)
    assert_eq(r.state.limits, { maxvol = 40, fade = 1, dim = true })
    assert_eq(kinds(r)[1], "timer.every bedtime.clock")
  end)

  it("set: validation, persistence, limits recomputed", function()
    local doc = apply(doc_with(), bedtime.on_boot(doc_with(), { wall = at(2026, 1, 15, 14, 0) }))
    local _, err = bedtime.on_set(doc, { start = "25:00" }, at(2026, 1, 15, 14, 0)); assert_eq(err.field, "start")
    _, err = bedtime.on_set(doc, { maxvol = 3 }, 0); assert_eq(err.field, "maxvol")
    _, err = bedtime.on_set(doc, { enabled = "yes" }, 0); assert_eq(err.field, "enabled")
    _, err = bedtime.on_set(doc, { tzdst = "US" }, 0); assert_eq(err.field, "tzdst")
    local r = bedtime.on_set(doc, { start = "13:00", stop = "15:30", tzbase = 0, tzdst = "none", maxvol = 30 }, at(2026, 1, 15, 14, 0))
    assert_true(r.state.bedtime.night)
    assert_eq(r.state.limits, { maxvol = 30, fade = 1, dim = true })
    assert_eq(kinds(r), { "write /d/bedtime.json", "emit limits.changed" })
    doc = apply(doc, r)
    r = bedtime.on_clock(doc, { wall = at(2026, 1, 15, 16, 0) })
    assert_false(r.state.bedtime.night); assert_eq(r.state.limits.maxvol, 100)
    assert_nil(bedtime.on_clock(doc, { wall = at(2026, 1, 15, 14, 30) }))
  end)
end)

describe("services.bedtime — sleep timer", function()
  local function playing_doc()
    local doc = apply(doc_with(), bedtime.on_boot(doc_with(), { wall = at(2026, 1, 15, 14, 0) }))
    doc.playback = { state = "playing", position_ms = 0, now = { duration_ms = 300000 } }
    return doc
  end

  it("counts down, fades over the last third (max 60 s), then pauses and restores the volume", function()
    local doc = playing_doc()
    local r = bedtime.on_sleep(doc, { seconds = 90 }, 1000)
    assert_eq(r.state.bedtime.sleep, { mode = "time", remaining = 90, total = 90 })
    assert_eq(kinds(r)[1], "timer.every bedtime.tick")
    doc = apply(doc, r)
    r = bedtime.on_tick(doc, { now = 1050 }); doc = apply(doc, r)
    assert_eq(doc.limits.fade, 1)
    r = bedtime.on_tick(doc, { now = 1075 }); doc = apply(doc, r)
    assert_true(doc.limits.fade < 0.6 and doc.limits.fade > 0.3)
    assert_eq(kinds(r), { "emit limits.changed" })
    r = bedtime.on_tick(doc, { now = 1089 }); doc = apply(doc, r)
    assert_true(doc.limits.fade <= 0.05)
    r = bedtime.on_tick(doc, { now = 1090 })
    assert_eq(kinds(r), { "timer.cancel bedtime.tick", "log bedtime.sleep_done", "emit playback.pause_request" })
    assert_eq(r.commands[3].event.source, "sleep_timer")
    doc = apply(doc, r)
    assert_false(doc.bedtime.sleep)
    assert_true(doc.limits.fade <= 0.05, "still silent while pausing")
    r = bedtime.on_playback(doc, { state = "paused", now = 1091 })
    assert_eq(r.state.limits.fade, 1)
  end)

  it("cancel restores at once; invalid durations are refused", function()
    local doc = playing_doc()
    doc = apply(doc, bedtime.on_sleep(doc, { minutes = 1 }, 0))
    doc = apply(doc, bedtime.on_tick(doc, { now = 50 }))
    assert_true(doc.limits.fade < 1)
    local r = bedtime.on_sleep(doc, { cancel = true }, 51)
    assert_eq(r.state.limits.fade, 1); assert_false(r.state.bedtime.sleep)
    assert_eq(kinds(r)[1], "timer.cancel bedtime.tick")
    local _, err = bedtime.on_sleep(doc, { minutes = 0 }, 0); assert_eq(err.field, "seconds")
    _, err = bedtime.on_sleep(doc, {}, 0); assert_eq(err.field, "seconds")
  end)

  it("end of chapter: fade over the last 20 s, stop flag for playback, cleared when the track ends", function()
    local doc = playing_doc()
    doc = apply(doc, bedtime.on_sleep(doc, { mode = "track" }, 0))
    assert_true(doc.bedtime_int.stop_at_end)
    doc.playback.position_ms = 290000
    doc = apply(doc, bedtime.on_tick(doc, { now = 1 }))
    assert_true(doc.limits.fade < 0.6)
    local r = bedtime.on_playback(doc, { state = "ended", now = 2 })
    assert_nil(r.state.bedtime_int.stop_at_end); assert_eq(r.state.limits.fade, 1); assert_false(r.state.bedtime.sleep)
  end)

  it("night: playback gets the automatic timer, day: not", function()
    local doc = apply(doc_with(), bedtime.on_boot(doc_with(), { wall = at(2026, 1, 15, 22, 0) }))
    local r = bedtime.on_playback(doc, { state = "playing", now = 10 })
    assert_eq(r.state.bedtime.sleep.auto, true); assert_eq(r.state.bedtime.sleep.total, 1200)
    doc = apply(doc_with(), bedtime.on_boot(doc_with(), { wall = at(2026, 1, 15, 14, 0) }))
    assert_nil(bedtime.on_playback(doc, { state = "playing", now = 10 }))
  end)
end)
