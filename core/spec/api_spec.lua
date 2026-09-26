local api = require("api.v2")
local schema = require("api.schema")
local json = require("vendor.json")

describe("api.schema", function()
  local S = { type = "object", required = { "id" }, additionalProperties = false,
              properties = { id = { type = "string", minLength = 1, maxLength = 8, pattern = "^user_" },
                             n = { type = "integer", minimum = 0, maximum = 10 },
                             tracks = { type = "array", items = { type = "string" }, maxItems = 2 },
                             mode = { type = "string", enum = { "a", "b" } },
                             on = { type = "boolean" } } }
  it("accepts a valid object, including empty arrays", function()
    assert_true(schema.validate({ id = "user_1", n = 3, tracks = {}, mode = "a", on = false }, S))
  end)
  it("reports the first problem with its field path", function()
    local ok, f, m = schema.validate({ n = 1 }, S); assert_false(ok); assert_eq(f, "id"); assert_eq(m, "required")
    ok, f = schema.validate({ id = "user_1", n = 1.5 }, S); assert_false(ok); assert_eq(f, "n")
    ok, f = schema.validate({ id = "user_1", n = 11 }, S); assert_false(ok); assert_eq(f, "n")
    ok, f = schema.validate({ id = "nope" }, S); assert_false(ok); assert_eq(f, "id")
    ok, f = schema.validate({ id = "user_1", tracks = { "a", 2 } }, S); assert_false(ok); assert_eq(f, "tracks[2]")
    ok, f = schema.validate({ id = "user_1", tracks = { "a", "b", "c" } }, S); assert_false(ok); assert_eq(f, "tracks")
    ok, f = schema.validate({ id = "user_1", mode = "z" }, S); assert_false(ok); assert_eq(f, "mode")
    ok, f = schema.validate({ id = "user_1", extra = 1 }, S); assert_false(ok); assert_eq(f, "extra")
    ok, f = schema.validate("str", S); assert_false(ok); assert_eq(f, "")
  end)
end)

describe("api.v2", function()
  before_each(function() api.reset(); api.install_builtin("2.0.0-dev") end)

  local function call(msg)
    local ev = api.translate(api.TOPIC_CMD, type(msg) == "string" and msg or json.encode(msg))
    local result = api.handle({ rev = 7, playback = { state = "idle" } }, ev)
    local replies, others = {}, {}
    for _, c in ipairs(result.commands) do
      if c.topic == api.TOPIC_REPLY then replies[#replies + 1] = c.payload else others[#others + 1] = c end
    end
    return replies, others, result
  end

  it("ignores foreign topics", function()
    assert_nil(api.translate("/j/web/input/GET_STATE", "{}"))
  end)

  it("answers state.get with a full state and an ok reply carrying the id", function()
    local replies, others = call({ v = 2, id = "abc", type = "state.get" })
    assert_eq(replies, { { v = 2, id = "abc", ok = true } })
    assert_eq(others[1].topic, api.TOPIC_STATE)
    assert_eq(others[1].payload.full, true)
    assert_eq(others[1].payload.rev, 7)
    assert_eq(others[1].payload.state.playback, { state = "idle" })
    assert_nil(others[1].payload.state.rev)
  end)

  it("rejects bad envelopes with typed errors", function()
    local r = call("not json")
    assert_eq(r[1].ok, false); assert_eq(r[1].error.code, "invalid_argument")
    r = call({ v = 1, type = "state.get" })
    assert_eq(r[1].error.field, "v")
    r = call({ v = 2, type = "nope" })
    assert_eq(r[1].error.field, "type")
    r = call({ v = 2, type = "no.such" })
    assert_eq(r[1].error.code, "not_found")
  end)

  it("validates command payloads and passes them to the command", function()
    api.command("playlist.rename", { type = "object", required = { "id", "title" }, properties = { id = { type = "string" }, title = { type = "string", minLength = 1 } } },
      function(doc, p) return { state = { library = { renamed = p.id } } } end)
    local r = call({ v = 2, id = "1", type = "playlist.rename", payload = { id = "user_1" } })
    assert_eq(r[1].error.field, "payload.title")
    local replies, _, result = call({ v = 2, id = "2", type = "playlist.rename", payload = { id = "user_1", title = "X" } })
    assert_eq(replies[1].ok, true)
    assert_eq(result.state.library.renamed, "user_1")
  end)

  it("turns a command's error into a reply", function()
    api.command("x.fail", nil, function() return nil, { code = "read_only", field = "id", message = "TRASH" } end)
    local r = call({ v = 2, id = "9", type = "x.fail" })
    assert_eq(r[1], { v = 2, id = "9", ok = false, error = { code = "read_only", field = "id", message = "TRASH" } })
  end)

  it("publishes patches with the revision", function()
    local cmds = api.publisher({ rev = 3, playback = { state = "playing" }, device = {} }, { "playback" })
    assert_eq(cmds[1].payload, { v = 2, rev = 3, patch = { playback = { state = "playing" } } })
  end)
end)
