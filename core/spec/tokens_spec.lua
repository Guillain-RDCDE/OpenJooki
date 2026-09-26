local tokens = require("services.tokens")

local function doc_with(playlists, toks)
  return { config = { data_dir = "/d" }, nfc = {}, library = { playlists = playlists or {}, tracks = {}, tokens = toks or {} } }
end
local function emitted(r, etype)
  for _, c in ipairs(r.commands) do if c.kind == "emit" and c.event.type == etype then return c.event end end
  return nil
end

describe("services.tokens", function()
  it("maps codes to characters, unknown codes to new.<hex>, none for 0xFFFF", function()
    assert_eq(tokens.star_name(262), "Jooki.Black.Dragon")
    assert_eq(tokens.star_name(528), "G2.Orange")
    assert_eq(tokens.star_name(1030), "test.6")
    assert_eq(tokens.star_name(4095), "new.fff")
    assert_nil(tokens.star_name(65535)); assert_nil(tokens.star_name(nil))
  end)

  it("a known character with a playlist: learns the token, sets nfc, requests playback", function()
    local doc = doc_with({ user_1 = { title = "P", star = "Jooki.Black.Dragon", tracks = {} } })
    local r = tokens.on_tag(doc, { type = "nfc.tag", uid = "04000000B00001", star_code = 262 })
    assert_eq(r.state.nfc, { starId = "Jooki.Black.Dragon", tagId = "04000000B00001" })
    assert_eq(r.state.library.tokens["04000000B00001"], { starId = "Jooki.Black.Dragon", seen = 1 })
    assert_eq(r.commands[1].kind, "files.write"); assert_eq(r.commands[1].path, "/d/tokens.json")
    assert_eq(emitted(r, "system.event").name, "Evt.Character.Detect")
    assert_eq(emitted(r, "playback.request"), { type = "playback.request", playlist = "user_1", source = "token" })
    assert_true(doc.library.tokens["04000000B00001"] == nil, "original document untouched")
  end)

  it("a second token of the same character starts the same playlist (character rule)", function()
    local doc = doc_with({ user_1 = { title = "P", star = "Jooki.Black.Dragon", tracks = {} } }, { ["04000000B00001"] = { starId = "Jooki.Black.Dragon", seen = 3 } })
    local r = tokens.on_tag(doc, { type = "nfc.tag", uid = "04000000B00099", star_code = 262 })
    assert_eq(emitted(r, "playback.request").playlist, "user_1")
  end)

  it("a character without playlist: learned, no playback, 'empty' event", function()
    local doc = doc_with({})
    local r = tokens.on_tag(doc, { type = "nfc.tag", uid = "04000000F00001", star_code = 257 })
    assert_nil(emitted(r, "playback.request"))
    assert_eq(emitted(r, "system.event").name, "Evt.Character.Detect.Empty")
    assert_eq(r.state.library.tokens["04000000F00001"].starId, "Jooki.Fox")
  end)

  it("system tags are routed, not learned; bad tags only log", function()
    local doc = doc_with({})
    local r = tokens.on_tag(doc, { type = "nfc.tag", uid = "04000000000001", star_code = 773 })
    assert_eq(emitted(r, "system.tag").name, "sys.toy_safe_on")
    assert_nil(r.state.library)
    r = tokens.on_tag(doc, { type = "nfc.tag", bad = true, raw = "x" })
    assert_nil(r.state); assert_eq(r.commands[1].kind, "log")
  end)

  it("removing the token clears nfc and asks for a pause; the record tag stops recording", function()
    local r = tokens.on_removed({ nfc = { starId = "Jooki.Fox", tagId = "04" } })
    assert_eq(r.state.nfc, {})
    assert_eq(emitted(r, "playback.pause_request").source, "token")
    r = tokens.on_removed({ nfc = { starId = "sys.record", tagId = "04" } })
    assert_eq(emitted(r, "system.tag").name, "sys.record.stop")
  end)
end)
