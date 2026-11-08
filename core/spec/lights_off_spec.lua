local device = require("services.device")
local lights = require("services.device.lights")
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
