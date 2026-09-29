local bluetooth = require("services.bluetooth")
local be = require("api.bus_events")
local v1 = require("api.v1")

local SONY = '{"name": "SRS-X11", "mac": "8C:DE:52:BA:D9:F0", "rssi":-25, "cod":"0x00240414"}'

local function topics(r)
  local out = {}
  for _, c in ipairs(r.commands or {}) do if c.kind == "bus.publish" then out[#out + 1] = c.topic:gsub("^/j/esp32/output/bt/", "") .. " " .. c.payload end end
  return out
end

describe("services.bluetooth", function()
  it("bus: discovered and connected devices, as the real chip sends them", function()
    assert_eq(be.translate("/j/esp32/input/bt/device_discovered", SONY),
      { type = "bt.discovered", mac = "8C:DE:52:BA:D9:F0", name = "SRS-X11", cod = 0x240414, rssi = -25 })
    local c = be.translate("/j/esp32/input/bt/device_connected", '{"name": "SRS-X11", "mac": "8c:de:52:ba:d9:f0", "rssi":-128, "cod":"0x00240414"}')
    assert_eq(c.type, "bt.connected"); assert_eq(c.mac, "8C:DE:52:BA:D9:F0")
    assert_true(be.translate("/j/esp32/input/bt/device_discovered", "garbage").bad)
  end)

  it("boot asks the chip, then every 30 s (it never says when a speaker goes away)", function()
    local r = bluetooth.on_boot()
    assert_eq(r.state.bluetooth.state, 0)
    assert_eq(topics(r), { "get_state " })
    assert_eq(r.commands[2], { kind = "timer.every", name = "bluetooth.poll", seconds = 30 })
    assert_eq(topics(bluetooth.on_timer({}, { name = "bluetooth.poll" })), { "get_state " })
    assert_nil(bluetooth.on_timer({}, { name = "other" }))
  end)

  it("scan: the list starts empty, keeps audio devices once each, and the name when it comes late", function()
    local r = bluetooth.on_scan({ bluetooth = { state = 0, devices = { { mac = "old" } } } })
    assert_eq(topics(r), { "start_scan " }); assert_eq(#r.state.bluetooth.devices, 0); assert_eq(r.state.bluetooth.state, 1)
    local doc = { bluetooth = r.state.bluetooth }
    r = bluetooth.on_discovered(doc, { mac = "AA:AA:AA:AA:AA:AA", name = "", cod = 0x240404 })
    doc.bluetooth = r.state.bluetooth
    assert_nil(bluetooth.on_discovered(doc, { mac = "AA:AA:AA:AA:AA:AA", name = "", cod = 0x240404 }))
    r = bluetooth.on_discovered(doc, { mac = "AA:AA:AA:AA:AA:AA", name = "Amp", cod = 0x240404 })
    doc.bluetooth = r.state.bluetooth
    assert_eq(doc.bluetooth.devices, { { mac = "AA:AA:AA:AA:AA:AA", name = "Amp", cod = 0x240404 } })
    assert_nil(bluetooth.on_discovered(doc, { mac = "AA:AA:AA:AA:AA:AA", name = "Amp", cod = 0x240404 }))
    assert_nil(bluetooth.on_discovered(doc, { mac = "BB:BB:BB:BB:BB:BB", name = "Phone", cod = 0x5a020c }))   -- a phone
    assert_true(bluetooth.is_audio(0x240414)); assert_false(bluetooth.is_audio(nil))
  end)

  it("a search lasts 20 s whatever the chip says (it can answer 'searching' for ever)", function()
    local r = bluetooth.on_scan({ bluetooth = { state = 0, devices = {} } })
    assert_eq(r.commands[2], { kind = "timer.once", name = "bluetooth.scan_end", seconds = 20 })
    local doc = { bluetooth = r.state.bluetooth }
    assert_nil(bluetooth.on_state(doc, { code = 1 }))
    r = bluetooth.on_timer(doc, { name = "bluetooth.scan_end" })
    assert_eq(r.state.bluetooth.state, 2); assert_nil(r.state.bluetooth.scanning)
    doc.bluetooth = r.state.bluetooth
    assert_nil(bluetooth.on_state(doc, { code = 1 }))   -- the 30 s poll: still "searching", ignored
  end)

  it("connect: autoconnect off, then MAC<TAB>COD<TAB>name; once connected, autoconnect on once", function()
    local doc = { bluetooth = { state = 2, devices = { { mac = "8C:DE:52:BA:D9:F0", name = "SRS-X11", cod = 0x240414 } } } }
    local r = bluetooth.on_connect(doc, { mac = "8c:de:52:ba:d9:f0" })
    assert_eq(topics(r), { "set_autoconnect false", "connect_device 8C:DE:52:BA:D9:F0\t0x00240414\tSRS-X11" })
    doc.bluetooth = r.state.bluetooth
    r = bluetooth.on_connected(doc, { mac = "8C:DE:52:BA:D9:F0", name = "SRS-X11" })
    assert_eq(topics(r), { "set_autoconnect true" })
    assert_eq(r.state.bluetooth.connected, { mac = "8C:DE:52:BA:D9:F0", name = "SRS-X11" })
    assert_eq(r.state.bluetooth.connected_mac, "8C:DE:52:BA:D9:F0")
    doc.bluetooth = r.state.bluetooth
    assert_nil(bluetooth.on_connected(doc, { mac = "8C:DE:52:BA:D9:F0", name = "SRS-X11" }))   -- every poll: nothing new
    assert_nil(bluetooth.on_state(doc, { code = 5 }))
    -- gone (switched off): the poll says so
    r = bluetooth.on_state(doc, { code = 9 })
    assert_nil(r.state.bluetooth.connected); assert_nil(r.state.bluetooth.connected_mac)
    local _, err = bluetooth.on_connect(doc, { mac = "11:22:33:44:55:66" })
    assert_eq(err.code, "not_found")
    _, err = bluetooth.on_connect(doc, { mac = "nope" })
    assert_eq(err.field, "mac")
  end)

  it("the speaker the chip remembers is offered without a search, and can be connected (no pairing mode needed)", function()
    local s = be.translate("/j/esp32/input/bt/device_saved", '{"name": "SRS-X11", "mac": "8C:DE:52:BA:D9:F0", "rssi":-128, "cod":"0x00240414"}')
    assert_eq(s.type, "bt.saved")
    local doc = { bluetooth = { state = 0, devices = {} } }
    local r = bluetooth.on_saved(doc, s)
    assert_eq(r.state.bluetooth.known, { { mac = "8C:DE:52:BA:D9:F0", name = "SRS-X11", cod = 0x240414 } })
    doc.bluetooth = r.state.bluetooth
    assert_nil(bluetooth.on_saved(doc, s))                       -- every poll: nothing new
    -- the chip remembers several (seen on the real Jooki: the Sony and an amplifier)
    r = bluetooth.on_saved(doc, { mac = "F4:4E:FD:C9:F5:0D", name = "Fosi Audio BT20A", cod = 0x240404 })
    doc.bluetooth = r.state.bluetooth
    assert_eq(#doc.bluetooth.known, 2)
    r = bluetooth.on_connect(doc, { mac = "8C:DE:52:BA:D9:F0" })
    assert_eq(topics(r)[2], "connect_device 8C:DE:52:BA:D9:F0\t0x00240414\tSRS-X11")
    assert_eq(bluetooth.on_forget(doc, { mac = "8C:DE:52:BA:D9:F0" }).state.bluetooth.known, { { mac = "F4:4E:FD:C9:F5:0D", name = "Fosi Audio BT20A", cod = 0x240404 } })
  end)

  it("forget: autoconnect off first (the chip refuses otherwise), then the MAC", function()
    local doc = { bluetooth = { state = 5, auto = true, connected_mac = "8C:DE:52:BA:D9:F0", devices = {} } }
    local r = bluetooth.on_forget(doc, { mac = "8C:DE:52:BA:D9:F0" })
    assert_eq(topics(r), { "set_autoconnect false", "forget_device 8C:DE:52:BA:D9:F0" })
    assert_nil(r.state.bluetooth.connected_mac)
  end)

  it("v1: connecting and forgetting need the parent code, looking does not", function()
    assert_true(v1.PROTECTED.OJ_BT_CONNECT); assert_true(v1.PROTECTED.OJ_BT_FORGET); assert_nil(v1.PROTECTED.OJ_BT_SCAN)
    local r = v1.on_cmd({ bluetooth = { devices = {} } }, { name = "OJ_BT_SCAN", raw = "{}" })
    assert_eq(topics(r), { "start_scan " })
  end)
end)
