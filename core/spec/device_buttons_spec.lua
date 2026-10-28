local buttons = require("services.device.buttons")
local radio = require("services.device.radio")

local function doc_with(o)
  o = o or {}
  return { config = { data_dir = "/d" }, audiocfg = o.audiocfg or { volume = 40, shuffle_mode = false, repeat_mode = 1 },
           activity = o.activity, flags = o.flags or {}, device = { toy_safe = true } }
end
local function kinds(r)
  local out = {}
  for _, c in ipairs((r and r.commands) or {}) do
    if c.kind == "host.volume" then out[#out + 1] = "vol " .. c.percent
    elseif c.kind == "emit" then out[#out + 1] = "emit " .. c.event.type .. (c.event.name and " " .. c.event.name or "")
    elseif c.kind == "shell" then out[#out + 1] = "shell " .. c.action
    elseif c.kind == "files.write" then out[#out + 1] = "write " .. c.path
    else out[#out + 1] = c.kind end
  end
  return out
end
-- Assertion rule: a handler's commands are a set, so `same` compares the whole set regardless of
-- order, and a positional `kinds(r)[n]` / `r.commands[n]` stays only where the order itself is what is tested.
local function sorted(list) local out = {} for i, v in ipairs(list) do out[i] = v end table.sort(out) return out end
local function same(actual, expected, msg) assert_eq(sorted(actual), sorted(expected), msg) end

describe("services.device.buttons — presses and long presses", function()
  it("next/prev on release, circle long press -> power off, four buttons -> speak info", function()
    local doc = doc_with()
    local r = buttons.on_button(doc, { button = "next", down = true, now = 1 })
    assert_eq(r.state.activity.buttons.next, 1)
    assert_eq(kinds(r), { "timer.every" }); assert_eq(r.commands[1].name, "device.tick")   -- the first button held starts the long-press tick
    doc.activity = r.state.activity
    r = buttons.on_button(doc, { button = "next", down = false, now = 1.3 })
    same(kinds(r), { "emit playback.next", "timer.cancel" })                             -- the last one up stops it
    doc.activity = { buttons = { circle = 10 }, last = 10 }
    assert_nil(buttons.on_tick(doc, { now = 11 }))
    r = buttons.on_timer(doc, { name = "device.tick", now = 12.1 })
    same(kinds(r), { "emit power.off_request", "timer.cancel" }); assert_nil(r.state.activity.buttons.circle)
    assert_nil(buttons.on_timer(doc, { name = "other", now = 12.1 }))
    doc.activity = { buttons = { next = 1, prev = 1, vol_inc = 1 } }
    r = buttons.on_button(doc, { button = "vol_dec", down = true, now = 1 })
    same(kinds(r), { "shell speak_info", "emit playback.pause_request", "timer.cancel" })
    -- a second button down while one is held: the tick already runs, nothing is added
    doc.activity = { buttons = { circle = 1 } }
    assert_eq(kinds(buttons.on_button(doc, { button = "next", down = true, now = 2 })), {})
  end)

  it("volume buttons step by 10 within 0-100", function()
    local doc = doc_with({ audiocfg = { volume = 95 } })
    doc.activity = { buttons = { vol_inc = 1 } }
    local r = buttons.on_button(doc, { button = "vol_inc", down = false, now = 1.2 })
    assert_eq(r.state.audiocfg.volume, 100)
    same(kinds(r), { "vol 100", "write /d/audiocfg.json", "timer.cancel" })
  end)

  it("airplane long press toggles the radios and the flags", function()
    local doc = doc_with()
    doc.activity = { buttons = { airplane_mode_on = 0 } }
    local r = buttons.on_tick(doc, { now = 5 })
    same(kinds(r), { "emit radio.set", "timer.cancel" })
    r = radio.on_radio(doc, r.commands[1].event)
    assert_true(r.state.flags.WIFI_OFF); assert_true(r.state.flags.BT_OFF)
  end)

  it("prev + next held 10 s: the parent code is cleared (physical reset)", function()
    local doc = doc_with()
    doc.activity = { buttons = { prev = 0, next = 1 } }
    assert_nil(buttons.on_tick(doc, { now = 10.5 }))
    local r = buttons.on_tick(doc, { now = 11 })
    same(kinds(r), { "emit security.parent_clear", "timer.cancel" })
    assert_true(r.commands[1].event.physical); assert_nil(r.state.activity.buttons.prev); assert_nil(r.state.activity.buttons.next)
  end)

  it("Jooki 2 (one knob): volume all the way down, knob held on prev 10 s -> parent code cleared; the release plays nothing", function()
    local doc = doc_with({ audiocfg = { volume = 0, shuffle_mode = false, repeat_mode = 1 }, activity = { buttons = { prev = 0 } } })
    assert_nil(buttons.on_tick(doc, { now = 9.5 }))
    local r = buttons.on_tick(doc, { now = 10 })
    same(kinds(r), { "emit security.parent_clear", "timer.cancel" })
    assert_true(r.commands[1].event.physical)
    doc.activity = r.state.activity
    local rel = buttons.on_button(doc, { button = "prev", down = false, now = 11 })
    same(kinds(rel), {})
  end)

  it("the knob held on prev 10 s with the volume up: no reset (a child holding it), prev on release as usual", function()
    local doc = doc_with({ audiocfg = { volume = 40, shuffle_mode = false, repeat_mode = 1 }, activity = { buttons = { prev = 0 } } })
    assert_nil(buttons.on_tick(doc, { now = 12 }))
    local rel = buttons.on_button(doc, { button = "prev", down = false, now = 12.5 })
    same(kinds(rel), { "emit playback.prev", "timer.cancel" })
  end)

  it("the heart's short press does what Settings say: nothing by default, the next track, or pause / play", function()
    local function short(choice)
      local doc = doc_with({ audiocfg = { volume = 40, heart_press = choice }, activity = { buttons = { circle = 5 } } })
      return buttons.on_button(doc, { button = "circle", down = false, now = 5.4 })
    end
    same(kinds(short(nil)), { "timer.cancel" })
    same(kinds(short("none")), { "timer.cancel" })
    same(kinds(short("next")), { "emit playback.next", "timer.cancel" })
    local r = short("pause")
    same(kinds(r), { "emit playback.toggle_request", "timer.cancel" })
    local ev
    for _, c in ipairs(r.commands) do if c.kind == "emit" then ev = c.event end end
    assert_eq(ev.source, "button"); assert_eq(ev.now, 5.4)
    -- held 2 s it switches off (the tick), and the release that follows does nothing more
    local doc = doc_with({ audiocfg = { volume = 40, heart_press = "next" }, activity = { buttons = { circle = 10 } } })
    r = buttons.on_tick(doc, { now = 12.1 })
    same(kinds(r), { "emit power.off_request", "timer.cancel" })
    doc.activity = r.state.activity
    same(kinds(buttons.on_button(doc, { button = "circle", down = false, now = 12.5 })), {})
  end)

  it("the knob held halfway winds the track after 1 s, 10 s at each tick; a turn to next crosses the zone without winding", function()
    local doc = doc_with({ activity = { buttons = { fwd = 3 } } })
    assert_nil(buttons.on_tick(doc, { now = 3.5 }))
    local r = buttons.on_tick(doc, { now = 4 })
    assert_eq(kinds(r), { "emit playback.skip_request" }); assert_eq(r.commands[1].event.seconds, 10)
    assert_nil(r.state)                                     -- still held: the tick goes on
    r = buttons.on_tick(doc, { now = 4.5 })
    assert_eq(r.commands[1].event.seconds, 10)
    doc.activity = { buttons = { rew = 3 } }
    r = buttons.on_tick(doc, { now = 4.1 })
    assert_eq(r.commands[1].event.seconds, -10)
    -- released: nothing on release, the tick stops
    same(kinds(buttons.on_button(doc, { button = "rew", down = false, now = 4.2 })), { "timer.cancel" })
    -- a whole turn: fwd in, fwd out at once, then next: only the next track
    doc = doc_with()
    r = buttons.on_button(doc, { button = "fwd", down = true, now = 1 }); doc.activity = r.state.activity
    r = buttons.on_button(doc, { button = "fwd", down = false, now = 1.05 }); doc.activity = r.state.activity
    r = buttons.on_button(doc, { button = "next", down = true, now = 1.06 }); doc.activity = r.state.activity
    r = buttons.on_button(doc, { button = "next", down = false, now = 1.3 })
    same(kinds(r), { "emit playback.next", "timer.cancel" })
  end)
end)
