local state = require("kernel.state")

describe("kernel.state", function()
  before_each(function() state.reset({ playback = { state = "idle" }, device = { volume = 40 } }) end)

  it("starts at rev 0 with the initial sub-trees", function()
    assert_eq(state.rev(), 0)
    assert_eq(state.get("playback"), { state = "idle" })
  end)

  it("bumps rev only when a sub-tree really changes", function()
    assert_false(state.set("playback", { state = "idle" }))
    assert_eq(state.rev(), 0)
    assert_true(state.set("playback", { state = "playing" }))
    assert_eq(state.rev(), 1)
  end)

  it("tracks dirty keys and builds a patch", function()
    state.set("playback", { state = "playing" })
    state.set("device", { volume = 50 })
    state.set("device", { volume = 50 })
    assert_eq(state.take_dirty(), { "device", "playback" })
    assert_eq(state.take_dirty(), {})
    local p = state.patch({ "device" })
    assert_eq(p, { rev = 2, patch = { device = { volume = 50 } } })
  end)

  it("apply() changes several keys in a stable order and reports them", function()
    local changed = state.apply({ device = { volume = 60 }, playback = { state = "idle" }, library = { n = 1 } })
    assert_eq(changed, { "device", "library" })
    assert_eq(state.rev(), 2)
  end)

  it("refuses to touch rev", function()
    assert_error(function() state.set("rev", 99) end, "rev is managed")
  end)

  it("snapshot is a deep copy", function()
    local s = state.snapshot()
    s.playback.state = "hacked"
    assert_eq(state.get("playback").state, "idle")
  end)
end)
