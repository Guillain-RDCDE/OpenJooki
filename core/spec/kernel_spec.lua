local fakes = require("fakes")
local commands = require("kernel.commands")
local loop = require("kernel.loop")
local state = require("kernel.state")
local timers = require("kernel.timers")
local dispatch = require("kernel.dispatch")
local config = require("kernel.config")
local log = require("kernel.log")
local json = require("vendor.json")

local function fresh()
  local A = { bus = fakes.bus(), files = fakes.files(), clock = fakes.clock(0), host = fakes.host(), shell = fakes.shell() }
  log.configure({ level = "error", sinks = {}, clock = A.clock.now })
  state.reset({ playback = { state = "idle" } })
  timers.reset()
  dispatch.reset({ budget = 5, clock = A.clock.now })
  config.load({})
  return A
end

describe("kernel.commands", function()
  it("executes each kind through the adapters and reports failures", function()
    local A = fresh()
    local ctx = commands.execute(A, {
      { kind = "bus.publish", topic = "/t", payload = { a = 1 } },
      { kind = "files.write", path = "/x.json", doc = { n = 1 }, version = 2 },
      { kind = "host.volume", percent = 42 },
      { kind = "shell", action = "sync" },
      { kind = "timer.every", name = "tick", seconds = 5 },
      { kind = "emit", event = { type = "custom" } },
      { kind = "log", level = "error", key = "x" },
      { kind = "bogus" },
      { kind = "bus.publish" },
      { kind = "shutdown", reason = "test" },
    })
    assert_eq(A.bus.published[1], { topic = "/t", payload = '{"a":1}' })
    assert_eq(A.files.read("/x.json"), { n = 1 })
    assert_eq(A.host.last_volume(), 42)
    assert_eq(A.shell.calls[1].name, "sync")
    assert_true(timers.pending("tick"))
    assert_eq(ctx.emitted, { { type = "custom" } })
    assert_eq(ctx.failed, 2)
    assert_eq(ctx.shutdown, "test")
  end)
end)

describe("kernel.commands replies", function()
  it("turns a shell output and a file read into events for the next turn", function()
    local A = fresh()
    A.shell.results.md5 = { "0123456789abcdef0123456789abcdef  /f\n", 0 }
    A.files.write_text("/probe.json", '{"duration_s":3}')
    local ctx = commands.execute(A, {
      { kind = "shell", action = "md5", args = { file = "/f" }, reply = "upload.hashed", ref = { id = 7 } },
      { kind = "files.read_text", path = "/probe.json", reply = "upload.probed", ref = "x" },
      { kind = "files.read_text", path = "/missing", reply = "upload.probed" },
      { kind = "shell", action = "nope", reply = "r" },
    })
    assert_eq(ctx.emitted[1], { type = "upload.hashed", action = "md5", out = "0123456789abcdef0123456789abcdef  /f\n", rc = 0, ref = { id = 7 } })
    assert_eq(ctx.emitted[2], { type = "upload.probed", path = "/probe.json", text = '{"duration_s":3}', ref = "x" })
    assert_eq(ctx.emitted[3], { type = "upload.probed", path = "/missing", ref = nil })
    assert_eq(ctx.emitted[4].rc, -1)
  end)
end)

describe("kernel.loop", function()
  it("delivers bus messages as events, applies state, publishes coalesced patches", function()
    local A = fresh()
    dispatch.on("nfc.tag", "tokens", function(doc, ev)
      return { state = { tokens = { last = ev.uid } }, commands = { { kind = "bus.publish", topic = "/cmd", payload = ev.uid } } }
    end)
    local published_patches = {}
    loop.init(A, {
      translate = function(topic, payload) if topic == "/j/nfc/input/tag" then return { type = "nfc.tag", uid = payload } end end,
      publisher = function(doc, keys) published_patches[#published_patches + 1] = keys; return { { kind = "bus.publish", topic = "/state", payload = state.patch(keys) } } end,
    })
    A.bus:receive("/j/nfc/input/tag", "04AA")
    A.bus:receive("/j/other", "ignored")
    assert_eq(loop.step(0), 1)
    assert_eq(state.get("tokens"), { last = "04AA" })
    assert_eq(A.bus:last("/cmd"), "04AA")
    assert_eq(published_patches, { { "tokens" } })
    assert_eq(json.decode(A.bus:last("/state")).rev, 1)
    -- a second change within the coalescing window waits for the next window
    A.bus:receive("/j/nfc/input/tag", "04BB")
    loop.step(0)
    assert_eq(#published_patches, 1)
    A.clock.advance(0.3)
    loop.step(0)
    assert_eq(#published_patches, 2)
  end)

  it("fires timers as events and lets emitted events run on the next turn", function()
    local A = fresh()
    local seen = {}
    dispatch.on("timer", "m", function(doc, ev) seen[#seen + 1] = ev.name; return { commands = { { kind = "emit", event = { type = "after" } } } } end)
    dispatch.on("after", "m", function() seen[#seen + 1] = "after" end)
    loop.init(A, {})
    timers.every("beat", 2, 0)
    loop.step(0); assert_eq(seen, {})
    A.clock.set(2)
    loop.step(0); assert_eq(seen, { "beat" })
    loop.step(0); assert_eq(seen, { "beat", "after" })
  end)

  it("reports bus transitions and host termination, and stops on a shutdown command", function()
    local A = fresh()
    local seen = {}
    dispatch.on("bus.down", "m", function() seen[#seen + 1] = "down" end)
    dispatch.on("bus.up", "m", function() seen[#seen + 1] = "up" end)
    dispatch.on("host.terminating", "m", function() return { commands = { { kind = "shutdown", reason = "sigterm" } } } end)
    loop.init(A, {})
    A.bus.transitions = { "down", "up" }
    loop.step(0); loop.step(0)
    assert_eq(seen, { "down", "up" })
    A.host.is_terminating = true
    loop.step(0)
    assert_eq(loop.stopped(), "sigterm")
  end)

  it("marks the state degraded when a handler is disabled, and keeps running", function()
    local A = fresh()
    dispatch.on("t", "flaky", function() error("x") end)
    loop.init(A, {})
    for _ = 1, 7 do loop.emit({ type = "t" }); loop.step(0) end
    assert_eq(state.get("health"), { degraded = true, module = "flaky" })
    assert_nil(loop.stopped())
  end)
end)
