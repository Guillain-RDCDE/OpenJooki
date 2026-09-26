-- Integration: the real bus adapter against a real mosquitto (127.0.0.1:1883).
--   lua5.1 core/spec/run.lua core/spec/integration/bus_spec.lua
local Bus = require("adapters.bus")
local log = require("kernel.log")
local socket = require("socket")

describe("adapters.bus against mosquitto", function()
  before_each(function() log.configure({ level = "error", sinks = {} }) end)

  it("connects, subscribes, publishes and receives its own message", function()
    local b = Bus.new({ client_id = "spec-" .. os.time(), keepalive = 5, topics = { "/oj/spec/#" } })
    assert_eq(b:maintain(0), "up")
    assert_true(b:connected())
    assert_true(b:publish("/oj/spec/a", "hello"))
    local got
    for _ = 1, 20 do
      local msgs = b:poll(0.1, 1)
      if #msgs > 0 then got = msgs[1] break end
    end
    assert_eq(got, { topic = "/oj/spec/a", payload = "hello" })
    b:close()
    assert_false(b:connected())
  end)

  it("reassembles several packets from one read and large payloads", function()
    local b = Bus.new({ client_id = "spec2-" .. os.time(), topics = { "/oj/spec2/#" } })
    b:maintain(0)
    local big = string.rep("x", 20000)
    b:publish("/oj/spec2/1", "one"); b:publish("/oj/spec2/2", big); b:publish("/oj/spec2/3", "three")
    local got = {}
    for _ = 1, 50 do
      for _, m in ipairs(b:poll(0.1, 1)) do got[#got + 1] = m end
      if #got == 3 then break end
    end
    assert_eq(#got, 3)
    assert_eq(#got[2].payload, 20000)
    assert_eq(got[3].payload, "three")
    b:close()
  end)

  it("reports a failed connection and backs off", function()
    local b = Bus.new({ port = 1, min_backoff = 2, max_backoff = 8 })
    assert_nil(b:maintain(0))
    assert_eq(b.next_attempt, 2)
    assert_nil(b:maintain(1))            -- not yet
    assert_nil(b:maintain(2))
    assert_eq(b.next_attempt, 6)         -- backoff doubled
    assert_eq(b.stats.reconnects, 2)
  end)

  it("keeps the connection alive with pings", function()
    local b = Bus.new({ client_id = "spec3-" .. os.time(), keepalive = 2 })
    b:maintain(0)
    local sent = b.stats.sent
    assert_nil(b:maintain(1.5))          -- keepalive/2 elapsed -> ping
    assert_eq(b.stats.sent, sent + 1)
    socket.sleep(0.2)
    b:poll(0.2, 1.7)
    assert_true(b:connected())
    b:close()
  end)
end)
