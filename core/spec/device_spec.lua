local device = require("services.device")

-- o.jack = true: a Jooki with a wired headphone jack (config headphone_jack; the v2 default is none)
local function doc_with(o)
  o = o or {}
  return { config = { data_dir = "/d", headphone_jack = o.jack }, audiocfg = o.audiocfg or { volume = 40, shuffle_mode = false, repeat_mode = 1 },
           limits = o.limits, power = o.power, activity = o.activity, playback = o.playback, nfc = o.nfc, net = o.net, flags = o.flags or {}, device = { toy_safe = true } }
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
-- (the power-off sequence, in device_power_spec). So `same` compares the whole set regardless of order,
-- `has` / `find` look for one command, and a positional `kinds(r)[n]` / `r.commands[n]` stays only
-- where the order itself is what is tested.
local function find(r, kind, key, val)
  for _, c in ipairs((r and r.commands) or {}) do
    if c.kind == kind and (key == nil or c[key] == val) then return c end
  end
  return nil
end
local function has(r, kind, key, val) return find(r, kind, key, val) ~= nil end
local function sorted(list) local out = {} for i, v in ipairs(list) do out[i] = v end table.sort(out) return out end
local function same(actual, expected, msg) assert_eq(sorted(actual), sorted(expected), msg) end

describe("services.device — volume chain", function()
  it("applies the knob through the night limit and the fade, keeps the requested value", function()
    local doc = doc_with({ limits = { maxvol = 30, fade = 1 } })
    local r = device.on_gpio_volume(doc, { percent = 97 })
    assert_eq(r.state.audiocfg.volume, 97)
    same(kinds(r), { "vol 30", "write /d/audiocfg.json" })
    doc.limits = { maxvol = 100, fade = 0.5 }
    assert_eq(device.effective_volume(doc, 97), 49)
    assert_eq(kinds(device.on_apply_volume(doc)), { "vol 20" })   -- 40 * 0.5
  end)

  it("knob reports change the volume and the headphones only when they differ (jack enabled)", function()
    local doc = doc_with({ jack = true }); doc.device.esp32_up = true   -- the first answer only marks esp32_ctrl up (see boot spec)
    assert_nil(device.on_knobs(doc, { volume = 40, headphones = false }))
    local r = device.on_knobs(doc, { volume = 55, headphones = true })
    assert_eq(r.state.audiocfg.volume, 55); assert_true(r.state.audiocfg.headphones_en)
    assert_true(has(r, "host.volume", "percent", 55))
    assert_eq(find(r, "bus.publish", "topic", "/j/audio/out/set_output_device").payload, "headphones")
    assert_eq(find(r, "bus.publish", "topic", "/j/spotify/output/set_output_device").payload, "headphones")   -- Spotify follows the headphones too
  end)

  it("shuffle / repeat: one updater for the page (v1 booleans), the v2 command and the Spotify daemon", function()
    local doc = doc_with()
    local r = device.update_config(doc, { shuffle_mode = true, repeat_mode = false })        -- v1: false = none
    assert_true(r.state.audiocfg.shuffle_mode); assert_eq(r.state.audiocfg.repeat_mode, 0)
    same(kinds(r), { "write /d/audiocfg.json", "emit audiocfg.changed" })
    assert_eq(find(r, "emit").event.repeat_mode, false)                                     -- the raw value travels to streaming
    r = device.update_config(doc, { repeat_mode = "2" }, { silent = true })                   -- the daemon: strings, and no echo
    assert_eq(r.state.audiocfg.repeat_mode, 2); assert_eq(kinds(r), { "write /d/audiocfg.json" })
    r = device.update_config(doc, { repeat_mode = "x", shuffle_mode = 1 })                    -- unreadable: kept; not exactly true: off
    assert_eq(r.state.audiocfg.repeat_mode, 1); assert_false(r.state.audiocfg.shuffle_mode)
  end)
end)

describe("services.device — audio output / amplifier", function()
  local function amp_and_out(r)
    local amp, out
    for _, c in ipairs(r.commands) do
      if c.kind == "files.write_text" and c.path == "/sys/kernel/htdrv/amp_en" then amp = c.text end
      if c.kind == "bus.publish" and c.topic == "/j/audio/out/set_output_device" then out = c.payload end
    end
    return amp, out
  end

  it("boot turns the amplifier ON for the speaker (sound must work on battery, not only when plugged)", function()
    local amp, out = amp_and_out(device.on_boot(doc_with(), { audiocfg = { volume = 50 }, flags = {}, now = 5 }))
    assert_eq(amp, "1"); assert_eq(out, "speaker")
  end)

  it("v2 has no jack (default): a headphones report is ignored, the amplifier stays on the speaker", function()
    local doc = doc_with({ audiocfg = { volume = 40, headphones_en = false } }); doc.device.esp32_up = true
    assert_nil(device.on_knobs(doc, { headphones = true }))   -- ignored, nothing changes
    -- and a stale "headphones on" is cleared at boot so it can never keep the speaker off
    local r = device.on_boot(doc_with(), { audiocfg = { volume = 50, headphones_en = true }, flags = {}, now = 5 })
    local amp, out = amp_and_out(r)
    assert_eq(amp, "1"); assert_eq(out, "speaker"); assert_false(r.state.audiocfg.headphones_en)
  end)

  it("with a jack enabled, boot with headphones set routes to headphones and leaves the amplifier off", function()
    local amp, out = amp_and_out(device.on_boot(doc_with({ jack = true }), { audiocfg = { volume = 50, headphones_en = true }, flags = {}, now = 5 }))
    assert_eq(amp, "0"); assert_eq(out, "headphones")
  end)

  it("with a jack enabled, plugging headphones switches the amplifier off and back on when removed", function()
    local on = doc_with({ jack = true, audiocfg = { volume = 40, headphones_en = false } })
    assert_eq(select(1, amp_and_out(device.on_knobs(on, { headphones = true }))), "0")
    local off = doc_with({ jack = true, audiocfg = { volume = 40, headphones_en = true } })
    assert_eq(select(1, amp_and_out(device.on_knobs(off, { headphones = false }))), "1")
  end)
end)

describe("services.device — the time from the page (no RTC, no Internet)", function()
  local PHONE = 1790780000        -- 2026-09-30 14:53 UTC

  it("clock unset (1970 after a start without Internet): the phone's time is taken, and night mode is told", function()
    local r = device.on_clock(doc_with(), { utc = PHONE }, { wall = 75 })
    same(kinds(r), { "shell set_clock", "log", "emit clock.set" })
    assert_eq(find(r, "shell", "action", "set_clock").args.utc, PHONE)
    assert_eq(find(r, "log").fields.from, 75); assert_eq(find(r, "log").fields.to, PHONE)
    assert_nil(r.state)
  end)

  it("clock already set (ntpd, or a phone before): never moved, even by minutes", function()
    for _, wall in ipairs({ PHONE, PHONE - 3600, PHONE + 86400, device.CLOCK_MIN }) do
      local r = device.on_clock(doc_with(), { utc = PHONE }, { wall = wall })
      assert_eq(kinds(r), {})
    end
  end)

  it("refuses a time that is not a plausible now (before 2024, after 2099, not a number)", function()
    for _, bad in ipairs({ 0, 1600000000, 4102444800, "x" }) do
      local ok, err = device.on_clock(doc_with(), { utc = bad }, { wall = 75 })
      assert_nil(ok); assert_eq(err.field, "utc")
    end
  end)

  it("Wi-Fi from the API: refused plainly (a Jooki 2 learns a network over Bluetooth only)", function()
    assert_eq(device.WIFI_OVER_BLUETOOTH.message, "WIFI_OVER_BLUETOOTH")
  end)
end)

describe("services.device — boot, the ESP32 and the name", function()
  it("boot applies the saved volume and schedules its timers", function()
    local r = device.on_boot(doc_with(), { audiocfg = { volume = 70 }, flags = { TOY_SAFE_OFF = true }, now = 5 })
    assert_eq(r.state.audiocfg.volume, 70)
    assert_true(has(r, "host.volume", "percent", 70)); assert_eq(find(r, "emit").event.name, "Evt.Jooki.Ready")
    assert_true(has(r, "timer.every", "name", "device.knobs"))
    assert_false(has(r, "timer.every", "name", "device.tick"))   -- the long-press tick waits for a button
    -- after a restart by the Wi-Fi watchdog: no chime, and the marker file goes
    r = device.on_boot(doc_with(), { audiocfg = {}, flags = {}, now = 5, quiet_boot = true })
    local k = table.concat(kinds(r), "|")
    assert_nil(k:find("Evt.Jooki.Ready", 1, true))
  end)

  it("the bus back (broker restarted): the ESP32 hears the boot orders again, until it answers", function()
    local doc = doc_with(); doc.device.esp32_up = true
    local r = device.on_bus_up(doc)
    assert_false(r.state.device.esp32_up)
    local k = table.concat(kinds(r), "|")
    assert_true(k:find("esp32/output/nfc/mode/set 1", 1, true) ~= nil)
    assert_true(k:find("esp32/output/device/send_all_notifications", 1, true) ~= nil)
    local timers = 0
    for _, c in ipairs(r.commands) do if c.kind == "timer.once" and c.name:match("^device%.esp32_init%.%d$") then timers = timers + 1 end end
    assert_eq(timers, 3)
  end)

  it("boot tells the ESP32 at once, again at 1 and 3 s, until esp32_ctrl has answered once", function()
    local r = device.on_boot(doc_with(), { audiocfg = {}, flags = {}, now = 5 })
    local k = table.concat(kinds(r), "|")
    assert_true(k:find("esp32/output/nfc/mode/set 1", 1, true) ~= nil)
    local onces = {}
    for _, c in ipairs(r.commands) do if c.kind == "timer.once" then onces[#onces + 1] = c.name .. "@" .. c.seconds end end
    same(onces, { "device.esp32_init.1@1", "device.esp32_init.2@3" })
    local doc = doc_with()
    local t = device.on_timer(doc, { name = "device.esp32_init.1", now = 6 })
    same(kinds(t), { "esp32/output/device/send_all_notifications ", "esp32/output/nfc/mode/set 1", "esp32/output/knobs/state " })
    -- the knobs answer (nothing else changes) marks esp32_ctrl as listening: no more resends
    doc.audiocfg.volume = 40
    local kr = device.on_knobs(doc, { volume = 40 })
    assert_true(kr.state.device.esp32_up); assert_true(kr.state.device.toy_safe)
    doc.device = kr.state.device
    assert_nil(device.on_timer(doc, { name = "device.esp32_init.2", now = 8 }))
    assert_nil(device.on_knobs(doc, { volume = 40 }))
  end)

  it("the facade's on_timer reaches the sub-modules' timers too (the kernel routes each name itself)", function()
    local doc = doc_with({ activity = { last = 0 }, power = { connected = false } })
    assert_eq(find(device.on_timer(doc, { name = "device.inactivity", now = 901 }), "emit").event.type, "power.off_request")
    assert_nil(device.on_timer(doc, { name = "device.unknown", now = 1 }))
  end)

  it("set_name: normalizes, checks, changes device.hostname and net.name; empty = factory name", function()
    local doc = doc_with({ net = { name = "jooki2-a1b2c3.local", ip = "10.0.0.2" } }); doc.device.id = "jooki2-A1B2C3"
    local r = device.on_set_name(doc, "  Jooki.local ")
    assert_eq(r.state.device.hostname, "jooki.local"); assert_eq(r.state.net.name, "jooki.local"); assert_eq(r.state.net.ip, "10.0.0.2")
    assert_eq(find(r, "shell", "action", "set_name").args.name, "jooki")
    r = device.on_set_name(doc, "")
    assert_eq(r.state.device.hostname, "jooki2-a1b2c3.local"); assert_eq(find(r, "shell", "action", "set_name").args.name, "")
    for _, bad in ipairs({ "jo oki", "-a", "a-", "localhost", "x;reboot", string.rep("a", 33) }) do
      local ok, err = device.on_set_name(doc, bad)
      assert_nil(ok); assert_eq(err.code, "invalid_argument")
    end
  end)
end)
