local sounds = require("services.playback.sounds")
local playback = require("services.playback")

local function doc_with()
  local tracks = {}
  for _, id in ipairs({ "a", "b", "c" }) do tracks[id] = { title = "Chapter " .. id, filename = "/d/uploads/" .. id, duration = 100 } end
  return {
    config = { data_dir = "/d", system_dir = "/sys" },
    library = { playlists = { music = { title = "Songs", tracks = { "a", "b", "c" } } }, tracks = tracks, tokens = {} },
    audiocfg = { shuffle_mode = false, repeat_mode = 0 },
    resume = {},
    system = { tracks = { ["Evt.Jooki.Ready"] = { filename = "assets/ready.ogg" }, ["Evt.Power.Low.Warning"] = { filename = "assets/low.ogg" } } },
  }
end

local function topics(r)
  local out = {}
  for _, c in ipairs(r.commands or {}) do
    if c.kind == "bus.publish" then out[#out + 1] = c.topic:gsub("^/j/audio/out/", "") .. " " .. c.payload
    elseif c.kind == "emit" then out[#out + 1] = "emit " .. c.event.type .. (c.event.name and (" " .. c.event.name) or "") .. (c.event.state and (" " .. c.event.state) or "") end
  end
  return out
end

-- Assertion rule: the order of a sound's commands is a rule of the player -- the music paused BEFORE
-- the sound starts, continued BEFORE `after` runs -- so those asserts are positional; `same` (whole set,
-- any order) elsewhere.
local function sorted(list) local out = {} for i, v in ipairs(list) do out[i] = v end table.sort(out) return out end
local function same(r, expected) assert_eq(sorted(topics(r)), sorted(expected)) end

local function apply(doc, r)
  for k, v in pairs(r.state or {}) do doc[k] = v end
  return doc
end

describe("services.playback.sounds — system sounds", function()
  it("pauses the music, plays the sound on stream 3, then continues the music and runs `after`", function()
    local doc = doc_with()
    apply(doc, playback.on_request(doc, { playlist = "music" }))
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    local r = sounds.on_system_event(doc, { name = "Evt.Jooki.Ready", after = { type = "shutdown.request" } })
    -- positional: the music is paused BEFORE the sound starts, and continued BEFORE `after` runs
    assert_eq(topics(r), { "emit lights.event Evt.Jooki.Ready", "pauz 7", "play 3\tfile:///sys/assets/ready.ogg" })
    apply(doc, r)
    r = playback.on_audio(doc, { type = "audio.ended", id = 3 })   -- the engine's report comes through the facade
    assert_eq(topics(r), { "cont 7", "emit shutdown.request" })
    assert_nil(r.state.playback_int.sys); assert_nil(r.state.playback.sys)
  end)

  it("an event without a sound only lights up and runs `after` at once", function()
    local doc = doc_with()
    local r = sounds.on_system_event(doc, { name = "Evt.Character.Detect", after = { type = "x" } })
    same(r, { "emit lights.event Evt.Character.Detect", "emit x" })
  end)

  it("a second sound stops the first and keeps the promise to continue the music", function()
    local doc = doc_with()
    apply(doc, playback.on_request(doc, { playlist = "music" }))
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    apply(doc, sounds.on_system_event(doc, { name = "Evt.Jooki.Ready" }))
    assert_true(doc.playback_int.sys.resume_music)
    doc.playback.state = "paused"                                     -- the engine confirmed the pause meanwhile
    local r = sounds.on_system_event(doc, { name = "Evt.Power.Low.Warning", no_pause = true })
    assert_eq(topics(r), { "emit lights.event Evt.Power.Low.Warning", "stop 3", "play 3\tfile:///sys/assets/low.ogg" })
    assert_true(r.state.playback_int.sys.resume_music); assert_eq(r.state.playback_int.sys.name, "Evt.Power.Low.Warning")
    apply(doc, r)
    assert_nil(sounds.on_sound_audio(doc, {}, "playing"))             -- only the end of the sound matters
    r = sounds.on_sound_audio(doc, {}, "stopped")
    assert_eq(topics(r), { "cont 7" })
    apply(doc, r)
    assert_nil(sounds.on_sound_audio(doc, {}, "ended"))               -- nothing in progress any more
  end)

  it("with nothing playing, no pause and no continue; idle music is left alone", function()
    local doc = doc_with()
    local r = sounds.on_system_event(doc, { name = "Evt.Jooki.Ready" })
    assert_eq(topics(r), { "emit lights.event Evt.Jooki.Ready", "play 3\tfile:///sys/assets/ready.ogg" })
    assert_nil(r.state.playback_int.sys.resume_music)
    apply(doc, r)
    assert_eq(topics(sounds.on_sound_audio(doc, {}, "ended")), {})
  end)

  it("boot keeps the sound catalogue", function()
    assert_eq(sounds.on_boot(nil, { system = { tracks = { x = { filename = "x.ogg" } } } }).state.system.tracks.x.filename, "x.ogg")
    assert_eq(sounds.on_boot(nil, {}).state.system, { tracks = {} })
  end)
end)
