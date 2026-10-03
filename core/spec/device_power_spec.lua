local power = require("services.device.power")

local function doc_with(o)
  o = o or {}
  return { config = { data_dir = "/d" }, audiocfg = o.audiocfg or { volume = 40, shuffle_mode = false, repeat_mode = 1 },
           limits = o.limits, power = o.power, activity = o.activity, playback = o.playback, flags = o.flags or {}, device = { toy_safe = true } }
end
local function kinds(r)
  local out = {}
  for _, c in ipairs((r and r.commands) or {}) do
    if c.kind == "host.volume" then out[#out + 1] = "vol " .. c.percent
    elseif c.kind == "bus.publish" then out[#out + 1] = c.topic:gsub("^/j/", "") .. " " .. c.payload
    elseif c.kind == "emit" then out[#out + 1] = "emit " .. c.event.type .. (c.event.name and " " .. c.event.name or "")
    elseif c.kind == "shell" then out[#out + 1] = "shell " .. c.action
    elseif c.kind == "files.write" then out[#out + 1] = "write " .. c.path
    else out[#out + 1] = c.kind end
  end
  return out
end
-- Assertion rule: a handler's commands are a set unless their order is a requirement of the device
-- (the power-off sequence: save, lights, quit, poweroff, then the kernel's shutdown). So `same`
-- compares the whole set regardless of order, `has` / `find` look for one command, and a positional
-- `kinds(r)` stays only where the order itself is what is tested.
local function find(r, kind, key, val)
  for _, c in ipairs((r and r.commands) or {}) do
    if c.kind == kind and (key == nil or c[key] == val) then return c end
  end
  return nil
end
local function has(r, kind, key, val) return find(r, kind, key, val) ~= nil end
local function sorted(list) local out = {} for i, v in ipairs(list) do out[i] = v end table.sort(out) return out end
local function same(actual, expected, msg) assert_eq(sorted(actual), sorted(expected), msg) end

describe("services.device.power — battery, cable, inactivity", function()
  it("battery: warning under 20 % every 5 min, shutdown under 10 %, nothing while charging", function()
    local doc = doc_with({ power = { charging = false } })
    local r = power.on_battery(doc, { mv = 3600, tenths = 150, mc = 30000, now = 100 })
    assert_eq(kinds(r), { "emit system.event Evt.Power.Low.Warning" })
    doc.power = r.state.power
    assert_eq(kinds(power.on_battery(doc, { tenths = 150, now = 200 })), {})
    assert_eq(kinds(power.on_battery(doc, { tenths = 150, now = 401 })), { "emit system.event Evt.Power.Low.Warning" })
    r = power.on_battery(doc, { tenths = 90, now = 500 })
    assert_eq(find(r, "emit").event.after.type, "power.off_request")
    doc.power.charging = true
    assert_eq(kinds(power.on_battery(doc, { tenths = 50, now = 600 })), {})
  end)

  it("overheat: toy safe, volume 80, script", function()
    local doc = doc_with()
    local r = power.on_battery(doc, { mc = 85000, tenths = 900, now = 1 })
    same(kinds(r), { "log", "emit device.toy_safe_request", "shell power_overheat", "vol 80", "write /d/audiocfg.json" })
  end)

  it("plug and charge events set state and lights only after the first report", function()
    local doc = doc_with({ power = {} })
    local r = power.on_plugged(doc, { on = true })
    assert_true(r.state.power.connected); assert_eq(kinds(r), {})
    doc.power = r.state.power
    r = power.on_plugged(doc, { on = false })
    same(kinds(r), { "files.write_text", "emit system.event Evt.Power.Cable.Remove" })
    assert_nil(power.on_plugged(doc, { on = true }))
  end)

  it("inactivity: warns at 14 min, powers off at 15, unless playing / plugged / BT / STAY_ON", function()
    local doc = doc_with({ activity = { last = 0 }, power = { connected = false } })
    assert_nil(power.on_inactivity(doc, { now = 800 }))
    local r = power.on_inactivity(doc, { now = 841 })
    assert_eq(kinds(r), { "emit lights.event Evt.Power.Inactivity.Warning" }); doc.activity = r.state.activity
    r = power.on_inactivity(doc, { now = 901 })
    assert_eq(find(r, "emit").event.type, "power.off_request")
    doc.playback = { state = "playing" }
    r = power.on_inactivity(doc, { now = 902 })
    assert_eq(r.state.activity.last, 902)
    doc.playback = nil; doc.flags = { STAY_ON = true }
    assert_nil(power.on_inactivity(doc, { now = 2000 }))
    doc.flags = {}; doc.power.connected = true
    assert_eq(power.on_inactivity(doc, { now = 2000 }).state.activity.last, 2000)
  end)

  it("power off: sound first, then save, lights, quit, poweroff, kernel shutdown", function()
    local doc = doc_with()
    local r = power.on_off_request(doc, { reason = "button" })
    assert_eq(find(r, "emit").event.name, "Evt.Jooki.Poweroff"); assert_eq(find(r, "emit").event.after, { type = "shutdown.request", reason = "button" })
    r = power.on_shutdown_request(doc, { reason = "button" })
    -- the order IS the point here: save, lights, quit the daemons, sync, poweroff, and the kernel's shutdown last
    assert_eq(kinds(r), { "write /d/audiocfg.json", "led/output/set_raw ALL,0,0,0", "led/output/set_raw CIRCLE,200,0,0", "all/quit \"from-player\"", "shell sync", "shell poweroff", "shutdown" })
    r = power.on_shutdown_request(doc, { reason = "signal" })
    assert_eq(kinds(r)[#kinds(r)], "shutdown"); assert_false(has(r, "shell", "action", "poweroff"))
  end)
end)

describe("services.device.power — boot", function()
  it("boot schedules the inactivity timer and starts the activity clock", function()
    local r = power.on_boot(doc_with(), { now = 5 })
    assert_true(has(r, "timer.every", "name", "device.inactivity"))
    assert_eq(r.state.activity, { last = 5, buttons = {} })
    assert_eq(power.on_timer(doc_with({ activity = { last = 0 }, power = { connected = false } }), { name = "device.inactivity", now = 901 }).commands[2].event.type, "power.off_request")
    assert_nil(power.on_timer(doc_with(), { name = "other" }))
  end)

  it("boot reads the charger: plugged in at start never powers off for inactivity, and no cable sound", function()
    local r = power.on_boot(doc_with(), { now = 5, plugged = "1" })
    assert_true(r.state.power.connected)
    local doc = doc_with({ activity = { last = 0 }, power = r.state.power })
    assert_eq(power.on_inactivity(doc, { now = 5000 }).state.activity.last, 5000)
    assert_nil(power.on_plugged(doc, { on = true }))
    assert_false(power.on_boot(doc_with(), { now = 5, plugged = "0" }).state.power.connected)
    assert_nil(power.on_boot(doc_with(), { now = 5 }).state.power.connected)
  end)
end)
