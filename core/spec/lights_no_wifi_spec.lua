describe("lights off without Wi-Fi, and the driver at power-off", function()
  local lights = require("services.device.lights")
  local power = require("services.device.power")
  local function timer(r, name)
    for _, c in ipairs(r.commands or {}) do if c.kind == "timer.once" and c.name == name then return c end end
  end
  local function driver(r)
    for _, c in ipairs(r.commands or {}) do if c.topic == "/j/ht/output/raw_write" then return c.payload end end
  end

  it("does not wait for the Wi-Fi for ever: a minute, then the cue and darkness", function()
    local doc = { audiocfg = { lights_off = true }, config = {} }
    local r = lights.on_boot(doc, { audiocfg = doc.audiocfg })
    assert_eq(r.state.lights_boot_int.phase, "connecting")
    assert_eq(timer(r, "device.lights_boot").seconds, lights.NO_WIFI_S)
    doc.lights_boot_int = r.state.lights_boot_int
    r = lights.on_boot_frame(doc)
    assert_eq(r.state.lights_boot_int.phase, "blinking")
    local b = r.state.lights_boot_int
    for _ = 1, 6 do
      doc.lights_boot_int = b
      r = lights.on_boot_frame(doc)
      b = r.state.lights_boot_int
    end
    assert_nil(b.phase)
    assert_eq(driver(r), "34 0")
  end)

  it("losing the Wi-Fi during the countdown starts the minute again, it does not stop it", function()
    local doc = { audiocfg = { lights_off = true }, config = {}, lights_boot_int = { phase = "waiting" }, net = { connected = true, ip = "10.0.0.2" } }
    local r = lights.on_net_status(doc, { connected = false })
    assert_eq(r.state.lights_boot_int.phase, "connecting")
    assert_eq(timer(r, "device.lights_boot").seconds, lights.NO_WIFI_S)
  end)

  it("gives the driver back before switching off, unless the parent asked for darkness", function()
    local r = power.on_off_frame({ audiocfg = {}, poweroff_int = { step = 6, reason = "button" } })
    assert_eq(driver(r), "34 8")
    r = power.on_off_frame({ audiocfg = { lights_off = true }, poweroff_int = { step = 6, reason = "button" } })
    assert_nil(driver(r))
  end)
end)
