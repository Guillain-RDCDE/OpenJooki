local codec = require("adapters.mqtt_codec")
local files = require("adapters.files")
local shell = require("adapters.shell")
local clock = require("adapters.clock")
local host = require("adapters.host")

describe("adapters.mqtt_codec", function()
  it("encodes CONNECT with clean session and keepalive", function()
    local p = codec.connect("core", 30)
    assert_eq(p:byte(1), 0x10)
    assert_eq(p:sub(3, 8), "\0\4MQTT")
    assert_eq(p:byte(9), 4)      -- protocol level
    assert_eq(p:byte(10), 2)     -- clean session
    assert_eq(p:sub(11, 12), "\0\30")
    assert_eq(p:sub(13), "\0\4core")
  end)

  it("encodes and parses PUBLISH, including a payload with binary bytes", function()
    local p = codec.publish("/j/x", "a\0b\255")
    local pkt, n = codec.parse(p .. "extra")
    assert_eq(n, #p)
    assert_eq(pkt, { type = "publish", topic = "/j/x", payload = "a\0b\255", qos = 0 })
  end)

  it("handles multi-byte remaining length", function()
    local big = string.rep("x", 300)
    local p = codec.publish("t", big)
    assert_eq(p:byte(2), 0xAF); assert_eq(p:byte(3), 0x02)   -- 303 = 0x12F -> AF 02
    local pkt = codec.parse(p)
    assert_eq(#pkt.payload, 300)
  end)

  it("parses CONNACK, SUBACK, PINGRESP and reports incomplete or bad input", function()
    assert_eq(codec.parse("\32\2\0\0"), { type = "connack", session_present = false, code = 0 })
    assert_eq(codec.parse("\144\3\0\1\0"), { type = "suback", packet_id = 1, codes = { 0 } })
    assert_eq(codec.parse("\208\0"), { type = "pingresp" })
    local _, why = codec.parse("\48")
    assert_eq(why, "incomplete")
    local _, why2 = codec.parse("\48\255\255\255\255\255")
    assert_eq(why2, "bad")
  end)

  it("SUBSCRIBE lists topics with QoS 0", function()
    local p = codec.subscribe(7, { "/a", "/b/#" })
    assert_eq(p:byte(1), 0x82)
    assert_eq(p:sub(3), "\0\7\0\2/a\0\0\4/b/#\0")
  end)
end)

describe("adapters.files", function()
  local dir = os.getenv("TMPDIR") or "/tmp"
  local path = dir .. "/oj_files_spec.json"
  before_each(function() os.remove(path); os.remove(path .. ".bak"); os.remove(path .. ".tmp") end)

  it("writes and reads back a document with its version", function()
    assert_true(files.write(path, { a = { x = 1 }, list = { "u", "v" } }, 3))
    local doc, ver = files.read(path, 1)
    assert_eq(doc, { a = { x = 1 }, list = { "u", "v" } })
    assert_eq(ver, 3)
    local raw = files.read_text(path)
    assert_match(raw, '^{"_":{')
    assert_match(raw, '"version":3')
  end)

  it("keeps the previous version as .bak and recovers from it when the file is corrupt", function()
    files.write(path, { n = 1 }, 1)
    files.write(path, { n = 2 }, 1)
    assert_eq(files.read(path .. ".bak", 1), { n = 1 })
    files.write_text(path, '{"_":{"version":1},"n":')
    local doc, _, note = files.read(path, 1)
    assert_eq(doc, { n = 1 })
    assert_match(note, "recovered")
  end)

  it("detects truncation through the sum and refuses a too-old version", function()
    files.write(path, { long = string.rep("z", 100) }, 1)
    local raw = files.read_text(path)
    files.write_text(path, raw:gsub('"long":"zzzz', '"long":"zzz'))
    local doc, why = files.read(path, 1)
    assert_nil(doc); assert_eq(why, "bad sum")
    files.write(path, { n = 1 }, 1)
    local d2, why2 = files.read(path, 2)
    assert_nil(d2); assert_eq(why2, "version too low")
  end)

  it("the sum does not depend on the insertion order of nested keys (read back in another process)", function()
    local a = { z = { b = 1, a = { 2, 3 }, c = { x = "y" } }, list = { { k = 1, j = 2 } } }
    files.write(path, a, 1)
    local doc = files.read(path, 1)
    assert_eq(doc, a)
    -- re-encode the decoded copy (different insertion order) and compare bodies
    assert_eq(files.encode_body(doc), files.encode_body(a))
    files.write(path, doc, 1)
    local again, why = files.read(path, 1)
    assert_eq(again, a, why)
  end)

  it("reads 1.x files without a sum (compatibility)", function()
    files.write_text(path, '{"_":{"version":1},"user_1":{"title":"A","tracks":[]}}')
    local doc, ver = files.read(path, 1)
    assert_eq(ver, 1)
    assert_eq(doc.user_1.title, "A")
  end)

  it("refuses a caller-supplied `_`", function()
    assert_error(function() files.write(path, { _ = {} }, 1) end, "managed")
  end)
end)

describe("adapters.shell", function()
  local calls
  before_each(function()
    calls = {}
    shell.count = 0
    shell._set_runner(function(argv, bg) calls[#calls + 1] = { argv = argv, bg = bg } return "out", 0 end)
  end)

  it("runs only named actions with checked arguments", function()
    local out, rc = shell.run("set_lang", { lang = "FR" })
    assert_eq(out, "out"); assert_eq(rc, 0)
    assert_eq(calls[1].argv, { "/jooki/app/services/lang_set.sh", "FR" })
    assert_eq(shell.count, 1)
  end)

  it("refuses unknown actions and bad arguments without spawning", function()
    local o, e = shell.run("rm_rf", {})
    assert_nil(o); assert_match(e, "unknown action")
    o, e = shell.run("set_lang", { lang = "fr; rm -rf /" })
    assert_nil(o); assert_match(e, "bad lang")
    o, e = shell.run("probe_audio", { file = "../etc/passwd", image = "/a", out = "/b" })
    assert_nil(o); assert_match(e, "bad path")
    o, e = shell.run("wifi_add", { ssid = "ok", password = "pass1234" })   -- the Jooki 1's script: gone
    assert_nil(o); assert_match(e, "unknown action")
    for _, bad in ipairs({ "1790780000", 1790780000.5, 0, 1600000000, 4102444800, "@1790780000;reboot" }) do
      o, e = shell.run("set_clock", { utc = bad })
      assert_nil(o); assert_match(e, "bad time")
    end
    assert_eq(#calls, 0); assert_eq(shell.count, 0)
  end)

  it("set_clock: busybox date, UTC, whole seconds", function()
    assert_eq(shell.run("set_clock", { utc = 1790780000 }), "out")
    assert_eq(calls[1].argv, { "date", "-u", "-s", "@1790780000" })
  end)

  it("marks background actions", function()
    shell.run("speak_info", {})
    assert_true(calls[1].bg)
    shell.run("setup_web_dirs", { data = "/jooki/external/jooki" })   -- 0.8 s on the device: never blocks the boot
    assert_true(calls[2].bg)
  end)

  it("set_name: a checked network name, or empty for the factory name; anything else never runs", function()
    assert_eq(shell.run("set_name", { name = "alexandre-2" }), "out")
    assert_eq(calls[1].argv[#calls[1].argv], "alexandre-2")
    assert_eq(shell.run("set_name", { name = "" }), "out")
    for _, bad in ipairs({ "Jooki", "-jooki", "jooki-", "jo oki", "x;reboot", "a.local", string.rep("a", 33), 7 }) do
      local o, e = shell.run("set_name", { name = bad })
      assert_nil(o); assert_match(e, "bad name")
    end
    assert_eq(#calls, 2)
  end)

  it("the updater fetches only from our GitHub or the bench's own server, at the configured address", function()
    local ok = { "https://github.com/Guillain-RDCDE/OpenJooki/releases/latest/download/version.json",
                 "https://guillain-rdcde.github.io/OpenJooki/o.sh", "http://127.0.0.1:8090/oj-test/o.sh" }
    for _, u in ipairs(ok) do assert_true(shell.is_update_url(u), u) end
    for _, bad in ipairs({ "https://example.com/o.sh", "http://127.0.0.1/o.sh", "https://github.com/someone/else/o.sh",
                           "https://guillain-rdcde.github.io/OpenJooki/o.sh;reboot", "ftp://127.0.0.1:1/x", "", 7, nil }) do
      assert_false(shell.is_update_url(bad), tostring(bad))
    end
    assert_eq(shell.run("update_check", { out = "/tmp/web_ctrl_dirs/public/oj-latest.json", url = ok[1] }), "out")
    assert_eq(calls[1].argv[#calls[1].argv], ok[1])
    local o, e = shell.run("update_check", { out = "/tmp/web_ctrl_dirs/public/oj-latest.json", url = "https://example.com/v.json" })
    assert_nil(o); assert_match(e, "bad url")
    o, e = shell.run("update_start", { status = "/jooki/app/www/public/openjooki-status.txt", link = "/tmp/web_ctrl_dirs/public/oj-status.txt" })
    assert_nil(o); assert_match(e, "bad url")
    assert_eq(#calls, 1)
  end)
end)

describe("adapters.clock / host", function()
  it("reads uptime through the injected reader", function()
    clock._set_reader(function() return 123.5 end)
    assert_eq(clock.now(), 123.5)
    clock._set_reader(function() return nil end)
    local a = clock.now()
    assert_true(a >= 0 and a < 1)
  end)

  it("host clamps the volume and works without the C functions", function()
    assert_false(host.available())
    assert_true(host.set_volume(150))
    assert_eq(host._last_volume, 100)
    host.set_volume(-3)
    assert_eq(host._last_volume, 0)
    assert_false(host.terminating())
  end)
end)
