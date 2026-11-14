local device = require("services.device")
local radio = require("services.device.radio")
local schema = require("api.schema")
local security = require("services.security")
local v1 = require("api.v1")
local json = require("vendor.json")

local function doc()
  return { audiocfg = { volume = 80, toy_safe_maxvol = 35, lights_off = false },
           device = { toy_safe = true, volume_api = 2 }, config = { data_dir = "/d", wifi_anim_s = 0 },
           net = { connected = true, ip = "10.0.0.2" }, limits = { maxvol = 100, fade = 1 } }
end
local function has(r, kind, key, value)
  for _, c in ipairs((r or {}).commands or {}) do if c.kind == kind and (not key or c[key] == value) then return c end end
end
local function apply(d, r) for k, v in pairs((r or {}).state or {}) do d[k] = v end end

describe("volume firmware compatibility", function()
  it("leaves the factory kids attenuation in charge without global volume support", function()
    for _, api in ipairs({ false, 0, 1, 3 }) do
      local d = doc(); d.device.volume_api = api or nil
      for _, maximum in ipairs({ 0, 35, 56, 100 }) do
        d.audiocfg.toy_safe_maxvol = maximum
        for _, requested in ipairs({ 80, 100 }) do
          assert_eq(device.effective_volume(d, requested), requested)
          local c = device.set_volume(d, requested).commands[1]
          assert_eq(c.percent, requested); assert_false(c.esp32); assert_false(c.global_volume)
          assert_true(c.toy_safe)
        end
      end
      local boot = device.on_boot(d, { audiocfg = { volume = 80 }, flags = {} })
      assert_eq(has(boot, "host.volume").percent, 80)
      d.limits = { maxvol = 70, fade = 0.5 }
      assert_eq(device.effective_volume(d, 100), 35)
      d.upnp = { muted = true }
      assert_eq(device.effective_volume(d, 100), 0)
      d.upnp = nil; d.streaming_int = { find = { skips = 1 } }
      assert_eq(device.effective_volume(d, 100), 0)
    end
  end)

  it("reapplies the legacy headphone policy when support disappears without dial movement", function()
    for _, api in ipairs({ false, 0, 1 }) do
      local d = doc(); d.volume_int = { knob = 80 }
      local r = device.on_knobs(d, { volume = 80, volume_api = api or nil })
      apply(d, r)
      assert_eq(has(r, "emit").event.type, "volume.apply")
      assert_true(has(r, "emit").event.force)
      assert_nil(r.state.audiocfg)
      local c = device.on_apply_volume(d).commands[1]
      assert_eq(c.percent, 80); assert_false(c.esp32); assert_false(c.global_volume)
    end
    local d = doc()
    local r = device.on_bus_up(d); apply(d, r)
    assert_eq(has(r, "emit").event.type, "volume.apply")
    assert_true(has(r, "emit").event.force)
    assert_eq(device.on_apply_volume(d).commands[1].percent, 80)
  end)

  it("silences wired output switches and restores the saved level under the negotiated policy", function()
    for _, api in ipairs({ 0, 1, 2 }) do
      local d = doc(); d.device.volume_api = api; d.power = { connected = false }
      local dial = api == 2 and 8 or 80   -- without API 2 the saved volume is the dial's
      d.hp_int = { mux = "1" }; d.volume_int = { knob = dial }
      for _, plugged in ipairs({ true, false }) do
        apply(d, device.on_knobs(d, { volume = dial, headphones = plugged, volume_api = api }))
        local r = device.on_knobs(d, { volume = dial, headphones = plugged, volume_api = api })
        apply(d, r)
        assert_eq(d.audiocfg.headphones_en, plugged)
        local levels = {}
        for _, c in ipairs(r.commands) do
          if c.kind == "host.volume" then
            levels[#levels + 1] = c.percent
            assert_eq(c.esp32, api == 2)
          end
        end
        assert_eq(levels, { 0, api == 2 and 35 or 80 })
        assert_eq(d.audiocfg.volume, 80)
      end
    end
  end)
end)

describe("parent maximum", function()
  it("caps before fading, combines with night, and never changes requested volume", function()
    local d = doc()
    for _, max in ipairs({ 0, 1, 35, 100 }) do
      d.audiocfg.toy_safe_maxvol = max
      for _, night in ipairs({ 0, 20, 100 }) do
        d.limits = { maxvol = night, fade = 0.5 }
        local expected = math.floor(math.min(80, max, night) * 0.5 + 0.5)
        local r = device.set_volume(d, 80)
        assert_eq(r.commands[1].percent, expected)
        assert_eq(r.commands[1].maximum, math.floor(math.min(max, night) * 0.5 + 0.5))
        assert_true(r.commands[1].esp32)
        assert_eq(r.state.audiocfg.volume, 80)
      end
    end
    d.device.toy_safe = false; d.limits = { maxvol = 70, fade = 1 }; d.audiocfg.toy_safe_maxvol = 0
    assert_eq(device.effective_volume(d, 80), 70)
  end)

  it("persists 0 and 100, reapplies changes, restores at boot and on kids mode changes", function()
    local d = doc()
    assert_eq(device.audiocfg_of({}).toy_safe_maxvol, 56)
    for _, value in ipairs({ 0, 100, 37 }) do
      local r = device.update_config(d, { toy_safe_maxvol = value })
      assert_eq(has(r, "files.write").doc.toy_safe_maxvol, value)
      local emitted = false
      for _, c in ipairs(r.commands) do if c.kind == "emit" and c.event.type == "volume.apply" then emitted = true end end
      assert_true(emitted); apply(d, r)
      local boot = device.on_boot(d, { audiocfg = d.audiocfg, flags = {} })
      assert_eq(has(boot, "host.volume").percent, math.min(value, 80))
    end
    local off = radio.on_toy_safe(d, { enable = false }); apply(d, off)
    assert_eq(device.on_apply_volume(d).commands[1].percent, 80)
    apply(d, radio.on_toy_safe(d, { enable = true }))
    assert_eq(device.on_apply_volume(d).commands[1].percent, 37)
  end)

  it("keeps physical movements within the ceiling and both outputs silent while muted", function()
    local d = doc(); d.volume_int = { knob = 4 }
    local r = device.on_gpio_volume(d, { percent = 95 }); apply(d, r)
    assert_eq(r.commands[1].percent, 35); assert_eq(d.audiocfg.volume, 95)
    d.upnp = { muted = true }
    r = device.on_apply_volume(d)
    assert_eq(r.commands[1].percent, 0); assert_eq(r.commands[1].maximum, 0)
    r = device.set_volume(d, 70); apply(d, r)
    assert_nil(d.upnp.muted); assert_eq(r.commands[1].percent, 35)
    assert_eq(device.on_apply_volume(d).commands[1].percent, 35)
  end)
end)

describe("maximum volume with kids mode off (max_volume, #10)", function()
  local function off(api) local d = doc(); d.device.volume_api = api; d.device.toy_safe = false; return d end
  it("changes nothing until a parent sets it: 100 is no limit", function()
    local d = off(nil)
    assert_eq(device.audiocfg_of(d).max_volume, 100)
    assert_eq(device.effective_volume(d, 100), 100)
    d.audiocfg.max_volume = 100
    assert_eq(device.effective_volume(d, 100), 100)
  end)
  it("caps with kids mode off only, the night maximum still wins when lower, the requested volume is kept", function()
    for _, api in ipairs({ false, 2 }) do
      local d = off(api or nil); d.audiocfg.max_volume = 70
      assert_eq(device.effective_volume(d, 100), 70); assert_eq(device.effective_volume(d, 50), 50)
      d.limits = { maxvol = 40, fade = 1 }; assert_eq(device.effective_volume(d, 100), 40)
      d.limits = { maxvol = 100, fade = 1 }; d.device.toy_safe = true
      assert_eq(device.effective_volume(d, 100), api == 2 and 35 or 100)
    end
    local d = off(nil); d.audiocfg.max_volume = 70; d.volume_int = { knob = 100 }
    local r = device.set_volume(d, 100)
    assert_eq(r.state.audiocfg.volume, 100)
    local c = has(r, "host.volume"); assert_eq(c.percent, 70); assert_eq(c.mixer, 70)
    d.audiocfg.headphones_en = true
    c = has(device.set_volume(d, 100), "host.volume"); assert_eq(c.percent, 70); assert_eq(c.mixer, 70)
  end)
  it("is saved and applied at once from both interfaces, invalid values write nothing", function()
    local d = off(nil)
    local r = device.update_config(d, { max_volume = 60 })
    assert_eq(r.state.audiocfg.max_volume, 60); assert_true(has(r, "emit") ~= nil)
    assert_eq(has(r, "files.write").doc.max_volume, 60)
    r = v1.on_cmd(d, { name = "SET_CFG", raw = json.encode({ max_volume = 0 }) })
    assert_eq(r.state.audiocfg.max_volume, 0)
    for _, v in ipairs({ -1, 101, 2.5, "35", false, {} }) do
      local p = { max_volume = v }
      assert_false(schema.validate(p, device.schemas.config))
      local rr, e = device.update_config(d, p); assert_nil(rr); assert_eq(e.field, "max_volume")
    end
    for _, v in ipairs({ 0, 35, 100 }) do assert_true(schema.validate({ max_volume = v }, device.schemas.config)) end
  end)
end)

describe("device configuration contract", function()
  it("both interfaces reject invalid maximums without writing anything", function()
    local d = doc()
    for _, field in ipairs({ "toy_safe_maxvol" }) do
      local bad = field == "toy_safe_maxvol" and { -1, 101, 2.5, "35", false, {} } or { 0, 1, "false", {} }
      for _, value in ipairs(bad) do
        local p = { [field] = value }
        assert_false(schema.validate(p, device.schemas.config))
        local r, e = device.update_config(d, p)
        assert_nil(r); assert_eq(e.field, field)
        r = v1.on_cmd(d, { name = "SET_CFG", raw = json.encode(p) })
        assert_nil(r.state); assert_true(has(r, "bus.publish", "topic", v1.TOPIC_ERROR) ~= nil)
      end
    end
    for _, v in ipairs({ 0, 35, 100 }) do assert_true(schema.validate({ toy_safe_maxvol = v }, device.schemas.config)) end
  end)

  it("SET_CFG and device.set_config require the parent code, requested volume remains open", function()
    security._set_parent_code("1234")
    local p = { toy_safe_maxvol = 20 }
    local d = doc()
    local denied = v1.on_cmd(d, { name = "SET_CFG", raw = json.encode(p) })
    assert_nil(denied.state)
    assert_true(security.gate(security.PROTECTED_V2, "device.set_config", nil) ~= nil)
    assert_nil(security.gate(security.PROTECTED_V2, "device.set_config", "1234"))
    p.code = "1234"
    local allowed = v1.on_cmd(d, { name = "SET_CFG", raw = json.encode(p) })
    assert_eq(allowed.state.audiocfg.toy_safe_maxvol, 20)
    assert_nil(security.gate(v1.PROTECTED, "SET_VOL", nil))
    security._set_parent_code(nil)
  end)
end)


describe("global volume scale migration", function()
  it("keeps the factory speaker ceiling initially and migrates earlier relative ceilings down", function()
    for _, old in ipairs({ 0, 7, 30, 40, 75, 100 }) do
      local d = doc()
      local r = device.on_boot(d, { audiocfg = { volume = 10, toy_safe_maxvol = old }, flags = {} })
      local a = r.state.audiocfg
      assert_true(a.toy_safe_maxvol_global)
      local function curve(v) return v == 0 and 0 or v == 1 and 0.005 or 10 ^ ((v - 100) / 50) end
      assert_true(curve(a.toy_safe_maxvol) * 1.5 <= curve(old) * 0.2 + 1e-9)
      local again = device.on_boot(d, { audiocfg = a, flags = {} })
      assert_eq(again.state.audiocfg.toy_safe_maxvol, a.toy_safe_maxvol)
    end
    assert_eq(device.on_boot(doc(), { flags = {} }).state.audiocfg.toy_safe_maxvol, 56)
    assert_eq(device.on_boot(doc(), { flags = {} }).state.audiocfg.volume, 40)
  end)

  it("keeps an explicitly configured global maximum through restarts", function()
    local d = doc()
    local r = device.update_config(d, { toy_safe_maxvol = 100 }); apply(d, r)
    assert_true(d.audiocfg.toy_safe_maxvol_global)
    assert_eq(device.on_boot(d, { audiocfg = d.audiocfg, flags = {} }).state.audiocfg.toy_safe_maxvol, 100)
  end)
end)
