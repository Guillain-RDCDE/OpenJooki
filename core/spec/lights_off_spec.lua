local device = require("services.device")
local lights = require("services.device.lights")
local bedtime = require("services.bedtime")
local power = require("services.device.power")
local schema = require("api.schema")
local security = require("services.security")
local v1 = require("api.v1")
local json = require("vendor.json")

local function doc()
  return { audiocfg = { volume = 80, lights_off = false },
           device = { toy_safe = true }, config = { data_dir = "/d", wifi_anim_s = 0 },
           net = { connected = true, ip = "10.0.0.2" }, limits = { maxvol = 100, fade = 1 } }
end
local function has(r, kind, key, value)
  for _, c in ipairs((r or {}).commands or {}) do if c.kind == kind and (not key or c[key] == value) then return c end end
end
local function apply(d, r) for k, v in pairs((r or {}).state or {}) do d[k] = v end end

describe("device configuration contract", function()
  it("both interfaces reject invalid light switches without writing anything", function()
    local d = doc()
    for _, field in ipairs({ "lights_off" }) do
      local bad = { 0, 1, "false", {} }
      for _, value in ipairs(bad) do
        local p = { [field] = value }
        assert_false(schema.validate(p, device.schemas.config))
        local r, e = device.update_config(d, p)
        assert_nil(r); assert_eq(e.field, field)
        r = v1.on_cmd(d, { name = "SET_CFG", raw = json.encode(p) })
        assert_nil(r.state); assert_true(has(r, "bus.publish", "topic", v1.TOPIC_ERROR) ~= nil)
      end
    end
    assert_true(schema.validate({ lights_off = true }, device.schemas.config))
  end)

  it("SET_CFG and device.set_config protect the light switch with the parent code", function()
    security._set_parent_code("1234")
    local p = { lights_off = true }
    local d = doc()
    local denied = v1.on_cmd(d, { name = "SET_CFG", raw = json.encode(p) })
    assert_nil(denied.state)
    assert_true(security.gate(security.PROTECTED_V2, "device.set_config", nil) ~= nil)
    assert_nil(security.gate(security.PROTECTED_V2, "device.set_config", "1234"))
    p.code = "1234"
    local allowed = v1.on_cmd(d, { name = "SET_CFG", raw = json.encode(p) })
    assert_true(allowed.state.audiocfg.lights_off)
    assert_nil(security.gate(v1.PROTECTED, "SET_VOL", nil))
    security._set_parent_code(nil)
  end)
end)

describe("scheduled darkness and the permanent override", function()
  local function event(h, m)
    -- 2026-01-15, UTC: the schedule crosses midnight and uses UTC for these tests.
    return { wall = 1768435200 + h * 3600 + (m or 0) * 60,
      bedtime = { enabled = true, start = 1200, stop = 420, maxvol = 100,
                  dim = false, lights_off = true, tzbase = 0, tzdst = "none" } }
  end
  local function boot(h, m)
    local d = doc(); apply(d, bedtime.on_boot(d, event(h, m)))
    apply(d, lights.on_boot(d, event(h, m)))
    return d
  end
  local function driver(r) return has(r, "bus.publish", "topic", "/j/ht/output/raw_write") end

  it("defaults to normal lighting and strictly validates the protected night switch", function()
    assert_false(bedtime.on_boot(doc(), {}).state.bedtime.cfg.lights_off)
    for _, value in ipairs({ "false", 0, 1, {} }) do
      assert_false(schema.validate({ lights_off = value }, bedtime.schemas.set))
      local r, e = bedtime.on_set(doc(), { lights_off = value }, event(22).wall)
      assert_nil(r); assert_eq(e.field, "lights_off")
      r = v1.on_cmd(doc(), { name = "OJ_BEDTIME_SET", raw = json.encode({ lights_off = value }) })
      assert_nil(r.state); assert_true(has(r, "bus.publish", "topic", v1.TOPIC_ERROR) ~= nil)
    end
    security._set_parent_code("1234")
    assert_true(security.gate(security.PROTECTED_V2, "bedtime.set", nil) ~= nil)
    assert_nil(security.gate(security.PROTECTED_V2, "bedtime.set", "1234"))
    local r = v1.on_cmd(doc(), { name = "OJ_BEDTIME_SET", raw = '{"lights_off":true}' })
    assert_nil(r.state)
    r = v1.on_cmd(doc(), { name = "OJ_BEDTIME_SET", raw = '{"lights_off":true,"code":"1234"}', wall = event(22).wall })
    assert_true(r.state.bedtime.cfg.lights_off)
    security._set_parent_code(nil)
  end)

  it("turns off at the start and restores at the end even with no dimming or volume limit", function()
    local d = boot(19, 59)
    assert_false(lights.off(d)); assert_eq(d.lights_int.desired, 8)
    apply(d, bedtime.on_clock(d, event(20, 0)))
    assert_true(lights.off(d)); assert_eq(driver(lights.on_limits(d)).payload, "34 0")
    apply(d, lights.on_limits(d))
    assert_nil(driver(lights.on_limits(d))) -- unrelated fades must not restart the global driver
    assert_nil(bedtime.on_clock(d, event(6, 59)))
    apply(d, bedtime.on_clock(d, event(7, 0)))
    assert_false(lights.off(d))
    local r = lights.on_limits(d); apply(d, r)
    assert_eq(driver(r).payload, "34 8")
    assert_true(has(r, "bus.publish", "payload", "RING,200,200,200") ~= nil)
    assert_false(d.audiocfg.lights_off)
  end)

  it("uses the saved schedule in the first boot command without a transient driver enable", function()
    for _, h in ipairs({ 0, 6, 20, 23 }) do
      local d = doc(); d.limits.lights_off = false
      local r = lights.on_boot(d, event(h))
      assert_eq(driver(r).payload, "34 0")
      for _, c in ipairs(r.commands) do
        assert_false(c.topic == "/j/ht/output/raw_write" and c.payload == "34 8")
        if c.topic == "/j/led/output/set_raw" then assert_eq(c.payload, "ALL,0,0,0") end
      end
    end
    assert_eq(driver(lights.on_boot(doc(), event(12))).payload, "34 8")
  end)

  it("persists each preference independently and disabling night mode restores lighting", function()
    local d = boot(22)
    local r = bedtime.on_set(d, { enabled = false, dim = true }, event(22).wall)
    assert_true(has(r, "files.write").doc.lights_off); apply(d, r)
    assert_false(lights.off(d)); assert_eq(driver(lights.on_limits(d)).payload, "34 8")
    assert_true(d.bedtime.cfg.dim); assert_true(d.bedtime.cfg.lights_off)
    assert_false(d.audiocfg.lights_off)
    apply(d, bedtime.on_set(d, { enabled = true }, event(22).wall))
    assert_true(lights.off(d))
    d.audiocfg.lights_off = true
    apply(d, bedtime.on_set(d, { enabled = false }, event(22).wall))
    assert_true(lights.off(d)); assert_nil(driver(lights.on_limits(d)))
    assert_true(d.audiocfg.lights_off)
  end)

  it("keeps the permanent override across the morning and only enables when both are off", function()
    local d = boot(22); d.audiocfg.lights_off = true
    apply(d, bedtime.on_clock(d, event(8)))
    assert_true(lights.off(d)); assert_nil(driver(lights.on_limits(d)))
    d.audiocfg.lights_off = false
    assert_eq(driver(lights.on_apply(d)).payload, "34 8")
    apply(d, bedtime.on_clock(d, event(22))); apply(d, lights.on_limits(d))
    assert_eq(driver(lights.on_apply(d)).payload, "34 0") -- permanent off cannot bypass the night window
  end)

  it("reapplies scheduled darkness on reconnect and charging, suppressing events and shutdown light", function()
    local d = boot(22)
    assert_eq(driver(lights.on_apply(d)).payload, "34 0")
    assert_eq(driver(lights.on_power(d, { type = "power.plugged", on = true })).payload, "34 0")
    assert_nil(lights.on_lights_event(d, { name = "Evt.Character.Write" }))
    assert_nil(lights.on_lights_event(d, { name = "Evt.Power.Low.Warning" }))
    assert_eq(lights.on_party(d), {})
    assert_nil(has(power.on_shutdown_request(d, {}), "bus.publish", "payload", "CIRCLE,200,0,0"))
    apply(d, bedtime.on_clock(d, event(8))); apply(d, lights.on_limits(d))
    assert_nil(lights.on_register(d, { address = 34, value = 0 })) -- late night acknowledgement
    apply(d, lights.on_register(d, { address = 34, value = 8 }))
    assert_true(d.lights_int.verified)
  end)

  it("does not apply scheduled darkness without a valid clock, enabled window or distinct endpoints", function()
    local ev = event(22); ev.wall = 0
    assert_false(bedtime.boot_limits(ev).lights_off)
    ev = event(22); ev.bedtime.enabled = false
    assert_false(bedtime.boot_limits(ev).lights_off)
    ev = event(22); ev.bedtime.stop = ev.bedtime.start
    assert_false(bedtime.boot_limits(ev).lights_off)
    ev = event(22); ev.bedtime.lights_off = "true"
    assert_false(bedtime.boot_limits(ev).lights_off)
    ev.audiocfg = { lights_off = true }
    assert_eq(driver(lights.on_boot(doc(), ev)).payload, "34 0")
  end)
end)

describe("all device lights off", function()
  it("persists the switch and restores it at boot, including the heart driver", function()
    local d = doc()
    assert_false(device.audiocfg_of({}).lights_off)
    local r = device.update_config(d, { lights_off = true }); apply(d, r)
    assert_true(has(r, "files.write").doc.lights_off)
    local boot = lights.on_boot(doc(), { audiocfg = d.audiocfg })
    assert_eq(has(boot, "bus.publish", "topic", "/j/ht/output/raw_write").payload, "34 0")
    assert_false(has(boot, "timer.every") ~= nil)
    assert_eq(device.on_boot(d, { audiocfg = d.audiocfg }).state.audiocfg.lights_off, true)
  end)

  it("cancels animations and suppresses playback, NFC, error, button and shutdown colours", function()
    local d = doc(); d.audiocfg.lights_off = true; d.device.party = true
    local r = lights.on_apply(d)
    assert_true(has(r, "timer.cancel", "name", "device.party") ~= nil)
    assert_true(has(r, "timer.cancel", "name", "device.party_end") ~= nil)
    assert_true(has(r, "timer.cancel", "name", "device.wifi_anim") ~= nil)
    assert_nil(r.state.device) -- cannot overwrite the facade's reconnect state
    assert_nil(lights.on_party_frame(d, { now = 1 })); assert_nil(lights.on_wifi_anim(d, { now = 1 }))
    assert_eq(lights.on_party(d), {})
    for _, ev in ipairs({ "Evt.Character.Detect", "Evt.Character.Write", "Evt.Character.Detect.Empty", "Evt.Mobile.connect", "Evt.Power.Low.Warning", "Evt.ToySafe.On" }) do
      assert_nil(lights.on_lights_event(d, { name = ev }))
    end
    for _, s in ipairs({ "playing", "paused", "starting", "idle" }) do
      d.playback = { state = s }; assert_eq(lights.on_lights_refresh(d).commands, {})
    end
    assert_nil(has(power.on_shutdown_request(d, {}), "bus.publish", "payload", "CIRCLE,200,0,0"))
    d.power = { connected = false, charging = false }
    assert_true(has(power.on_battery(d, { mv = 3400, tenths = 10, mc = 40000, now = 1 }), "emit") ~= nil)
    assert_true(has(power.on_battery(d, { mv = 4000, tenths = 800, mc = 90000, now = 1 }), "shell", "action", "power_overheat") ~= nil)
  end)

  it("checks read-back, retries at most three times and can recover on reconnect", function()
    local d = doc(); d.audiocfg.lights_off = true
    apply(d, lights.on_apply(d))
    assert_nil(lights.on_register(d, { address = 33, value = 0 }))
    assert_nil(lights.on_register(d, { address = 34, value = 8 }))
    for attempt = 2, 3 do
      local r = lights.on_verify(d); apply(d, r)
      assert_eq(d.lights_int.attempts, attempt)
      assert_eq(has(r, "bus.publish").payload, "34 0")
    end
    local failed = lights.on_verify(d); apply(d, failed)
    assert_false(d.lights_int.verified); assert_nil(has(failed, "bus.publish"))
    assert_nil(lights.on_verify(d))
    apply(d, lights.on_apply(d))
    apply(d, lights.on_register(d, { address = 34, value = 0 }))
    assert_true(d.lights_int.verified); assert_nil(lights.on_verify(d))
    for _, t in ipairs({ "power.plugged", "power.charging" }) do
      d.power = { connected = false, charging = false }
      assert_eq(has(lights.on_power(d, { type = t, on = true }), "bus.publish", "topic", "/j/ht/output/raw_write").payload, "34 0")
      assert_nil(lights.on_power(d, { type = t, on = false }))
    end
  end)

  it("reenables the driver and restores current status colours", function()
    local d = doc(); d.limits.dim = true
    local r = lights.on_apply(d)
    assert_eq(has(r, "bus.publish", "topic", "/j/ht/output/raw_write").payload, "34 8")
    assert_true(has(r, "bus.publish", "payload", "RING,10,10,10") ~= nil)
    assert_true(has(r, "bus.publish", "payload", "PREV,10,10,10") ~= nil)
    assert_true(has(r, "bus.publish", "payload", "NEXT,10,10,10") ~= nil)
  end)
end)
