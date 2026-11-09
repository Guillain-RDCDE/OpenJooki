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

describe("playback.on_restart — the knob's back to the start (#40)", function()
  it("the first song, the audiobook's place forgotten, no seek", function()
    local doc = doc_with()
    doc.library.playlists.music.audiobook = true
    doc.resume = { music = { id = "b", pos = 90000 } }
    apply(doc, playback.on_request(doc, { playlist = "music" }))
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    assert_eq(doc.playback.now.index, 2)
    local r = playback.on_restart(doc, { now = 5 })
    apply(doc, r)
    assert_eq(doc.playback.now.index, 1)
    assert_nil(doc.resume.music)
    assert_nil(doc.playback.resume_ms)
    assert_eq(doc.playback.state, "starting")
  end)
  it("nothing loaded, or a song from an app: nothing", function()
    local doc = doc_with()
    assert_nil(playback.on_restart(doc, { now = 5 }))
    doc.playback = { state = "playing", now = { service = "UPNP", uri = "http://x" } }
    assert_nil(playback.on_restart(doc, { now = 5 }))
  end)
end)

describe("services.playback.sounds — system sounds", function()
  it("pauses the music, plays the sound on stream 3, then loads the same song again at its place", function()
    local doc = doc_with()
    apply(doc, playback.on_request(doc, { playlist = "music" }))
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    apply(doc, playback.on_audio(doc, { type = "audio.position", id = 7, ms = 42000 }))
    local uri = doc.playback.now.uri
    local r = sounds.on_system_event(doc, { name = "Evt.Jooki.Ready" })
    -- positional: the music is paused BEFORE the sound starts
    assert_eq(topics(r), { "emit lights.event Evt.Jooki.Ready", "pauz 7", "play 3\tfile:///sys/assets/ready.ogg" })
    apply(doc, r)
    -- the engine's report comes through the facade. "cont 7" would play the sound again: one pipeline
    r = playback.on_audio(doc, { type = "audio.ended", id = 3 })
    assert_eq(topics(r), { "play 7\t" .. uri, "emit playback.changed starting" })
    assert_nil(r.state.playback_int.sys); assert_nil(r.state.playback.sys)
    apply(doc, r)
    assert_nil(doc.playback.song_replaced)                          -- private, and over
    r = playback.on_audio(doc, { type = "audio.playing", id = 7 })
    assert_eq(topics(r)[1], "seek 7\t42000")
  end)

  it("the real engine says paused and stopped for the song when the sound takes its place: it still comes back", function()
    local doc = doc_with()
    apply(doc, playback.on_request(doc, { playlist = "music" }))
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    apply(doc, playback.on_audio(doc, { type = "audio.position", id = 7, ms = 10506 }))
    local uri = doc.playback.now.uri
    apply(doc, sounds.on_system_event(doc, { name = "Evt.Jooki.Ready" }))
    -- what a real Jooki 2 sends, in this order (measured on the device)
    apply(doc, playback.on_audio(doc, { type = "audio.paused", id = 7, ms = 0 }) or {})
    apply(doc, playback.on_audio(doc, { type = "audio.stopped", id = 7, ms = 0 }) or {})
    assert_eq(doc.playback.state, "paused")
    assert_eq(doc.playback.position_ms, 10506)
    assert_nil(playback.on_audio(doc, { type = "audio.playing", id = 3 }))
    local r = playback.on_audio(doc, { type = "audio.ended", id = 3 })
    assert_eq(topics(r), { "play 7\t" .. uri, "emit playback.changed starting" })
    apply(doc, r)
    assert_eq(topics(playback.on_audio(doc, { type = "audio.playing", id = 7 }))[1], "seek 7\t10506")
  end)

  it("Play during the sound: the song comes back and the sound does not stay 'in progress'", function()
    local doc = doc_with()
    apply(doc, playback.on_request(doc, { playlist = "music" }))
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    apply(doc, sounds.on_system_event(doc, { name = "Evt.Jooki.Ready" }))
    apply(doc, playback.on_audio(doc, { type = "audio.paused", id = 7 }) or {})
    local r = playback.on_resume(doc, { now = 10 })
    assert_eq(topics(r)[1], "play 7\t" .. doc.playback.now.uri)
    apply(doc, r)
    assert_nil(doc.playback_int.sys)
  end)

  it("Pause during the sound never reaches the engine, and the song stays paused after it", function()
    for _, confirmed in ipairs({ false, true }) do
      local doc = doc_with()
      apply(doc, playback.on_request(doc, { playlist = "music" }))
      apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
      apply(doc, playback.on_audio(doc, { type = "audio.position", id = 7, ms = 5000 }))
      local uri = doc.playback.now.uri
      apply(doc, sounds.on_system_event(doc, { name = "Evt.Jooki.Ready" }))
      if confirmed then apply(doc, playback.on_audio(doc, { type = "audio.paused", id = 7 }) or {}) end
      local r = playback.on_pause(doc, { source = "token", now = 10 })
      assert_eq(topics(r), {})                                     -- no "pauz": it would freeze the sound
      apply(doc, r)
      assert_eq(doc.playback.state, "paused")
      r = playback.on_audio(doc, { type = "audio.ended", id = 3 })
      assert_eq(topics(r), {})
      apply(doc, r)
      assert_nil(doc.playback_int.sys)
      r = playback.on_resume(doc, { now = 20 })                    -- the token back: the song, at its place
      assert_eq(topics(r), { "play 7\t" .. uri, "emit playback.changed starting" })
      apply(doc, r)
      assert_eq(topics(playback.on_audio(doc, { type = "audio.playing", id = 7 }))[1], "seek 7\t5000")
    end
  end)

  it("before powering off (`after`) the song stays paused instead of starting again", function()
    local doc = doc_with()
    apply(doc, playback.on_request(doc, { playlist = "music" }))
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    apply(doc, sounds.on_system_event(doc, { name = "Evt.Jooki.Ready", after = { type = "shutdown.request" } }))
    assert_eq(topics(playback.on_audio(doc, { type = "audio.ended", id = 3 })), { "emit shutdown.request" })
  end)

  it("#28: a sound that must not stop the music is not played over a song, playing or paused", function()
    for _, state in ipairs({ "playing", "paused" }) do
      local doc = doc_with()
      doc.system.tracks["Evt.Mobile.connect"] = { filename = "assets/connect.ogg" }
      apply(doc, playback.on_request(doc, { playlist = "music" }))
      apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
      if state == "paused" then apply(doc, playback.on_audio(doc, { type = "audio.paused", id = 7 })) end
      local r = sounds.on_system_event(doc, { name = "Evt.Mobile.connect", no_pause = true })
      assert_eq(topics(r), { "emit lights.event Evt.Mobile.connect" })
      assert_nil(r.state)
    end
  end)

  it("#28: with nothing loaded the connect sound still plays", function()
    local doc = doc_with()
    doc.system.tracks["Evt.Mobile.connect"] = { filename = "assets/connect.ogg" }
    local r = sounds.on_system_event(doc, { name = "Evt.Mobile.connect", no_pause = true })
    assert_eq(topics(r), { "emit lights.event Evt.Mobile.connect", "play 3\tfile:///sys/assets/connect.ogg" })
  end)

  it("a paused song under a sound stays paused, and its resume loads it again", function()
    local doc = doc_with()
    apply(doc, playback.on_request(doc, { playlist = "music" }))
    apply(doc, playback.on_audio(doc, { type = "audio.playing", id = 7 }))
    apply(doc, playback.on_audio(doc, { type = "audio.position", id = 7, ms = 9000 }))
    apply(doc, playback.on_audio(doc, { type = "audio.paused", id = 7 }))
    local uri = doc.playback.now.uri
    apply(doc, sounds.on_system_event(doc, { name = "Evt.Power.Low.Warning" }))
    local r = playback.on_audio(doc, { type = "audio.ended", id = 3 })
    assert_eq(topics(r), {})
    apply(doc, r)
    assert_eq(doc.playback.state, "paused")
    r = playback.on_resume(doc, { now = 100 })
    assert_eq(topics(r), { "play 7\t" .. uri, "emit playback.changed starting" })
    apply(doc, r)
    assert_eq(topics(playback.on_audio(doc, { type = "audio.playing", id = 7 }))[1], "seek 7\t9000")
  end)

  it("Spotify has its own daemon: nothing to pause or load again in audio_ctrl", function()
    local doc = doc_with()
    doc.playback = { state = "playing", now = { service = "SPOTIFY", uri = "spotify:x" } }
    local r = sounds.on_system_event(doc, { name = "Evt.Jooki.Ready" })
    assert_eq(topics(r), { "emit lights.event Evt.Jooki.Ready", "play 3\tfile:///sys/assets/ready.ogg" })
    apply(doc, r)
    assert_eq(topics(playback.on_audio(doc, { type = "audio.ended", id = 3 })), {})
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
    local r = sounds.on_system_event(doc, { name = "Evt.Power.Low.Warning" })
    assert_eq(topics(r), { "emit lights.event Evt.Power.Low.Warning", "stop 3", "play 3\tfile:///sys/assets/low.ogg" })
    assert_true(r.state.playback_int.sys.resume_music); assert_eq(r.state.playback_int.sys.name, "Evt.Power.Low.Warning")
    apply(doc, r)
    assert_nil(sounds.on_sound_audio(doc, {}, "playing"))             -- only the end of the sound matters
    r = sounds.on_sound_audio(doc, {}, "stopped")
    assert_eq(topics(r), { "play 7\t" .. doc.playback.now.uri, "emit playback.changed starting" })
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
