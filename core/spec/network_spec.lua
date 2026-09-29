local network = require("services.network")
local mdns = require("adapters.mdns")

describe("services.network", function()
  it("boot: name from the hostname, log cleanup, wifi log timer", function()
    local r = network.on_boot({ device = { hostname = "JOOKI2-A1B2C3" } }, { now = 5 })
    assert_eq(r.state.net, { drops = 0, beacons = 0, since = 5, name = "jooki2-a1b2c3.local" })
    assert_eq(r.commands[1], { kind = "shell", action = "log_cleanup" })
    assert_eq(r.commands[2].name, "network.wifi_log")
  end)

  it("status from the chip, drops and beacon losses from the log, access point known either way", function()
    local doc = { net = { drops = 0, beacons = 0 } }
    local r = network.on_status(doc, { ssid = "Box", signal = -70, connected = true, ip = "10.0.0.2", channel = 1 })
    assert_eq(r.state.net.ap, "Box"); assert_eq(r.state.net.ip, "10.0.0.2")
    doc.net = r.state.net
    r = network.on_wifi_log(doc, { text = "x wifi:connected with Salon, aid = 1\ny wifi:bcn_timout\nz wifi:state: run -> init (c800)\n" })
    assert_eq(r.state.net.drops, 1); assert_eq(r.state.net.beacons, 1); assert_eq(r.state.net.ap, "Box")
    doc.net = r.state.net
    assert_nil(network.on_wifi_log(doc, { text = "x wifi:connected with Salon, aid = 1\ny wifi:bcn_timout\nz wifi:state: run -> init (c800)\n" }))
    doc.net.connected = false
    r = network.on_wifi_log(doc, { text = "x wifi:connected with Salon, aid = 1\n" })
    assert_eq(r.state.net.ap, "Salon")
    assert_eq({ network.read_wifi_log(nil) }, { 0, 0, nil })
  end)
end)

describe("services.network — Wi-Fi watchdog", function()
  local function kinds(r)
    local out = {}
    for _, c in ipairs((r and r.commands) or {}) do out[#out + 1] = c.kind .. (c.action and (" " .. c.action) or "") .. (c.path and (" " .. c.path) or "") end
    return out
  end
  local function apply(doc, r) for k, v in pairs((r and r.state) or {}) do doc[k] = v end return r end
  local function offline_doc(extra)
    local doc = { net = { connected = false, ip = "" }, net_watch = { count = 0 }, flags = {}, device = { airplane = false },
                  playback = { state = "idle" }, power = { connected = true } }
    for k, v in pairs(extra or {}) do doc[k] = v end
    return doc
  end
  local function has(r, s) for _, k in ipairs(kinds(r)) do if k == s then return true end end return false end

  it("offline 10 minutes on the charger, nothing playing: a silent restart, counted on /data", function()
    local doc = offline_doc()
    apply(doc, network.on_timer(doc, { name = "network.status", now = 100 }))
    assert_eq(doc.net_watch.since, 100)
    local r = network.on_timer(doc, { name = "network.status", now = 100 + 599 })
    assert_false(has(r, "shell watchdog_reboot"))
    r = apply(doc, network.on_timer(doc, { name = "network.status", now = 100 + 600 }))
    assert_true(has(r, "shell watchdog_reboot"))
    assert_true(has(r, "files.write_text /data/openjooki/wifi_watchdog"))
    assert_true(has(r, "files.write_text /data/openjooki/quiet_boot"))
    assert_eq(doc.net_watch.count, 1)
    -- still asks the chip for its state first, as before
    assert_eq(r.commands[1].topic, "/j/esp32/output/net/sta/status")
  end)

  it("never while playing, on battery, in airplane mode, or after two restarts in a row", function()
    local cases = {
      { playback = { state = "playing" } }, { playback = { state = "idle", sys = { name = "Evt.X" } } },
      { power = { connected = false } }, { flags = { WIFI_OFF = true } }, { flags = { OJ_AIRPLANE = true } },
      { device = { airplane = { ends = 1 } } }, { net_watch = { count = 2 } },
    }
    for i, extra in ipairs(cases) do
      local doc = offline_doc(extra)
      doc.net_watch = extra.net_watch or { count = 0 }
      apply(doc, network.on_timer(doc, { name = "network.status", now = 0 }))
      local r = network.on_timer(doc, { name = "network.status", now = 5000 })
      assert_false(has(r, "shell watchdog_reboot"), "case " .. i)
    end
  end)

  it("the Wi-Fi back: the count goes back to 0 on /data; a short drop starts the 10 minutes again", function()
    local doc = offline_doc({ net_watch = { count = 1 } })
    apply(doc, network.on_timer(doc, { name = "network.status", now = 0 }))
    doc.net = { connected = true, ip = "192.168.1.19" }
    local r = apply(doc, network.on_timer(doc, { name = "network.status", now = 30 }))
    assert_true(has(r, "files.write_text /data/openjooki/wifi_watchdog"))
    assert_eq(doc.net_watch.count, 0); assert_nil(doc.net_watch.since)
    assert_eq(kinds(network.on_timer(doc, { name = "network.status", now = 60 })), { "bus.publish" })   -- online: nothing more
    doc.net = { connected = false }
    apply(doc, network.on_timer(doc, { name = "network.status", now = 90 }))
    assert_eq(doc.net_watch.since, 90)
  end)

  it("boot reads the restarts already made", function()
    assert_eq(network.on_boot({ device = {} }, { now = 1, wifi_watchdog = "2\n" }).state.net_watch, { count = 2 })
    assert_eq(network.on_boot({ device = {} }, { now = 1 }).state.net_watch, { count = 0 })
  end)
end)

describe("adapters.broker_watch", function()
  it("starts the broker after 20 s without it, then at most once a minute; quiet again once back", function()
    local calls = {}
    local w = require("adapters.broker_watch").new({ shell = { run = function(name) calls[#calls + 1] = name return "started", 0 end }, after_s = 20, every_s = 60 })
    assert_nil(w:check(true, 0))
    assert_nil(w:check(false, 1))
    assert_nil(w:check(false, 20.9))
    assert_eq(w:check(false, 21), "restart")
    assert_nil(w:check(false, 50))
    assert_eq(w:check(false, 81), "restart")
    assert_eq(calls, { "broker_start", "broker_start" })
    assert_nil(w:check(true, 82))
    assert_nil(w:check(false, 83))           -- a new outage waits its 20 s again
    assert_eq(w:check(false, 103), "restart")
  end)
end)

describe("adapters.mdns packets", function()
  local function query(name, qtype, id)
    local q = ""
    for part in name:gmatch("[^%.]+") do q = q .. string.char(#part) .. part end
    q = q .. string.char(0) .. string.char(0, qtype, 0, 1)
    return (id or "\18\52") .. string.char(0, 0, 0, 1, 0, 0, 0, 0, 0, 0) .. q
  end
  local names = { ["jooki2-a1b2c3.local"] = true }

  it("parses questions for our names only, any case, A/ANY/AAAA", function()
    assert_eq(#mdns.questions(query("JOOKI2-A1B2C3.local", 1), names), 1)
    assert_eq(#mdns.questions(query("jooki2-a1b2c3.local", 28), names), 1)
    assert_eq(#mdns.questions(query("jooki2-a1b2c3.local", 255), names), 1)
    assert_eq(#mdns.questions(query("jooki2-a1b2c3.local", 16), names), 0)
    assert_eq(#mdns.questions(query("printer.local", 1), names), 0)
    assert_eq(#mdns.questions("\0\0\132\0", names), 0)          -- a response, not a query
    assert_eq(#mdns.questions("garbage", names), 0)
    assert_eq(#mdns.questions("\18\52\0\0\0\5" .. string.rep("\0", 6) .. "\63abc", names), 0)
  end)

  it("answers A with the address and AAAA with an 'IPv4 only' NSEC; unicast echoes id and question", function()
    local q = mdns.questions(query("jooki2-a1b2c3.local", 1), names)[1]
    local a = mdns.answer(q, "192.168.1.19", false)
    assert_eq(a:sub(1, 2), "\0\0"); assert_eq(a:byte(3), 132)
    assert_eq(a:sub(-4), string.char(192, 168, 1, 19))
    assert_true(a:find(string.char(0, 1, 128, 1), 1, true) ~= nil, "cache-flush class for multicast")
    local u = mdns.answer(q, "192.168.1.19", true, "\18\52")
    assert_eq(u:sub(1, 2), "\18\52"); assert_eq(u:byte(6), 1)   -- one question echoed
    local q6 = mdns.questions(query("jooki2-a1b2c3.local", 28), names)[1]
    local a6 = mdns.answer(q6, "10.0.0.2", true, "\1\2")
    assert_true(a6:find(string.char(0, 47), 1, true) ~= nil, "NSEC type")
    assert_eq(a6:sub(-3), string.char(0, 1, 64))
    assert_nil(mdns.answer(q, "not an ip", false))
  end)
end)
