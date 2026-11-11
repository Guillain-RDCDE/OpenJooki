local device = require("services.device")

-- o.jack = false: wired headphones detection off (config headphone_jack; on by default)
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
    local doc = doc_with({ limits = { maxvol = 30, fade = 1 } }); doc.device.toy_safe = false
    doc.volume_int = { knob = 40 }
    local r = device.on_gpio_volume(doc, { percent = 97 })
    assert_eq(r.state.audiocfg.volume, 97)
    same(kinds(r), { "vol 30", "write /d/audiocfg.json" })
    doc.limits = { maxvol = 100, fade = 0.5 }
    assert_eq(device.effective_volume(doc, 97), 49)
    assert_eq(kinds(device.on_apply_volume(doc)), { "vol 20" })   -- 40 * 0.5
  end)

  it("knob reports change the volume only when it differs", function()
    local doc = doc_with({ jack = false }); doc.device.esp32_up = true   -- the first answer only marks esp32_ctrl up (see boot spec)
    local initial = device.on_knobs(doc, { volume = 40, headphones = false })
    assert_nil(initial.state.audiocfg); doc.volume_int = initial.state.volume_int; doc.device = initial.state.device
    assert_nil(device.on_knobs(doc, { volume = 40, headphones = false }))
    local r = device.on_knobs(doc, { volume = 55, headphones = true })
    assert_eq(r.state.audiocfg.volume, 55); assert_false(r.state.audiocfg.headphones_en == true)
    assert_true(has(r, "host.volume", "percent", 55))
  end)

  it("with volume API 2, first and unchanged reports preserve web volume, real movement takes over, restart preserves it", function()
    local doc = doc_with({ jack = false, audiocfg = { volume = 75 } })
    doc.device.esp32_up = true
    doc.device.volume_api = 2
    local function step(ev)
      ev.volume_api = 2
      local r = device.on_knobs(doc, ev)
      for k, v in pairs((r or {}).state or {}) do doc[k] = v end
      return r
    end
    local function saved(r) return ((r or {}).state or {}).audiocfg end
    assert_nil(saved(step({ volume = 9 })))
    assert_eq(doc.audiocfg.volume, 75)
    for _ = 1, 10 do assert_nil(saved(step({ volume = 9 }))) end
    local web = device.set_volume(doc, 90); doc.audiocfg = web.state.audiocfg
    assert_nil(saved(step({ volume = 9 }))); assert_eq(doc.audiocfg.volume, 90)
    step({ volume = 15 }); assert_eq(doc.audiocfg.volume, 15)
    assert_nil(device.on_gpio_volume(doc, { percent = 15 }))
    local boot = device.on_boot(doc, { audiocfg = doc.audiocfg })
    for k, v in pairs(boot.state) do doc[k] = v end
    doc.device.volume_api = 2
    step({ volume = 3 }); assert_eq(doc.audiocfg.volume, 15)
  end)

  it("without volume API 2, the page lowers the speaker below the dial, never above, and the dial takes over", function()
    for _, api in ipairs({ false, 0, 1 }) do
      local doc = doc_with({ jack = false, audiocfg = { volume = 75 } })
      doc.device.esp32_up = true
      local function step(ev)
        ev.volume_api = api or nil
        local r = device.on_knobs(doc, ev)
        for k, v in pairs((r or {}).state or {}) do doc[k] = v end
        return r
      end
      step({ volume = 60 }); assert_eq(doc.audiocfg.volume, 60)        -- at start, not above the dial
      local up = device.set_volume(doc, 90); assert_eq(up.state.audiocfg.volume, 60)
      assert_eq(up.commands[1].mixer, 100)
      local web = device.set_volume(doc, 30); doc.audiocfg = web.state.audiocfg
      assert_eq(web.commands[1].mixer, 70)                             -- 30 points below the dial
      assert_nil(((step({ volume = 60 }) or {}).state or {}).audiocfg) -- an unchanged dial keeps it
      assert_eq(doc.audiocfg.volume, 30)
      local moved = step({ volume = 15 })
      assert_eq(doc.audiocfg.volume, 15); assert_eq(moved.commands[1].mixer, 100)
      local below = step({ volume = 15 })
      assert_nil(((below or {}).state or {}).audiocfg)
      assert_eq(device.volume_command(doc, 0).mixer, 0)                -- silence is silence
      doc.limits = { maxvol = 5 }
      assert_eq(device.on_apply_volume(doc).commands[1].mixer, 90)     -- night limit on the speaker
      doc.limits = {}
      doc.audiocfg.headphones_en = true
      local hp = device.set_volume(doc, 90)
      assert_eq(hp.state.audiocfg.volume, 90); assert_eq(hp.commands[1].mixer, 90) -- headphones: the volume itself
    end
  end)

  it("discovers volume support, reapplies after reconnect, and gates old firmware", function()
    local doc = doc_with({ jack = false })
    local r = device.on_knobs(doc, { volume = 8, volume_api = 2 })
    assert_eq(r.state.device.volume_api, 2)
    assert_eq(find(r, "emit").event.type, "volume.apply")
    doc.device = r.state.device; doc.volume_int = r.state.volume_int
    local c = device.on_apply_volume(doc).commands[1]
    assert_true(c.esp32); assert_eq(c.percent, 40); assert_eq(c.maximum, 56)
    local reconnect = device.on_bus_up(doc)
    assert_nil(reconnect.state.device.volume_api)
    assert_nil(reconnect.state.volume_int.knob)
    doc.device = reconnect.state.device
    assert_false(device.on_apply_volume(doc).commands[1].esp32)
    doc.device.volume_api = 0
    assert_false(device.set_volume(doc, 80).commands[1].esp32)
  end)

  it("reasserts the saved value after a silent chip restart and stops using a lost capability", function()
    local doc = doc_with({ jack = false, audiocfg = { volume = 90 } })
    doc.device.esp32_up = true; doc.device.volume_api = 2; doc.volume_int = { knob = 8 }
    local r = device.on_knobs(doc, { volume = 8, volume_api = 2 })
    assert_nil(r.state.audiocfg); assert_nil(find(r, "files.write"))
    assert_eq(find(r, "emit").event.type, "volume.apply")
    r = device.on_knobs(doc, { volume = 20, volume_api = 0 })
    assert_eq(r.state.device.volume_api, 0)
    assert_false(find(r, "host.volume").esp32)
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

  it("random start is independent of shuffle, saved and restored at boot", function()
    local doc = doc_with()
    assert_false(device.audiocfg_of(doc).random_start)
    local schema = require("api.schema")
    assert_true(schema.validate({ random_start = true }, device.schemas.config))
    assert_false(schema.validate({ random_start = "true" }, device.schemas.config))
    local r = device.update_config(doc, { random_start = true })
    assert_true(find(r, "files.write").doc.random_start)
    assert_false(r.state.audiocfg.shuffle_mode)
    local boot = device.on_boot(doc, { audiocfg = find(r, "files.write").doc, flags = {}, now = 5 })
    assert_true(boot.state.audiocfg.random_start)
    doc.audiocfg = boot.state.audiocfg
    r = device.update_config(doc, { shuffle_mode = true })
    assert_true(r.state.audiocfg.random_start)
    doc.audiocfg = r.state.audiocfg
    r = device.update_config(doc, { random_start = false })
    assert_false(r.state.audiocfg.random_start); assert_true(r.state.audiocfg.shuffle_mode)
    local bad, e = device.update_config(doc, { random_start = "false" })
    assert_nil(bad); assert_eq(e.field, "random_start")
    assert_true(doc.audiocfg.random_start)
  end)

  it("persists the token removal setting and restores it at boot", function()
    local doc = doc_with()
    assert_false(device.audiocfg_of(doc).continue_on_token_removal)
    local schema = require("api.schema")
    assert_true(schema.validate({ continue_on_token_removal = true }, device.schemas.config))
    assert_false(schema.validate({ continue_on_token_removal = "true" }, device.schemas.config))
    local r = device.update_config(doc, { continue_on_token_removal = true })
    assert_true(find(r, "files.write").doc.continue_on_token_removal)
    local boot = device.on_boot(doc, { audiocfg = find(r, "files.write").doc, flags = {}, now = 5 })
    assert_true(boot.state.audiocfg.continue_on_token_removal)
    doc.audiocfg = boot.state.audiocfg
    assert_true(device.update_config(doc, { continue_on_token_removal = "false" }).state.audiocfg.continue_on_token_removal)
    assert_false(device.update_config(doc, { continue_on_token_removal = false }).state.audiocfg.continue_on_token_removal)
  end)

  it("louder headphones: saved, said at once and at every boot, never with kids mode on", function()
    local schema = require("api.schema")
    assert_true(schema.validate({ hp_boost = true }, device.schemas.config))
    assert_false(schema.validate({ hp_boost = "true" }, device.schemas.config))
    local function gain(r) local c = find(r, "shell", "action", "hp_gain") return c and c.args.db end
    -- off by default; kids mode on (doc_with): the setting is saved but the gain stays at the factory 0 dB
    local doc = doc_with()
    assert_false(device.audiocfg_of(doc).hp_boost)
    local r = device.update_config(doc, { hp_boost = true })
    assert_true(find(r, "files.write").doc.hp_boost); assert_eq(gain(r), 0)
    -- kids mode off: +6 dB at once, back to 0 when switched off
    local free = doc_with(); free.device.toy_safe = false
    r = device.update_config(free, { hp_boost = true })
    assert_eq(gain(r), 6)
    free.audiocfg = r.state.audiocfg
    assert_eq(gain(device.update_config(free, { hp_boost = false })), 0)
    -- not a boolean, or no change: nothing said, nothing changed
    assert_nil(gain(device.update_config(free, { hp_boost = "false" })))
    assert_true(device.update_config(free, { hp_boost = "false" }).state.audiocfg.hp_boost)
    assert_nil(gain(device.update_config(free, { hp_boost = true })))
    assert_nil(gain(device.update_config(free, { shuffle_mode = true })))
    -- every boot says it (the factory start script restores whatever alsactl last stored)
    assert_eq(gain(device.on_boot(doc_with(), { audiocfg = { hp_boost = true }, flags = { TOY_SAFE_OFF = true }, now = 5 })), 6)
    assert_eq(gain(device.on_boot(doc_with(), { audiocfg = { hp_boost = true }, flags = {}, now = 5 })), 0)
    assert_eq(gain(device.on_boot(doc_with(), { audiocfg = {}, flags = { TOY_SAFE_OFF = true }, now = 5 })), 0)
    -- the shell action takes only the two values
    local shell = require("adapters.shell")
    assert_eq(shell._argv("hp_gain", { db = 6 }), { "/usr/bin/amixer", "-q", "-c", "0", "cset", "name=MERCURY Playback Volume", "37" })
    assert_eq(shell._argv("hp_gain", { db = 0 })[7], "31")
    for _, bad in ipairs({ 32, -31, "6", 6.5 }) do assert_nil(shell._argv("hp_gain", { db = bad })) end
  end)

  it("the heart's short press is saved with the rest; an unknown choice keeps the current one", function()
    local doc = doc_with()
    local r = device.update_config(doc, { heart_press = "next" })
    assert_eq(r.state.audiocfg.heart_press, "next"); assert_eq(find(r, "files.write").doc.heart_press, "next")
    doc.audiocfg = r.state.audiocfg
    r = device.update_config(doc, { heart_press = "dance" })
    assert_eq(r.state.audiocfg.heart_press, "next")
    r = device.update_config(doc, { shuffle_mode = true })
    assert_eq(r.state.audiocfg.heart_press, "next")
  end)

  it("the track knob's choice is saved the same way; an unknown one keeps the current one", function()
    local doc = doc_with()
    local r = device.update_config(doc, { knob_mode = "wind" })
    assert_eq(r.state.audiocfg.knob_mode, "wind"); assert_eq(find(r, "files.write").doc.knob_mode, "wind")
    doc.audiocfg = r.state.audiocfg
    r = device.update_config(doc, { knob_mode = "spin" })
    assert_eq(r.state.audiocfg.knob_mode, "wind")
  end)
end)

describe("services.device — audio output / amplifier", function()
  local function amp_and_out(r)
    local amp, out
    for _, c in ipairs((r or {}).commands or {}) do
      if c.kind == "files.write_text" and c.path == "/sys/kernel/htdrv/amp_en" then amp = c.text end
      if c.kind == "bus.publish" and c.topic == "/j/audio/out/set_output_device" then out = c.payload end
    end
    return amp, out
  end

  it("boot turns the amplifier ON for the speaker (sound must work on battery, not only when plugged)", function()
    local amp, out = amp_and_out(device.on_boot(doc_with(), { audiocfg = { volume = 50 }, flags = {}, now = 5 }))
    assert_eq(amp, "1"); assert_eq(out, "speaker")
  end)

  -- the knobs answered one after another, each result applied to the document as the kernel does
  local function step(doc, ev)
    local r = device.on_knobs(doc, ev)
    for k, v in pairs((r and r.state) or {}) do doc[k] = v end
    return r
  end
  local function mux_written(r) return find(r, "files.write_text", "path", "/sys/kernel/htdrv/usb_mux") end
  local function hp_doc(o)
    local doc = doc_with(o); doc.device.esp32_up = true
    return doc
  end

  it("wired headphones on battery: usb_mux first, the next reading skipped, then two readings in a row switch", function()
    local doc = hp_doc({ power = { connected = false } })
    local r = step(doc, { volume = 40, headphones = true })        -- usb_mux off: the line is not pulled up, nothing to trust
    assert_eq(mux_written(r).text, "1"); assert_true(has(r, "timer.once", "name", "device.hp_check"))
    assert_nil(select(2, amp_and_out(r)))
    r = step(doc, { volume = 40, headphones = true })              -- read before the line settled: skipped
    assert_nil(mux_written(r)); assert_nil(select(2, amp_and_out(r)))
    r = step(doc, { volume = 40, headphones = true })              -- a first good reading only waits for the next one
    assert_true(has(r, "timer.once", "name", "device.hp_check")); assert_nil(select(2, amp_and_out(r)))
    r = step(doc, { volume = 40, headphones = true })              -- the second agrees: headphones
    local amp, out = amp_and_out(r)
    assert_eq(amp, "0"); assert_eq(out, "headphones"); assert_true(doc.audiocfg.headphones_en)
    assert_eq(find(r, "bus.publish", "topic", "/j/spotify/output/set_output_device").payload, "headphones")   -- Spotify follows too
    assert_eq(r.commands[1].kind, "host.volume"); assert_eq(r.commands[1].percent, 0)   -- silent while it switches (1.x)
    assert_eq(r.commands[#r.commands - 1].percent, 40)                                   -- then its volume, the knob's
    step(doc, { volume = 40, headphones = false })
    amp, out = amp_and_out(step(doc, { volume = 40, headphones = false }))
    assert_eq(amp, "1"); assert_eq(out, "speaker"); assert_false(doc.audiocfg.headphones_en)
  end)

  it("one stray 'plugged' reading never mutes the speaker", function()
    local doc = hp_doc({ power = { connected = false } })
    step(doc, { headphones = false }); step(doc, { headphones = false })   -- usb_mux up and settled
    local r = step(doc, { headphones = true })
    assert_nil(select(1, amp_and_out(r)))
    r = step(doc, { headphones = false })
    assert_nil(select(1, amp_and_out(r) or nil)); assert_nil(doc.hp_int.pending)
    assert_false(doc.audiocfg.headphones_en == true)
  end)

  it("on the charger a 'plugged' reading is the charger itself: the speaker stays on", function()
    local doc = hp_doc({ power = { connected = true } })
    for _ = 1, 3 do
      local r = step(doc, { headphones = true })
      assert_nil(mux_written(r)); assert_nil(select(1, amp_and_out(r)))
    end
    assert_false(doc.audiocfg.headphones_en == true); assert_nil((doc.hp_int or {}).pending)
  end)

  it("on the charger, headphones already on still go back to the speaker when they come out", function()
    local doc = hp_doc({ power = { connected = true } })
    doc.audiocfg.headphones_en = true
    step(doc, { headphones = false })
    assert_eq(select(1, amp_and_out(step(doc, { headphones = false }))), "1")
    assert_false(doc.audiocfg.headphones_en)
  end)

  it("a charger plugged in on battery: the first 'plugged' reading waits, the cable event follows, no switch", function()
    local power = require("services.device.power")
    local doc = hp_doc({ power = { connected = false } })
    step(doc, { headphones = false }); step(doc, { headphones = false })   -- usb_mux up and settled
    local r = step(doc, { headphones = true })                             -- the charger's plug, read before its event
    assert_nil(select(1, amp_and_out(r)))
    r = power.on_plugged(doc, { on = true })
    for k, v in pairs(r.state) do doc[k] = v end
    for _ = 1, 3 do assert_nil(select(1, amp_and_out(step(doc, { headphones = true })))) end
    assert_false(doc.audiocfg.headphones_en == true)
  end)

  -- headphones on battery, settled: usb_mux up, two readings switch, a third confirms
  local function plug(doc)
    local r = require("services.device.power").on_plugged(doc, { on = true })
    for k, v in pairs(r.state) do doc[k] = v end
    return r
  end
  local function headphones_on(doc, confirmed)
    step(doc, { headphones = false }); step(doc, { headphones = false })
    step(doc, { headphones = true }); step(doc, { headphones = true })
    assert_true(doc.audiocfg.headphones_en)
    if confirmed then step(doc, { headphones = true }) end
  end

  it("a charger whose readings switched to headphones before its cable event goes back to the speaker", function()
    local doc = hp_doc({ power = { connected = false } })
    headphones_on(doc, false)                        -- the charger's two readings won the race
    local r = plug(doc)
    assert_eq(mux_written(r).text, "0"); assert_true(has(r, "timer.once", "name", "device.hp_check"))
    assert_eq(select(1, amp_and_out(step(doc, { headphones = true }))), "1")
    for _ = 1, 3 do assert_nil(select(1, amp_and_out(step(doc, { headphones = true })))) end
    assert_false(doc.audiocfg.headphones_en)
  end)

  it("headphones swapped for the charger before the 'out' readings agreed go back to the speaker", function()
    local doc = hp_doc({ power = { connected = false } })
    headphones_on(doc, true)
    step(doc, { headphones = false })                -- the adapter out: one reading, the next not yet in
    assert_eq(mux_written(plug(doc)).text, "0")
    assert_eq(select(1, amp_and_out(step(doc, { headphones = true }))), "1")
    assert_false(doc.audiocfg.headphones_en)
  end)

  it("headphones that have been playing keep the sound when a charger is added (a splitter)", function()
    local doc = hp_doc({ power = { connected = false } })
    headphones_on(doc, true)
    assert_eq(mux_written(plug(doc)).text, "1")
    for _ = 1, 3 do assert_nil(select(1, amp_and_out(step(doc, { headphones = true })))) end
    assert_true(doc.audiocfg.headphones_en)
  end)

  it("a cable change sets usb_mux and the reading after it is skipped", function()
    local power = require("services.device.power")
    local doc = hp_doc({ power = { connected = true } })
    local r = power.on_plugged(doc, { on = false })
    assert_eq(find(r, "files.write_text", "path", "/sys/kernel/htdrv/usb_mux").text, "1")
    assert_eq(r.state.hp_int, { mux = "1", fresh = true })
    doc.power, doc.hp_int = r.state.power, r.state.hp_int
    r = step(doc, { headphones = true })
    assert_nil(mux_written(r)); assert_nil(doc.hp_int.fresh); assert_nil(doc.hp_int.pending)
  end)

  it("the ESP32's plug event asks for a reading now; it is not a button", function()
    local doc = hp_doc()
    assert_true(has(device.on_hp_event(doc, { button = "hp_plugged", down = true }), "timer.once", "name", "device.hp_check"))
    assert_nil(device.on_hp_event(doc, { button = "next", down = true }))
    assert_nil(require("services.device.buttons").on_button(doc, { button = "hp_plugged", down = true, now = 3 }))
    assert_nil(device.on_hp_event(hp_doc({ jack = false }), { button = "hp_plugged", down = true }))
  end)

  it("headphone_jack = false: a headphones report changes nothing, the speaker stays on", function()
    local doc = hp_doc({ jack = false, power = { connected = false } })
    assert_nil(device.on_knobs(doc, { headphones = true }))
  end)

  it("boot always starts on the speaker, a saved 'headphones on' included (1.x)", function()
    local r = device.on_boot(doc_with(), { audiocfg = { volume = 50, headphones_en = true }, flags = {}, now = 5 })
    local amp, out = amp_and_out(r)
    assert_eq(amp, "1"); assert_eq(out, "speaker"); assert_false(r.state.audiocfg.headphones_en)
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
    doc.device = kr.state.device; doc.volume_int = kr.state.volume_int
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
