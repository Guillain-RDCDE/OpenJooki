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
    local doc = doc_with()
    assert_nil(device.on_knobs(doc, { volume = 40, headphones = false }))
    local r = device.on_knobs(doc, { volume = 55, headphones = true })
    assert_eq(r.state.audiocfg.volume, 55); assert_true(r.state.audiocfg.headphones_en)
    assert_eq(kinds(r)[1], "vol 55"); assert_eq(kinds(r)[3], "audio/out/set_output_device headphones")
  end)

  it("volume buttons step by 10 within 0-100", function()
    local doc = doc_with({ audiocfg = { volume = 95 } })
    doc.activity = { buttons = { vol_inc = 1 } }
    local r = device.on_button(doc, { button = "vol_inc", down = false, now = 1.2 })
    assert_eq(r.state.audiocfg.volume, 100)
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
  end)
end)
