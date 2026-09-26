local log = require("kernel.log")

describe("kernel.log", function()
  local lines, now
  before_each(function()
    lines = {}
    now = 0
    log.configure({ level = "debug", sinks = { function(l, name, sev) lines[#lines + 1] = { l, name, sev } end },
                    clock = function() return now end, window = 60, burst = 3 })
  end)

  it("writes one line with sorted fields", function()
    log.info("playback.play", { playlist = "user_1", ms = 42, title = "Le chat noir" })
    assert_eq(#lines, 1)
    assert_eq(lines[1][1], 'info  playback.play ms=42 playlist=user_1 title="Le chat noir"')
    assert_eq(lines[1][2], "info")
    assert_eq(lines[1][3], 6)
  end)

  it("respects the level", function()
    log.configure({ level = "warn", sinks = { function(l) lines[#lines + 1] = { l } end }, clock = function() return now end })
    assert_false(log.info("x"))
    assert_true(log.warn("x"))
    assert_eq(#lines, 1)
  end)

  it("rate-limits a repeated key and reports the suppressed count", function()
    for _ = 1, 10 do log.error("bus.fail", { code = 1 }) end
    assert_eq(#lines, 3)
    now = 61
    log.error("bus.fail", { code = 1 })
    assert_eq(#lines, 5)
    assert_match(lines[4][1], "suppressed=7")
  end)

  it("rate-limits per key, not globally", function()
    for _ = 1, 5 do log.warn("a") end
    for _ = 1, 5 do log.warn("b") end
    assert_eq(#lines, 6)
  end)

  it("refuses an unknown level", function()
    assert_error(function() log.configure({ level = "loud" }) end, "unknown log level")
  end)
end)
