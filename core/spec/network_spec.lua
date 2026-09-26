local network = require("services.network")
local mdns = require("adapters.mdns")

describe("services.network", function()
  it("boot: name from the hostname, log cleanup, wifi log timer", function()
    local r = network.on_boot({ device = { hostname = "JOOKI2-0426E8" } }, { now = 5 })
    assert_eq(r.state.net, { drops = 0, beacons = 0, since = 5, name = "jooki2-0426e8.local" })
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

describe("adapters.mdns packets", function()
  local function query(name, qtype, id)
    local q = ""
    for part in name:gmatch("[^%.]+") do q = q .. string.char(#part) .. part end
    q = q .. string.char(0) .. string.char(0, qtype, 0, 1)
    return (id or "\18\52") .. string.char(0, 0, 0, 1, 0, 0, 0, 0, 0, 0) .. q
  end
  local names = { ["jooki2-0426e8.local"] = true }

  it("parses questions for our names only, any case, A/ANY/AAAA", function()
    assert_eq(#mdns.questions(query("JOOKI2-0426E8.local", 1), names), 1)
    assert_eq(#mdns.questions(query("jooki2-0426e8.local", 28), names), 1)
    assert_eq(#mdns.questions(query("jooki2-0426e8.local", 255), names), 1)
    assert_eq(#mdns.questions(query("jooki2-0426e8.local", 16), names), 0)
    assert_eq(#mdns.questions(query("printer.local", 1), names), 0)
    assert_eq(#mdns.questions("\0\0\132\0", names), 0)          -- a response, not a query
    assert_eq(#mdns.questions("garbage", names), 0)
    assert_eq(#mdns.questions("\18\52\0\0\0\5" .. string.rep("\0", 6) .. "\63abc", names), 0)
  end)

  it("answers A with the address and AAAA with an 'IPv4 only' NSEC; unicast echoes id and question", function()
    local q = mdns.questions(query("jooki2-0426e8.local", 1), names)[1]
    local a = mdns.answer(q, "192.168.1.19", false)
    assert_eq(a:sub(1, 2), "\0\0"); assert_eq(a:byte(3), 132)
    assert_eq(a:sub(-4), string.char(192, 168, 1, 19))
    assert_true(a:find(string.char(0, 1, 128, 1), 1, true) ~= nil, "cache-flush class for multicast")
    local u = mdns.answer(q, "192.168.1.19", true, "\18\52")
    assert_eq(u:sub(1, 2), "\18\52"); assert_eq(u:byte(6), 1)   -- one question echoed
    local q6 = mdns.questions(query("jooki2-0426e8.local", 28), names)[1]
    local a6 = mdns.answer(q6, "10.0.0.2", true, "\1\2")
    assert_true(a6:find(string.char(0, 47), 1, true) ~= nil, "NSEC type")
    assert_eq(a6:sub(-3), string.char(0, 1, 64))
    assert_nil(mdns.answer(q, "not an ip", false))
  end)
end)
