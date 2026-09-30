local device = require("services.device")

local function doc_with(o)
  o = o or {}
  return { config = { data_dir = "/d" }, audiocfg = o.audiocfg or { volume = 40, shuffle_mode = false, repeat_mode = 1 },
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

describe("services.device — volume chain", function()
  it("applies the knob through the night limit and the fade, keeps the requested value", function()
    local doc = doc_with({ limits = { maxvol = 30, fade = 1 } })
    local r = device.on_gpio_volume(doc, { percent = 97 })
    assert_eq(r.state.audiocfg.volume, 97)
    assert_eq(kinds(r), { "vol 30", "write /d/audiocfg.json" })
    doc.limits = { maxvol = 100, fade = 0.5 }
    assert_eq(device.effective_volume(doc, 97), 49)
    assert_eq(kinds(device.on_apply_volume(doc)), { "vol 20" })   -- 40 * 0.5
  end)

  it("knob reports change the volume and the headphones only when they differ", function()
    local doc = doc_with(); doc.device.esp32_up = true   -- the first answer only marks esp32_ctrl up (see boot spec)
    assert_nil(device.on_knobs(doc, { volume = 40, headphones = false }))
    local r = device.on_knobs(doc, { volume = 55, headphones = true })
    assert_eq(r.state.audiocfg.volume, 55); assert_true(r.state.audiocfg.headphones_en)
    assert_eq(kinds(r)[1], "vol 55"); assert_eq(kinds(r)[3], "audio/out/set_output_device headphones")
    assert_eq(kinds(r)[4], "spotify/output/set_output_device headphones")   -- Spotify follows the headphones too
  end)

  it("volume buttons step by 10 within 0-100", function()
    local doc = doc_with({ audiocfg = { volume = 95 } })
    doc.activity = { buttons = { vol_inc = 1 } }
    local r = device.on_button(doc, { button = "vol_inc", down = false, now = 1.2 })
    assert_eq(r.state.audiocfg.volume, 100)
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

  it("boot with headphones set routes to headphones and leaves the amplifier off", function()
    local amp, out = amp_and_out(device.on_boot(doc_with(), { audiocfg = { volume = 50, headphones_en = true }, flags = {}, now = 5 }))
    assert_eq(amp, "0"); assert_eq(out, "headphones")
  end)

  it("plugging in headphones switches the amplifier off and back on when removed", function()
    local on = doc_with({ audiocfg = { volume = 40, headphones_en = false } })
    local amp1 = select(1, amp_and_out(device.on_knobs(on, { headphones = true })))
    assert_eq(amp1, "0")
    local off = doc_with({ audiocfg = { volume = 40, headphones_en = true } })
    local amp2 = select(1, amp_and_out(device.on_knobs(off, { headphones = false })))
    assert_eq(amp2, "1")
  end)
end)

describe("services.device — buttons", function()
  it("next/prev on release, circle long press -> power off, four buttons -> speak info", function()
    local doc = doc_with()
    local r = device.on_button(doc, { button = "next", down = true, now = 1 })
    assert_eq(r.state.activity.buttons.next, 1); assert_eq(kinds(r), {})
    doc.activity = r.state.activity
    r = device.on_button(doc, { button = "next", down = false, now = 1.3 })
    assert_eq(kinds(r), { "emit playback.next" })
    doc.activity = { buttons = { circle = 10 }, last = 10 }
    assert_nil(device.on_tick(doc, { now = 11 }))
    r = device.on_tick(doc, { now = 12.1 })
    assert_eq(kinds(r), { "emit power.off_request" }); assert_nil(r.state.activity.buttons.circle)
    doc.activity = { buttons = { next = 1, prev = 1, vol_inc = 1 } }
    r = device.on_button(doc, { button = "vol_dec", down = true, now = 1 })
    assert_eq(kinds(r), { "shell speak_info", "emit playback.pause_request" })
  end)

  it("airplane long press toggles the radios and the flags", function()
    local doc = doc_with()
    doc.activity = { buttons = { airplane_mode_on = 0 } }
    local r = device.on_tick(doc, { now = 5 })
    assert_eq(kinds(r), { "emit radio.set" })
    r = device.on_radio(doc, { wifi = false, bt = false })
    assert_true(r.state.flags.WIFI_OFF); assert_true(r.state.flags.BT_OFF)
    assert_eq(kinds(r)[3], "shell radio"); assert_eq(kinds(r)[4], "emit lights.event Evt.Airplane.Enable")
  end)
end)

describe("services.device — airplane mode from the page (always bounded)", function()
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
    local r = device.on_airplane(doc, { minutes = 120 }, { wall = 1000 })
    assert_true(r.state.flags.WIFI_OFF); assert_true(r.state.flags.BT_OFF); assert_true(r.state.flags.OJ_AIRPLANE)
    assert_eq(r.state.device.airplane.ends, 1000 + 120 * 60); assert_true(r.state.device.airplane.boot)
    assert_eq(kinds(r)[3], "shell radio"); assert_eq(r.commands[3].args.wifi, false); assert_eq(r.commands[3].args.bt, false)
    assert_eq(flag_cmds(r), { "WIFI_OFF=true", "BT_OFF=true", "OJ_AIRPLANE=true" })
    assert_eq(timer_cmds(r), { "timer.once device.airplane@7200" })
  end)

  it("without minutes: until the next start only (no timer)", function()
    local doc = doc_with(); doc.device.airplane = false
    local r = device.on_airplane(doc, {}, { wall = 1000 })
    assert_nil(r.state.device.airplane.ends); assert_true(r.state.device.airplane.boot)
    assert_eq(timer_cmds(r), { "timer.cancel device.airplane" })
    assert_eq(flag_cmds(r)[3], "OJ_AIRPLANE=true")
  end)

  it("refuses a duration outside 1 to 1440 minutes", function()
    for _, bad in ipairs({ 0, -5, 1441, "x" }) do
      local ok, err = device.on_airplane(doc_with(), { minutes = bad }, { wall = 0 })
      assert_nil(ok); assert_eq(err.field, "minutes")
    end
  end)

  it("the timer switches the radios back on and drops the flag", function()
    local doc = doc_with({ flags = { WIFI_OFF = true, BT_OFF = true, OJ_AIRPLANE = true } }); doc.device.airplane = { ends = 5, boot = true }
    local r = device.on_timer(doc, { name = "device.airplane", now = 9000 })
    assert_nil(r.state.flags.WIFI_OFF); assert_nil(r.state.flags.OJ_AIRPLANE); assert_false(r.state.device.airplane)
    assert_eq(r.commands[3].args.wifi, true); assert_eq(kinds(r)[4], "emit lights.event Evt.Airplane.Disable")
    assert_eq(flag_cmds(r), { "WIFI_OFF=false", "BT_OFF=false", "OJ_AIRPLANE=false" })
    assert_eq(timer_cmds(r), { "timer.cancel device.airplane" })
  end)

  it("cancel from the page does the same at once", function()
    local doc = doc_with({ flags = { OJ_AIRPLANE = true } }); doc.device.airplane = { boot = true }
    local r = device.on_airplane(doc, { cancel = true }, { wall = 0 })
    assert_false(r.state.device.airplane); assert_eq(r.commands[3].args.wifi, true)
  end)

  it("the knob (held 5 s) overrides a bounded airplane mode: its timer and flag go", function()
    local doc = doc_with({ flags = { WIFI_OFF = true, BT_OFF = true, OJ_AIRPLANE = true } }); doc.device.airplane = { ends = 5, boot = true }
    doc.activity = { buttons = { airplane_mode_on = 0 } }
    local t = device.on_tick(doc, { now = 5 })
    assert_eq(kinds(t), { "emit radio.set" }); assert_nil(t.commands[1].event.bounded)
    local r = device.on_radio(doc, t.commands[1].event)
    assert_false(r.state.device.airplane); assert_nil(r.state.flags.OJ_AIRPLANE)
    assert_eq(timer_cmds(r), { "timer.cancel device.airplane" })
    -- and a plain radio change with nothing to end adds nothing
    doc.device.airplane = false; doc.flags = {}
    r = device.on_radio(doc, { wifi = false, bt = false })
    assert_nil(r.state.device); assert_eq(#r.commands, 4)
  end)

  it("boot with the OJ_AIRPLANE flag: the radios come back a few seconds later, whatever the ESP32 remembers", function()
    local r = device.on_boot(doc_with(), { audiocfg = {}, flags = { OJ_AIRPLANE = true, WIFI_OFF = true, BT_OFF = true }, now = 5 })
    assert_true(r.state.device.airplane.boot)
    local found
    for _, c in ipairs(r.commands) do if c.kind == "timer.once" and c.name == "device.airplane_restore" then found = c.seconds end end
    assert_eq(found, 3)
    local doc = doc_with({ flags = r.state.flags }); doc.device = r.state.device
    local t = device.on_timer(doc, { name = "device.airplane_restore", now = 8 })
    assert_eq(t.commands[3].args.wifi, true); assert_eq(flag_cmds(t)[3], "OJ_AIRPLANE=false"); assert_false(t.state.device.airplane)
    -- a normal boot schedules nothing of the kind
    r = device.on_boot(doc_with(), { audiocfg = {}, flags = {}, now = 5 })
    for _, c in ipairs(r.commands) do assert_true(c.name ~= "device.airplane_restore") end
  end)
end)

describe("services.device — power", function()
  it("battery: warning under 20 % every 5 min, shutdown under 10 %, nothing while charging", function()
    local doc = doc_with({ power = { charging = false } })
    local r = device.on_battery(doc, { mv = 3600, tenths = 150, mc = 30000, now = 100 })
    assert_eq(kinds(r), { "emit system.event Evt.Power.Low.Warning" })
    doc.power = r.state.power
    assert_eq(kinds(device.on_battery(doc, { tenths = 150, now = 200 })), {})
    assert_eq(kinds(device.on_battery(doc, { tenths = 150, now = 401 })), { "emit system.event Evt.Power.Low.Warning" })
    r = device.on_battery(doc, { tenths = 90, now = 500 })
    assert_eq(r.commands[1].event.after.type, "power.off_request")
    doc.power.charging = true
    assert_eq(kinds(device.on_battery(doc, { tenths = 50, now = 600 })), {})
  end)

  it("overheat: toy safe, volume 80, script", function()
    local doc = doc_with()
    local r = device.on_battery(doc, { mc = 85000, tenths = 900, now = 1 })
    assert_eq(kinds(r), { "log", "emit device.toy_safe_request", "shell power_overheat", "vol 80", "write /d/audiocfg.json" })
  end)

  it("plug and charge events set state and lights only after the first report", function()
    local doc = doc_with({ power = {} })
    local r = device.on_plugged(doc, { on = true })
    assert_true(r.state.power.connected); assert_eq(kinds(r), {})
    doc.power = r.state.power
    r = device.on_plugged(doc, { on = false })
    assert_eq(kinds(r), { "files.write_text", "emit system.event Evt.Power.Cable.Remove" })
    assert_nil(device.on_plugged(doc, { on = true }))
  end)

  it("inactivity: warns at 14 min, powers off at 15, unless playing / plugged / BT / STAY_ON", function()
    local doc = doc_with({ activity = { last = 0 }, power = { connected = false } })
    assert_nil(device.on_inactivity(doc, { now = 800 }))
    local r = device.on_inactivity(doc, { now = 841 })
    assert_eq(kinds(r), { "emit lights.event Evt.Power.Inactivity.Warning" }); doc.activity = r.state.activity
    r = device.on_inactivity(doc, { now = 901 })
    assert_eq(kinds(r)[2], "emit power.off_request")
    doc.playback = { state = "playing" }
    r = device.on_inactivity(doc, { now = 902 })
    assert_eq(r.state.activity.last, 902)
    doc.playback = nil; doc.flags = { STAY_ON = true }
    assert_nil(device.on_inactivity(doc, { now = 2000 }))
    doc.flags = {}; doc.power.connected = true
    assert_eq(device.on_inactivity(doc, { now = 2000 }).state.activity.last, 2000)
  end)

  it("power off: sound first, then save, lights, quit, poweroff, kernel shutdown", function()
    local doc = doc_with()
    local r = device.on_off_request(doc, { reason = "button" })
    assert_eq(r.commands[1].event.name, "Evt.Jooki.Poweroff"); assert_eq(r.commands[1].event.after, { type = "shutdown.request", reason = "button" })
    r = device.on_shutdown_request(doc, { reason = "button" })
    assert_eq(kinds(r), { "write /d/audiocfg.json", "led/output/set_raw ALL,0,0,0", "led/output/set_raw CIRCLE,200,0,0", "all/quit \"from-player\"", "shell sync", "shell poweroff", "shutdown" })
    r = device.on_shutdown_request(doc, { reason = "signal" })
    assert_eq(kinds(r)[6], "shutdown")
  end)
end)

describe("services.device — lights and toy safe", function()
  it("idle ring white, token playing ring off, Wi-Fi dots orange/white, dimmed at night", function()
    local doc = doc_with({ playback = { state = "idle" }, net = { connected = true, ip = "" } })
    assert_eq(kinds(device.on_lights_refresh(doc)), { "led/output/set_raw RING,200,200,200", "led/output/set_raw PREV,200,200,200", "led/output/set_raw NEXT,200,40,0" })
    doc.playback = { state = "playing" }; doc.nfc = { tagId = "04" }; doc.net = { connected = true, ip = "10.0.0.2" }; doc.limits = { dim = true }
    assert_eq(kinds(device.on_lights_refresh(doc)), { "led/output/set_raw RING,0,0,0", "led/output/set_raw PREV,10,10,10", "led/output/set_raw NEXT,10,10,10" })
    doc.playback = { state = "starting" }
    assert_eq(kinds(device.on_lights_refresh(doc))[1], "led/output/set_raw PREV,0,1,10")
  end)

  it("event lights: detect, write, error and warning pulses", function()
    local doc = doc_with()
    assert_eq(kinds(device.on_lights_event(doc, { name = "Evt.Character.Detect" }))[1], "led/output/set_raw PREV,0,10,200")
    assert_eq(kinds(device.on_lights_event(doc, { name = "Evt.Character.Detect.Empty" }))[1], "led/output/pulse_raw PREV,200,0,0,2,500,0.5")
    assert_eq(kinds(device.on_lights_event(doc, { name = "Evt.ToySafe.On" }))[2], "led/output/pulse_raw NEXT,200,200,0,1,500,0.5")
    assert_nil(device.on_lights_event(doc, { name = "Evt.Unknown" }))
  end)

  it("start-up Wi-Fi chase: refresh leaves the side dots to the chase (ring only) while waiting", function()
    local doc = doc_with({ playback = { state = "idle" }, net = { connected = false } })
    assert_eq(kinds(device.on_lights_refresh(doc)), { "led/output/set_raw RING,200,200,200" })
  end)

  it("start-up Wi-Fi chase: bright/dim orange ping-pongs left<->right", function()
    local doc = doc_with({ playback = { state = "idle" }, net = { connected = false } })
    assert_eq(kinds(device.on_wifi_anim(doc, { now = 0 })),
              { "led/output/set_raw PREV,200,40,0", "led/output/set_raw NEXT,50,10,0" })
    assert_eq(kinds(device.on_wifi_anim(doc, { now = 0.45 })),
              { "led/output/set_raw PREV,50,10,0", "led/output/set_raw NEXT,200,40,0" })
  end)

  it("start-up Wi-Fi chase: stops and settles the dots once associated", function()
    local doc = doc_with({ playback = { state = "idle" }, net = { connected = true, ip = "10.0.0.2" } })
    local k = kinds(device.on_wifi_anim(doc, { now = 1 }))
    assert_eq(k[#k], "timer.cancel")
    assert_eq(k[2], "led/output/set_raw PREV,200,200,200"); assert_eq(k[3], "led/output/set_raw NEXT,200,200,200")
  end)

  it("start-up Wi-Fi chase: none in airplane mode, nor while a token plays", function()
    local air = doc_with({ playback = { state = "idle" }, net = { connected = false } }); air.device.airplane = { boot = true }
    local ka = kinds(device.on_wifi_anim(air, { now = 0 })); assert_eq(ka[#ka], "timer.cancel")
    local play = doc_with({ playback = { state = "playing" }, net = { connected = false } })
    local kp = kinds(device.on_wifi_anim(play, { now = 0 })); assert_eq(kp[#kp], "timer.cancel")
  end)

  it("boot starts the Wi-Fi chase timer", function()
    local r = device.on_boot(doc_with(), { audiocfg = {}, flags = {}, now = 5 })
    local found = false
    for _, c in ipairs(r.commands) do
      if c.kind == "timer.every" and c.name == "device.wifi_anim" then found = true end
    end
    assert_true(found)
  end)

  it("toy safe sets the flag, the script and the ESP32", function()
    local doc = doc_with()
    local r = device.on_toy_safe(doc, { enable = false })
    assert_false(r.state.device.toy_safe); assert_true(r.state.flags.TOY_SAFE_OFF)
    assert_eq(kinds(r), { "files.flag", "shell toysafe_update", "esp32/output/audio/set_toysafe 0", "emit lights.event Evt.ToySafe.Off" })
  end)

  it("boot applies the saved volume and schedules its timers", function()
    local r = device.on_boot(doc_with(), { audiocfg = { volume = 70 }, flags = { TOY_SAFE_OFF = true }, now = 5 })
    assert_eq(r.state.audiocfg.volume, 70); assert_false(r.state.device.toy_safe)
    assert_eq(kinds(r)[1], "vol 70"); assert_eq(kinds(r)[#kinds(r)], "emit system.event Evt.Jooki.Ready")
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
    assert_eq(onces, { "device.esp32_init.1@1", "device.esp32_init.2@3" })
    local doc = doc_with()
    local t = device.on_timer(doc, { name = "device.esp32_init.1", now = 6 })
    assert_eq(kinds(t), { "esp32/output/device/send_all_notifications ", "esp32/output/nfc/mode/set 1", "esp32/output/knobs/state " })
    -- the knobs answer (nothing else changes) marks esp32_ctrl as listening: no more resends
    doc.audiocfg.volume = 40
    local kr = device.on_knobs(doc, { volume = 40 })
    assert_true(kr.state.device.esp32_up); assert_true(kr.state.device.toy_safe)
    doc.device = kr.state.device
    assert_nil(device.on_timer(doc, { name = "device.esp32_init.2", now = 8 }))
    assert_nil(device.on_knobs(doc, { volume = 40 }))
  end)

  it("set_name: normalizes, checks, changes device.hostname and net.name; empty = factory name", function()
    local doc = doc_with({ net = { name = "jooki2-a1b2c3.local", ip = "10.0.0.2" } }); doc.device.id = "jooki2-A1B2C3"
    local r = device.on_set_name(doc, "  Jooki.local ")
    assert_eq(r.state.device.hostname, "jooki.local"); assert_eq(r.state.net.name, "jooki.local"); assert_eq(r.state.net.ip, "10.0.0.2")
    assert_eq(r.commands[1].action, "set_name"); assert_eq(r.commands[1].args.name, "jooki")
    r = device.on_set_name(doc, "")
    assert_eq(r.state.device.hostname, "jooki2-a1b2c3.local"); assert_eq(r.commands[1].args.name, "")
    for _, bad in ipairs({ "jo oki", "-a", "a-", "localhost", "x;reboot", string.rep("a", 33) }) do
      local ok, err = device.on_set_name(doc, bad)
      assert_nil(ok); assert_eq(err.code, "invalid_argument")
    end
  end)

  it("boot reads the charger: plugged in at start never powers off for inactivity, and no cable sound", function()
    local r = device.on_boot(doc_with(), { audiocfg = {}, flags = {}, now = 5, plugged = "1" })
    assert_true(r.state.power.connected)
    local doc = doc_with({ activity = { last = 0 }, power = r.state.power })
    assert_eq(device.on_inactivity(doc, { now = 5000 }).state.activity.last, 5000)
    assert_nil(device.on_plugged(doc, { on = true }))
    assert_false(device.on_boot(doc_with(), { audiocfg = {}, flags = {}, now = 5, plugged = "0" }).state.power.connected)
    assert_nil(device.on_boot(doc_with(), { audiocfg = {}, flags = {}, now = 5 }).state.power.connected)
  end)
end)
