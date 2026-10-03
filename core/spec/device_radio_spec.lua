local radio = require("services.device.radio")
local buttons = require("services.device.buttons")

local function doc_with(o)
  o = o or {}
  return { config = { data_dir = "/d" }, audiocfg = o.audiocfg or { volume = 40, shuffle_mode = false, repeat_mode = 1 },
           activity = o.activity, flags = o.flags or {}, device = { toy_safe = true } }
end
local function kinds(r)
  local out = {}
  for _, c in ipairs((r and r.commands) or {}) do
    if c.kind == "bus.publish" then out[#out + 1] = c.topic:gsub("^/j/", "") .. " " .. c.payload
    elseif c.kind == "emit" then out[#out + 1] = "emit " .. c.event.type .. (c.event.name and " " .. c.event.name or "")
    elseif c.kind == "shell" then out[#out + 1] = "shell " .. c.action
    else out[#out + 1] = c.kind end
  end
  return out
end
-- Assertion rule: a handler's commands are a set, so `same` compares the whole set regardless of
-- order, `has` / `find` look for one command, and a positional `kinds(r)[n]` / `r.commands[n]` stays
-- only where the order itself is what is tested.
local function find(r, kind, key, val)
  for _, c in ipairs((r and r.commands) or {}) do
    if c.kind == kind and (key == nil or c[key] == val) then return c end
  end
  return nil
end
local function sorted(list) local out = {} for i, v in ipairs(list) do out[i] = v end table.sort(out) return out end
local function same(actual, expected, msg) assert_eq(sorted(actual), sorted(expected), msg) end

describe("services.device.radio — toy safe and the radios", function()
  it("toy safe sets the flag, the script and the ESP32", function()
    local doc = doc_with()
    local r = radio.on_toy_safe(doc, { enable = false })
    assert_false(r.state.device.toy_safe); assert_true(r.state.flags.TOY_SAFE_OFF)
    same(kinds(r), { "files.flag", "shell toysafe_update", "esp32/output/audio/set_toysafe 0", "emit lights.event Evt.ToySafe.Off" })
  end)

  it("radio.set switches the radios and the flags", function()
    local doc = doc_with()
    local r = radio.on_radio(doc, { wifi = false, bt = false })
    assert_true(r.state.flags.WIFI_OFF); assert_true(r.state.flags.BT_OFF)
    assert_eq(kinds(r)[3], "shell radio"); assert_eq(kinds(r)[4], "emit lights.event Evt.Airplane.Enable")
  end)

  it("the system tags drive toy safe and the radios; an unknown one is only logged", function()
    local doc = doc_with()
    assert_true(radio.on_system_tag(doc, { name = "sys.toy_safe_on" }).state.device.toy_safe)
    assert_false(radio.on_system_tag(doc, { name = "sys.toy_safe_off" }).state.device.toy_safe)
    local r = radio.on_system_tag(doc, { name = "sys.airplane_mode_on" })
    assert_true(r.state.flags.WIFI_OFF); assert_true(r.state.flags.BT_OFF)
    r = radio.on_system_tag(doc, { name = "sys.wifi_off" })
    assert_true(r.state.flags.WIFI_OFF); assert_nil(r.state.flags.BT_OFF)
    assert_eq(find(r, "shell", "action", "radio").args.bt, true)
    assert_eq(find(radio.on_system_tag(doc, { name = "sys.bt_off" }), "shell", "action", "radio").args.wifi, true)
    r = radio.on_system_tag(doc, { name = "sys.airplane_mode_off" })
    assert_nil(r.state.flags.WIFI_OFF); assert_eq(find(r, "emit").event.name, "Evt.Airplane.Disable")
    assert_eq(radio.on_system_tag(doc, { name = "sys.whatever" }).commands[1].key, "device.system_tag_ignored")
  end)

  it("boot: the flags become the state (toy safe on unless TOY_SAFE_OFF)", function()
    local r = radio.on_boot(doc_with(), { flags = { TOY_SAFE_OFF = true }, now = 5 })
    assert_false(r.state.device.toy_safe); assert_true(r.state.flags.TOY_SAFE_OFF); assert_false(r.state.device.airplane)
    assert_true(radio.on_boot(doc_with(), { flags = {}, now = 5 }).state.device.toy_safe)
  end)
end)

describe("services.device.radio — airplane mode from the page (always bounded)", function()
  local function flag_cmds(r)
    local out = {}
    for _, c in ipairs(r.commands) do if c.kind == "files.flag" then out[#out + 1] = c.name .. "=" .. tostring(c.set) end end
    return out
  end
  local function timer_cmds(r)
    local out = {}
    for _, c in ipairs(r.commands) do if c.kind == "timer.once" or c.kind == "timer.cancel" then out[#out + 1] = c.kind .. " " .. c.name .. (c.seconds and ("@" .. c.seconds) or "") end end
    return out
  end

  it("for N minutes: radios off, OJ_AIRPLANE flag, a timer, and the end time in the state", function()
    local doc = doc_with(); doc.device.airplane = false
    local r = radio.on_airplane(doc, { minutes = 120 }, { wall = 1000 })
    assert_true(r.state.flags.WIFI_OFF); assert_true(r.state.flags.BT_OFF); assert_true(r.state.flags.OJ_AIRPLANE)
    assert_eq(r.state.device.airplane.ends, 1000 + 120 * 60); assert_true(r.state.device.airplane.boot)
    local rd = find(r, "shell", "action", "radio")
    assert_eq(rd.args.wifi, false); assert_eq(rd.args.bt, false)
    same(flag_cmds(r), { "WIFI_OFF=true", "BT_OFF=true", "OJ_AIRPLANE=true" })
    assert_eq(timer_cmds(r), { "timer.once device.airplane@7200" })
  end)

  it("without minutes: until the next start only (no timer)", function()
    local doc = doc_with(); doc.device.airplane = false
    local r = radio.on_airplane(doc, {}, { wall = 1000 })
    assert_nil(r.state.device.airplane.ends); assert_true(r.state.device.airplane.boot)
    assert_eq(timer_cmds(r), { "timer.cancel device.airplane" })
    assert_true(find(r, "files.flag", "name", "OJ_AIRPLANE").set)
  end)

  it("refuses a duration outside 1 to 1440 minutes", function()
    for _, bad in ipairs({ 0, -5, 1441, "x" }) do
      local ok, err = radio.on_airplane(doc_with(), { minutes = bad }, { wall = 0 })
      assert_nil(ok); assert_eq(err.field, "minutes")
    end
  end)

  it("the timer switches the radios back on and drops the flag", function()
    local doc = doc_with({ flags = { WIFI_OFF = true, BT_OFF = true, OJ_AIRPLANE = true } }); doc.device.airplane = { ends = 5, boot = true }
    local r = radio.on_timer(doc, { name = "device.airplane", now = 9000 })
    assert_nil(r.state.flags.WIFI_OFF); assert_nil(r.state.flags.OJ_AIRPLANE); assert_false(r.state.device.airplane)
    assert_eq(find(r, "shell", "action", "radio").args.wifi, true); assert_eq(find(r, "emit").event.name, "Evt.Airplane.Disable")
    same(flag_cmds(r), { "WIFI_OFF=false", "BT_OFF=false", "OJ_AIRPLANE=false" })
    assert_eq(timer_cmds(r), { "timer.cancel device.airplane" })
    assert_nil(radio.on_timer(doc, { name = "other" }))
  end)

  it("cancel from the page does the same at once", function()
    local doc = doc_with({ flags = { OJ_AIRPLANE = true } }); doc.device.airplane = { boot = true }
    local r = radio.on_airplane(doc, { cancel = true }, { wall = 0 })
    assert_false(r.state.device.airplane); assert_eq(find(r, "shell", "action", "radio").args.wifi, true)
  end)

  it("the knob (held 5 s) overrides a bounded airplane mode: its timer and flag go", function()
    local doc = doc_with({ flags = { WIFI_OFF = true, BT_OFF = true, OJ_AIRPLANE = true } }); doc.device.airplane = { ends = 5, boot = true }
    doc.activity = { buttons = { airplane_mode_on = 0 } }
    local t = buttons.on_tick(doc, { now = 5 })
    same(kinds(t), { "emit radio.set", "timer.cancel" }); assert_nil(t.commands[1].event.bounded)
    local r = radio.on_radio(doc, t.commands[1].event)
    assert_false(r.state.device.airplane); assert_nil(r.state.flags.OJ_AIRPLANE)
    assert_eq(timer_cmds(r), { "timer.cancel device.airplane" })
    -- and a plain radio change with nothing to end adds nothing
    doc.device.airplane = false; doc.flags = {}
    r = radio.on_radio(doc, { wifi = false, bt = false })
    assert_nil(r.state.device); assert_eq(#r.commands, 4)
  end)

  it("boot with the OJ_AIRPLANE flag: the radios come back a few seconds later, whatever the ESP32 remembers", function()
    local r = radio.on_boot(doc_with(), { flags = { OJ_AIRPLANE = true, WIFI_OFF = true, BT_OFF = true }, now = 5 })
    assert_true(r.state.device.airplane.boot)
    local found
    for _, c in ipairs(r.commands) do if c.kind == "timer.once" and c.name == "device.airplane_restore" then found = c.seconds end end
    assert_eq(found, 3)
    local doc = doc_with({ flags = r.state.flags }); doc.device = r.state.device
    local t = radio.on_timer(doc, { name = "device.airplane_restore", now = 8 })
    assert_eq(find(t, "shell", "action", "radio").args.wifi, true); assert_false(find(t, "files.flag", "name", "OJ_AIRPLANE").set); assert_false(t.state.device.airplane)
    -- a normal boot schedules nothing of the kind
    r = radio.on_boot(doc_with(), { flags = {}, now = 5 })
    for _, c in ipairs(r.commands) do assert_true(c.name ~= "device.airplane_restore") end
  end)
end)
