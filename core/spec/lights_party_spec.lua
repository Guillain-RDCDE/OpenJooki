-- #54: the Christmas tree as long as the parents want, from the heart too; the everyday lights in
-- the parents' colours; a playlist's own lights. The configuration and the commands that carry them.
local device = require("services.device")
local buttons = require("services.device.buttons")
local library = require("services.library")
local schema = require("api.schema")
local security = require("services.security")
local v1 = require("api.v1")
local json = require("vendor.json")

local function doc()
  return { audiocfg = { volume = 40, shuffle_mode = false, repeat_mode = 1 }, device = { toy_safe = true },
           config = { data_dir = "/d", wifi_anim_s = 0 }, net = { connected = true, ip = "10.0.0.2" },
           library = { playlists = { p1 = { title = "P", tracks = {} } }, tracks = {}, tokens = {} } }
end
local function has(r, kind, key, value)
  for _, c in ipairs((r or {}).commands or {}) do if c.kind == kind and (not key or c[key] == value) then return c end end
end
local function emitted(r, name)
  for _, c in ipairs((r or {}).commands or {}) do if c.kind == "emit" and c.event.type == name then return c end end
end

describe("the Christmas tree's length and the heart (#54)", function()
  it("party_s: an integer from 0 (until stopped) to 3600, kept in audiocfg; 5 s by default", function()
    assert_eq(device.audiocfg_of(doc()).party_s, 5)
    local r = device.update_config(doc(), { party_s = 300 })
    assert_eq(r.state.audiocfg.party_s, 300); assert_eq(has(r, "files.write").doc.party_s, 300)
    assert_eq(device.update_config(doc(), { party_s = 0 }).state.audiocfg.party_s, 0)
    for _, bad in ipairs({ -1, 3601, 2.5, "60", true }) do
      local rr, e = device.update_config(doc(), { party_s = bad })
      assert_nil(rr); assert_eq(e.field, "party_s")
    end
    assert_true(schema.validate({ party_s = 0 }, device.schemas.config))
    assert_false(schema.validate({ party_s = 4000 }, device.schemas.config))
    local d = doc(); d.audiocfg.party_s = "x"
    assert_eq(device.audiocfg_of(d).party_s, 5)   -- an odd file reads as the default
  end)

  it("the heart can start and stop the tree, and then switches off only held 5 s", function()
    local d = doc(); d.audiocfg.heart_press = "party"; d.activity = { buttons = { circle = 5 } }
    local r = buttons.on_button(d, { button = "circle", down = false, now = 5.3 })
    assert_true(emitted(r, "lights.party") ~= nil)
    d.activity = { buttons = { circle = 10 } }
    assert_nil(buttons.on_tick(d, { now = 14.9 }))
    assert_true(emitted(buttons.on_tick(d, { now = 15.1 }), "power.off_request") ~= nil)
    assert_eq(device.update_config(doc(), { heart_press = "party" }).state.audiocfg.heart_press, "party")
    assert_true(schema.validate({ heart_press = "party" }, device.schemas.config))
  end)

  it("the page's button stays open to the children; SET_CFG carries the length behind the parent code", function()
    assert_nil(security.gate(v1.PROTECTED, "OJ_PARTY", nil))
    local r = v1.on_cmd(doc(), { name = "SET_CFG", raw = json.encode({ party_s = 60, heart_press = "party" }) })
    assert_eq(r.state.audiocfg.party_s, 60); assert_eq(r.state.audiocfg.heart_press, "party")
    security._set_parent_code("1234")
    assert_nil(v1.on_cmd(doc(), { name = "SET_CFG", raw = json.encode({ party_s = 60 }) }).state)
    security._set_parent_code(nil)
  end)
end)

describe("two presses on the heart: the Christmas tree (#54)", function()
  local function press(d, now)
    d.activity = d.activity or {}; d.activity.buttons = { circle = now - 0.1 }
    local r = buttons.on_button(d, { button = "circle", down = false, now = now })
    if r and r.state and r.state.activity then d.activity = r.state.activity end
    return r
  end
  it("off by default: the short press acts at once, as before", function()
    local d = doc(); d.audiocfg.heart_press = "pause"
    assert_false(device.audiocfg_of(d).heart_double_party)
    assert_true(emitted(press(d, 5), "playback.toggle_request") ~= nil)
  end)
  it("on: two presses start the tree and the first does nothing; one press acts after 0.4 s", function()
    local d = doc(); d.audiocfg.heart_press = "pause"; d.audiocfg.heart_double_party = true
    local r = press(d, 5)
    assert_nil(emitted(r, "playback.toggle_request")); assert_eq(has(r, "timer.once", "name", "device.heart_single").seconds, 0.4)
    r = press(d, 5.3)
    assert_true(emitted(r, "lights.party") ~= nil); assert_true(has(r, "timer.cancel", "name", "device.heart_single") ~= nil)
    assert_nil(emitted(r, "playback.toggle_request"))
    assert_nil(buttons.on_timer(d, { name = "device.heart_single", now = 5.4 }))   -- nothing left to do
    -- a single press: the pause comes when the wait is over
    press(d, 10)
    r = buttons.on_timer(d, { name = "device.heart_single", now = 10.4 })
    assert_true(emitted(r, "playback.toggle_request") ~= nil); assert_nil(r.state.activity.heart_at)
    -- two presses too far apart: two single presses
    press(d, 20); d.activity = buttons.on_timer(d, { name = "device.heart_single", now = 20.4 }).state.activity
    r = press(d, 20.9)
    assert_nil(emitted(r, "lights.party")); assert_true(has(r, "timer.once", "name", "device.heart_single") ~= nil)
  end)
  it("on, with nothing on the short press: one press does nothing, two the tree; held 5 s to switch off", function()
    local d = doc(); d.audiocfg.heart_double_party = true
    press(d, 5)
    local r = buttons.on_timer(d, { name = "device.heart_single", now = 5.4 })
    assert_eq(r.commands, {})
    assert_true(emitted(press(d, 6), "lights.party") == nil)
    assert_true(emitted(press(d, 6.2), "lights.party") ~= nil)
    d.activity = { buttons = { circle = 10 } }
    assert_nil(buttons.on_tick(d, { now = 14.9 }))
  end)
  it("the switch: a boolean, by SET_CFG and device.set_config", function()
    assert_true(device.update_config(doc(), { heart_double_party = true }).state.audiocfg.heart_double_party)
    assert_true(schema.validate({ heart_double_party = true }, device.schemas.config))
    assert_false(schema.validate({ heart_double_party = 1 }, device.schemas.config))
    assert_true(v1.on_cmd(doc(), { name = "SET_CFG", raw = json.encode({ heart_double_party = true }) }).state.audiocfg.heart_double_party)
  end)
end)

describe("the parents' colours (#54)", function()
  it("each light takes a #rrggbb, kept in lower case; false or \"\" gives it back; seen at once", function()
    local r = device.update_config(doc(), { colours = { off = "#8000FF", ring = "#ff0000" } })
    assert_eq(r.state.audiocfg.colours, { off = "#8000ff", ring = "#ff0000" })
    assert_true(emitted(r, "lights.refresh") ~= nil)
    local d = doc(); d.audiocfg = r.state.audiocfg
    r = device.update_config(d, { colours = { off = false, ring = "" } })
    assert_eq(r.state.audiocfg.colours, {})
    r = device.update_config(d, { colours = { dots = "#00ff00" } })
    assert_eq(r.state.audiocfg.colours, { off = "#8000ff", ring = "#ff0000", dots = "#00ff00" })   -- the others kept
  end)

  it("refuses an unknown light or a colour that is not #rrggbb, on both interfaces", function()
    for _, bad in ipairs({ { heart = "#ff0000" }, { off = "red" }, { off = "#ff00" }, { off = true }, "x" }) do
      local r, e = device.update_config(doc(), { colours = bad })
      assert_nil(r); assert_eq(e.field, "colours")
      local v = v1.on_cmd(doc(), { name = "SET_CFG", raw = json.encode({ colours = bad }) })
      assert_nil(v.state)
    end
    assert_true(schema.validate({ colours = { off = "#8000ff", ring = false } }, device.schemas.config))
    assert_false(schema.validate({ colours = { heart = "#8000ff" } }, device.schemas.config))
  end)

  it("a stored file with odd colours reads clean", function()
    local d = doc(); d.audiocfg.colours = { off = "#ABCDEF", ring = "white", heart = "#ffffff" }
    assert_eq(device.audiocfg_of(d).colours, { off = "#abcdef" })
  end)
end)

describe("a playlist's own lights (#54)", function()
  local ops = library.ops
  it("valid_lights: colour and breathe need their #rrggbb, rainbow and tree none", function()
    assert_eq(ops.valid_lights({ fx = "colour", colour = "#FF0000" }), { fx = "colour", colour = "#ff0000" })
    assert_eq(ops.valid_lights({ fx = "rainbow", colour = "nope" }), { fx = "rainbow" })
    assert_eq(ops.valid_lights({ fx = "tree" }), { fx = "tree" })
    assert_nil(ops.valid_lights({ fx = "breathe" })); assert_nil(ops.valid_lights({ fx = "disco" })); assert_nil(ops.valid_lights("tree"))
  end)

  it("PLAYLIST_UPDATE sets them, false takes them away, and the lights are painted again", function()
    local d = doc()
    local r = v1.on_cmd(d, { name = "PLAYLIST_UPDATE", raw = json.encode({ playlist = { id = "p1", lights = { fx = "breathe", colour = "#00ff00" } } }) })
    assert_eq(r.state.library.playlists.p1.lights, { fx = "breathe", colour = "#00ff00" })
    assert_true(emitted(r, "lights.refresh") ~= nil)
    d.library = r.state.library
    r = v1.on_cmd(d, { name = "PLAYLIST_UPDATE", raw = json.encode({ playlist = { id = "p1", lights = false } }) })
    assert_nil(r.state.library.playlists.p1.lights)
    r = v1.on_cmd(d, { name = "PLAYLIST_UPDATE", raw = json.encode({ playlist = { id = "p1", title = "Q" } }) })
    assert_nil(emitted(r, "lights.refresh"))   -- nothing to repaint for a new title
    r = v1.on_cmd(d, { name = "PLAYLIST_UPDATE", raw = json.encode({ playlist = { id = "p1", lights = { fx = "colour" } } }) })
    assert_nil(r.state)
  end)

  it("the v2 schema takes an effect or false", function()
    local S = library.schemas.playlist_update
    assert_true(schema.validate({ id = "p1", lights = { fx = "tree" } }, S))
    assert_true(schema.validate({ id = "p1", lights = false }, S))
    assert_false(schema.validate({ id = "p1", lights = { fx = "disco" } }, S))
    assert_false(schema.validate({ id = "p1", lights = { fx = "colour", colour = "red" } }, S))
  end)
end)
