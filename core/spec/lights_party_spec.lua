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
